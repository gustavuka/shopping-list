import Dexie, { type EntityTable } from 'dexie'
import type { ItemDTO, ItemRow, ListDTO, ListRow } from './rows'

/** One pending write per row, holding its latest snapshot (docs/sync.md#writes-the-outbox). */
export interface OutboxEntry {
  row_id: string
  entity: 'item' | 'list'
  payload: Partial<ItemDTO> | Partial<ListDTO>
  enqueued_at: number
  /** Bumped whenever the payload is replaced, so a push only retires the version it sent. */
  revision: number
}

/** Small key-value table: sync cursors, the owner of the local data. */
export interface MetaEntry {
  key: string
  value: string
}

/**
 * The local store (IndexedDB) — the web counterpart of the SwiftData container.
 * The UI reads only from here (`useLiveQuery`); `ListStore` and `SyncEngine` are its only writers.
 */
export class LocalDB extends Dexie {
  items!: EntityTable<ItemRow, 'id'>
  lists!: EntityTable<ListRow, 'id'>
  outbox!: EntityTable<OutboxEntry, 'row_id'>
  meta!: EntityTable<MetaEntry, 'key'>

  constructor(name = 'shopping-list') {
    super(name)
    this.version(1).stores({
      items: 'id, list_id',
      lists: 'id',
      outbox: 'row_id, enqueued_at',
      meta: 'key',
    })
  }

  /** Removes everything stored locally — on sign-out, so the next account starts clean. */
  async wipe(): Promise<void> {
    await this.transaction('rw', [this.items, this.lists, this.outbox, this.meta], async () => {
      await Promise.all([this.items.clear(), this.lists.clear(), this.outbox.clear(), this.meta.clear()])
    })
  }
}

export const db = new LocalDB()
