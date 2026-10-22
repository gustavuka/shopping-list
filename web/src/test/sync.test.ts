import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it } from 'vitest'
import { LocalDB } from '../data/db'
import { RemoteError, type Remote, type RemoteChange } from '../data/remote'
import type { ItemDTO, ListDTO } from '../data/rows'
import { ListStore } from '../data/store'
import { SyncEngine } from '../data/sync'

const me = '00000000-0000-4000-8000-000000000001'
const partner = '00000000-0000-4000-8000-000000000002'

/** In-memory server: stamps updated_at with microseconds like Postgres, echoes nothing by itself. */
class FakeRemote {
  items = new Map<string, ItemDTO>()
  lists = new Map<string, ListDTO>()
  clock = Date.UTC(2026, 9, 22) * 1000
  rejectNames = new Set<string>()
  /** Runs while an upsert is "in flight". */
  duringUpsert?: () => Promise<void>
  live?: (c: RemoteChange) => void

  private stamp(): string {
    this.clock += 1
    const ms = Math.floor(this.clock / 1000)
    const us = String(this.clock % 1000).padStart(3, '0')
    return new Date(ms).toISOString().replace('Z', `${us}+00:00`)
  }
  async upsertLists(lists: Partial<ListDTO>[]) {
    return lists.map((l) => {
      const row = { has_password: false, invite_code: 'ABC234', ...l, updated_at: this.stamp() } as ListDTO
      this.lists.set(row.id, row)
      return row
    })
  }
  async upsertItems(items: Partial<ItemDTO>[]) {
    await this.duringUpsert?.()
    if (items.some((i) => this.rejectNames.has(i.name!))) throw new RemoteError('23514 check', 'rejected')
    return items.map((i) => {
      const row = { ...i, updated_at: this.stamp() } as ItemDTO
      this.items.set(row.id, row)
      return row
    })
  }
  async fetchLists() {
    return [...this.lists.values()]
  }
  async fetchItems(listId: string) {
    return [...this.items.values()].filter((i) => i.list_id === listId)
  }
  async fetchItemsById(ids: string[]) {
    return ids.flatMap((id) => (this.items.has(id) ? [this.items.get(id)!] : []))
  }
  async fetchProfiles() {
    return [{ id: partner, display_name: 'Ana' }]
  }
  subscribed = new Set<string>()
  async subscribe(listId: string, onChange: (c: RemoteChange) => void) {
    this.subscribed.add(listId)
    this.live = onChange
    return { state: 'joined' } as never
  }
  async unsubscribe() {}
  /** A change made on the partner's phone, delivered over Realtime. */
  partnerEdit(id: string, patch: Partial<ItemDTO>) {
    const row = { ...this.items.get(id)!, ...patch, updated_by: partner, updated_at: this.stamp() }
    this.items.set(id, row)
    if (this.subscribed.has(row.list_id)) this.live?.({ kind: 'item', row })
  }
}

describe('SyncEngine', () => {
  let db: LocalDB
  let remote: FakeRemote
  let store: ListStore
  let sync: SyncEngine

  beforeEach(() => {
    db = new LocalDB(`sync-${Math.random()}`)
    remote = new FakeRemote()
    store = new ListStore(db, me)
    sync = new SyncEngine(db, remote as unknown as Remote, me)
  })

  it('pushes the outbox and adopts the server rows', async () => {
    const list = await store.ensureDefaultList()
    const item = (await store.addItem('Milk', list.id))!
    await sync.push()
    expect(await db.outbox.count()).toBe(0)
    const local = await db.items.get(item.id)
    expect(local?.pending).toBe(false)
    expect(local?.updated_at).toBe(remote.items.get(item.id)?.updated_at)
    expect((await db.lists.get(list.id))?.invite_code).toBe('ABC234')
  })

  it('keeps an edit made while the push was in flight', async () => {
    const list = await store.ensureDefaultList()
    const item = (await store.addItem('Eggs', list.id))!
    await sync.push()
    remote.duringUpsert = async () => {
      remote.duringUpsert = undefined
      await store.setChecked(item.id, false) // uncheck lands mid-flight
    }
    await store.setChecked(item.id, true)
    await sync.push()
    expect(await db.outbox.count()).toBe(0)
    expect(remote.items.get(item.id)?.is_checked).toBe(false)
    expect((await db.items.get(item.id))?.is_checked).toBe(false)
  })

  it('applies partner changes live, reports activity, and skips its own echoes', async () => {
    const list = await store.ensureDefaultList()
    const item = (await store.addItem('Bread', list.id))!
    await sync.start()
    await sync.start() // second pull: our own rows come back equal and are skipped
    remote.partnerEdit(item.id, { is_checked: true, checked_by: partner })
    await new Promise((r) => setTimeout(r, 20))
    expect((await db.items.get(item.id))?.is_checked).toBe(true)
    expect(sync.getState().latestActivity).toMatchObject({ actorName: 'Ana', verb: 'checked', itemNames: ['Bread'] })
    expect(sync.getState().recentlyChanged.has(item.id)).toBe(true)
  })

  it('listens live to a list created after the first pull (first launch on a new device)', async () => {
    await sync.start() // nothing on the server yet: no channels
    const list = await store.ensureDefaultList()
    const item = (await store.addItem('Coffee', list.id))!
    await sync.push()
    await new Promise((r) => setTimeout(r, 20))
    expect(remote.subscribed.has(list.id)).toBe(true)
    remote.partnerEdit(item.id, { is_checked: true, checked_by: partner })
    await new Promise((r) => setTimeout(r, 20))
    expect((await db.items.get(item.id))?.is_checked).toBe(true)
  })

  it('does not let a remote change overwrite a pending local edit', async () => {
    const list = await store.ensureDefaultList()
    const item = (await store.addItem('Tea', list.id))!
    await sync.push()
    await store.update(item.id, { name: 'Green tea', quantity: '', note: '', category: 'pantry' })
    remote.partnerEdit(item.id, { name: 'Black tea' })
    await new Promise((r) => setTimeout(r, 20))
    expect((await db.items.get(item.id))?.name).toBe('Green tea')
  })

  it('drops a rejected write and restores the server version', async () => {
    const list = await store.ensureDefaultList()
    const ok = (await store.addItem('Rice', list.id))!
    remote.rejectNames.add('Bad')
    const bad = (await store.addItem('Bad', list.id))!
    await sync.push()
    expect(await db.outbox.count()).toBe(0)
    expect(await db.items.get(bad.id)).toBeUndefined() // never reached the server
    expect((await db.items.get(ok.id))?.pending).toBe(false)
    expect(sync.getState().lastRejection).toBeDefined()
  })
})
