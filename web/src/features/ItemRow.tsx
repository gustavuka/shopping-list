import { useEffect, useRef, useState, type CSSProperties, type PointerEvent } from 'react'
import { categoryFrom, categoryStyle } from '../domain/category'
import type { ItemRow as Item } from '../data/rows'
import { useSyncState } from './session'

/** Swipe further than this (px) to delete; mirrors the iOS swipe action. */
const deleteThreshold = 120

/** One item. Tap the circle to check, tap the name to edit, swipe left to delete. */
export function ItemRow({
  item,
  onToggle,
  onDelete,
  onEdit,
}: {
  item: Item
  onToggle: (item: Item) => void
  onDelete: (item: Item) => void
  onEdit: () => void
}) {
  const { recentlyChanged } = useSyncState()
  const style = categoryStyle[categoryFrom(item.category)]
  const showUnsynced = useDelayedFlag(item.pending, 3000)
  const swipe = useSwipe(() => onDelete(item))

  const label = [item.name, item.quantity, style.name, item.is_checked ? 'in cart' : 'not in cart']
    .filter(Boolean)
    .join(', ')

  return (
    <li
      data-flip={item.id}
      className={`row ${item.is_checked ? 'checked' : ''} ${recentlyChanged.has(item.id) ? 'highlight' : ''}`}
      style={{ '--tint': style.tint } as CSSProperties}
    >
      <div className="row-delete" aria-hidden style={{ opacity: Math.min(1, -swipe.offset / deleteThreshold) }}>
        Delete
      </div>
      <div className="row-content" style={{ transform: swipe.offset ? `translateX(${swipe.offset}px)` : undefined }} {...swipe.handlers}>
        <button
          type="button"
          className="check"
          role="checkbox"
          aria-checked={item.is_checked}
          aria-label={label}
          onClick={() => onToggle(item)}
        >
          <svg viewBox="0 0 24 24" aria-hidden>
            <circle cx="12" cy="12" r="10.5" />
            <path d="M7.5 12.5l3 3 6-6.5" />
          </svg>
        </button>
        <button type="button" className="row-text" onClick={onEdit} aria-label={`Edit ${item.name}`}>
          <span className="name">{item.name}</span>
          {(item.quantity || item.note) && (
            <span className="detail secondary">{[item.quantity, item.note].filter(Boolean).join(' · ')}</span>
          )}
        </button>
        {showUnsynced && (
          <span className="unsynced" role="img" aria-label="Not synced yet" title="Not synced yet">
            ☁︎
          </span>
        )}
        <span className="symbol" aria-hidden>
          {style.symbol}
        </span>
        <button type="button" className="delete-button" aria-label={`Delete ${item.name}`} onClick={() => onDelete(item)}>
          ✕
        </button>
      </div>
    </li>
  )
}

/** True once `value` has been true for `delayMs` (the "pending" marker waits 3 s; docs/sync.md). */
function useDelayedFlag(value: boolean, delayMs: number): boolean {
  const [flag, setFlag] = useState(false)
  useEffect(() => {
    if (!value) return setFlag(false)
    const t = setTimeout(() => setFlag(true), delayMs)
    return () => clearTimeout(t)
  }, [value, delayMs])
  return flag
}

/** Horizontal swipe-left with vertical scroll left to the browser (`touch-action: pan-y`). */
function useSwipe(onCommit: () => void) {
  const [offset, setOffset] = useState(0)
  const start = useRef<{ x: number; y: number; id: number; horizontal?: boolean }>(undefined)

  const handlers = {
    onPointerDown(e: PointerEvent) {
      if (e.pointerType === 'mouse') return
      start.current = { x: e.clientX, y: e.clientY, id: e.pointerId }
    },
    onPointerMove(e: PointerEvent) {
      const s = start.current
      if (!s || s.id !== e.pointerId) return
      const dx = e.clientX - s.x
      const dy = e.clientY - s.y
      if (s.horizontal === undefined && Math.hypot(dx, dy) > 8) {
        s.horizontal = Math.abs(dx) > Math.abs(dy)
        if (s.horizontal) (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
      }
      if (s.horizontal) setOffset(Math.min(0, dx))
    },
    onPointerUp() {
      const commit = offset < -deleteThreshold
      start.current = undefined
      setOffset(0)
      if (commit) onCommit()
    },
    onPointerCancel() {
      start.current = undefined
      setOffset(0)
    },
  }
  return { offset, handlers }
}
