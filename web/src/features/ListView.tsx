import { useLiveQuery } from 'dexie-react-hooks'
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { activityMessage } from '../domain/activity'
import { categories, categoryFrom, categoryStyle } from '../domain/category'
import { db } from '../data/db'
import type { ItemRow as Item, ListRow } from '../data/rows'
import { haptic } from '../ui/haptics'
import { useFlip } from '../ui/motion'
import { ItemEditor } from './ItemEditor'
import { ItemRow } from './ItemRow'
import { useSession, useSyncState } from './session'
import type { SessionSheet } from './SessionRoot'

/** How long a just-checked row stays put so the check lands visibly before it moves to "In cart". */
const settleMs = 350

export function ListView({
  list,
  lists,
  onSelect,
  onShow,
}: {
  list: ListRow
  lists: ListRow[]
  onSelect: (id: string) => void
  onShow: (sheet: SessionSheet) => void
}) {
  const { store } = useSession()
  const items = useLiveQuery(() => db.items.where('list_id').equals(list.id).toArray(), [list.id])
  const [settling, setSettling] = useState<ReadonlySet<string>>(new Set())
  const [editingId, setEditingId] = useState<string>()
  const [celebrate, setCelebrate] = useState(false)
  const content = useRef<HTMLDivElement>(null)
  useFlip(content)

  const { sections, inCart, remaining } = useMemo(() => {
    const active = (items ?? []).filter((i) => !i.deleted_at)
    const toBuy = active.filter((i) => !i.is_checked || settling.has(i.id))
    const sections = categories
      .map((category) => ({
        category,
        items: toBuy.filter((i) => categoryFrom(i.category) === category).sort((a, b) => a.position - b.position),
      }))
      .filter((s) => s.items.length)
    const inCart = active
      .filter((i) => i.is_checked && !settling.has(i.id))
      .sort((a, b) => (b.checked_at ?? '').localeCompare(a.checked_at ?? ''))
    return { sections, inCart, remaining: active.filter((i) => !i.is_checked).length }
  }, [items, settling])

  function toggle(item: Item) {
    const checking = !item.is_checked
    haptic(checking ? 'success' : 'light')
    void store.setChecked(item.id, checking)
    if (!checking) return
    const isLast = remaining === 1
    setSettling((s) => new Set(s).add(item.id))
    setTimeout(() => {
      setSettling((s) => {
        const next = new Set(s)
        next.delete(item.id)
        return next
      })
      if (isLast) {
        setCelebrate(true)
        setTimeout(() => setCelebrate(false), 1600)
      }
    }, settleMs)
  }

  function remove(item: Item) {
    haptic('rigid')
    void store.delete(item.id)
  }

  const editing = items?.find((i) => i.id === editingId && !i.deleted_at)

  return (
    <div className="list-screen">
      <header className="toolbar glass">
        <label className="list-picker">
          <h1>
            {list.emoji ? `${list.emoji} ` : ''}
            {list.name}
            <span className="chevron" aria-hidden>
              ⌄
            </span>
          </h1>
          <select
            aria-label="Switch list"
            value={list.id}
            onChange={(e) => (e.target.value === 'join' ? onShow({ kind: 'join' }) : onSelect(e.target.value))}
          >
            {lists.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name}
              </option>
            ))}
            <option value="join">Join a list…</option>
          </select>
        </label>
        <span className="count" aria-live="polite">
          {remaining ? `${remaining} left` : ''}
        </span>
        <button type="button" className="icon-button" aria-label="Share list" onClick={() => onShow({ kind: 'share' })}>
          <ShareIcon />
        </button>
        <button type="button" className="icon-button" aria-label="Settings" onClick={() => onShow({ kind: 'settings' })}>
          <GearIcon />
        </button>
      </header>

      <StatusPill />

      <div className="content" ref={content}>
        {items && !sections.length && !inCart.length && (
          <div className="empty">
            <div className="empty-symbol">🛒</div>
            <h2>Nothing to buy</h2>
            <p className="secondary">Add what you're out of below. Your partner sees it instantly.</p>
          </div>
        )}

        {sections.map(({ category, items }) => (
          <section key={category} className="section">
            <h2 className="section-header">
              <span aria-hidden>{categoryStyle[category].symbol}</span> {categoryStyle[category].name}
            </h2>
            <ul className="rows">
              {items.map((item) => (
                <ItemRow key={item.id} item={item} onToggle={toggle} onDelete={remove} onEdit={() => setEditingId(item.id)} />
              ))}
            </ul>
          </section>
        ))}

        {inCart.length > 0 && (
          <section className="section in-cart">
            <h2 className="section-header">
              <span aria-hidden>✓</span> In cart
              <button type="button" className="link clear" onClick={() => (haptic('rigid'), store.clearChecked(list.id))}>
                Clear
              </button>
            </h2>
            <ul className="rows">
              {inCart.map((item) => (
                <ItemRow key={item.id} item={item} onToggle={toggle} onDelete={remove} onEdit={() => setEditingId(item.id)} />
              ))}
            </ul>
          </section>
        )}
      </div>

      <AddBar listId={list.id} />

      {celebrate && (
        <div className="celebration glass" role="status">
          <span className="celebration-symbol">🎉</span>
          All done!
        </div>
      )}
      {editing && <ItemEditor item={editing} onClose={() => setEditingId(undefined)} />}
    </div>
  )
}

/** Bottom glass bar. Stays focused after adding, for rapid entry. */
function AddBar({ listId }: { listId: string }) {
  const { store } = useSession()
  const [name, setName] = useState('')

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!name.trim()) return
    haptic('light')
    void store.addItem(name, listId)
    setName('')
  }

  return (
    <form className="add-bar glass" onSubmit={submit}>
      <input
        className="add-input"
        placeholder="Add an item"
        aria-label="Add an item"
        enterKeyHint="done"
        autoComplete="off"
        maxLength={100}
        value={name}
        onChange={(e) => setName(e.target.value)}
      />
      <button type="submit" className="add-button" aria-label="Add" disabled={!name.trim()}>
        +
      </button>
    </form>
  )
}

/** Offline / rejected / partner activity — calm, small, never blocking (docs/sync.md#ui-states). */
function StatusPill() {
  const { isOnline, lastRejection, latestActivity } = useSyncState()
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    const t = setTimeout(() => setNow(Date.now()), 2100)
    return () => clearTimeout(t)
  }, [now, lastRejection, latestActivity])

  let pill: { text: string; tone?: 'error' } | undefined
  if (lastRejection && Date.now() - lastRejection < 4000) pill = { text: "Couldn't save a change", tone: 'error' }
  else if (latestActivity && Date.now() - latestActivity.date < 2000) pill = { text: activityMessage(latestActivity) }
  else if (!isOnline) pill = { text: 'Offline — changes will sync' }

  return (
    <div className="status-slot" aria-live="polite">
      {pill && (
        <div key={pill.text} className={`status-pill glass ${pill.tone ?? ''}`}>
          {pill.text}
        </div>
      )}
    </div>
  )
}

function ShareIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 3v12M7 8l5-5 5 5M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" />
    </svg>
  )
}

function GearIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </svg>
  )
}
