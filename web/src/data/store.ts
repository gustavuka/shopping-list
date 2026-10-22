import { categoryFrom, type Category } from '../domain/category'
import { guessCategory } from '../domain/categoryGuesser'
import { positionAtTop } from '../domain/ordering'
import type { LocalDB, OutboxEntry } from './db'
import { itemDTO, listPayload, newId, type ItemRow, type ListRow } from './rows'

/**
 * The only way the UI mutates data. Every method writes the row and its outbox entry in one
 * IndexedDB transaction, so live queries re-render right away and the change survives a reload.
 * Port of `Data/Local/ListStore.swift`; see docs/sync.md#writes-the-outbox.
 */
export class ListStore {
  /** Called after every local change; `SyncEngine` hooks in here to push the outbox. */
  onLocalChange: () => void = () => {}

  constructor(
    private readonly db: LocalDB,
    readonly userId: string,
  ) {}

  // Lists

  /** The list the app opens into, creating "Groceries" if this account has none. */
  async ensureDefaultList(): Promise<ListRow> {
    const created = await this.db.transaction('rw', [this.db.lists, this.db.outbox], async () => {
      const existing = (await this.db.lists.toArray())
        .filter((l) => !l.deleted_at)
        .sort((a, b) => a.created_at.localeCompare(b.created_at))[0]
      if (existing) return { list: existing, isNew: false }
      const now = new Date().toISOString()
      const list: ListRow = {
        id: newId(), name: 'Groceries', emoji: null, invite_code: null, created_by: this.userId,
        created_at: now, updated_at: now, deleted_at: null, has_password: false, pending: true, serverUs: 0,
      }
      await this.db.lists.put(list)
      await this.enqueue('list', list.id, listPayload(list))
      return { list, isNew: true }
    })
    if (created.isNew) this.onLocalChange()
    return created.list
  }

  /** Soft-deletes a list (e.g. your own empty list after joining your partner's). */
  async deleteList(id: string): Promise<void> {
    await this.mutateList(id, (list) => ({ ...list, deleted_at: new Date().toISOString() }))
  }

  async activeItemCount(listId: string): Promise<number> {
    return (await this.activeItems(listId)).length
  }

  // Items

  async addItem(rawName: string, listId: string): Promise<ItemRow | undefined> {
    const name = rawName.trim().slice(0, 100)
    if (!name) return undefined
    const item = await this.db.transaction('rw', [this.db.items, this.db.outbox], async () => {
      const now = new Date().toISOString()
      const item: ItemRow = {
        id: newId(), list_id: listId, name, quantity: null, note: null, category: guessCategory(name),
        position: positionAtTop((await this.activeItems(listId)).map((i) => i.position)),
        is_checked: false, checked_by: null, checked_at: null, created_by: this.userId, updated_by: this.userId,
        created_at: now, updated_at: now, deleted_at: null, pending: true, serverUs: 0,
      }
      await this.db.items.put(item)
      await this.enqueue('item', item.id, itemDTO(item))
      return item
    })
    this.onLocalChange()
    return item
  }

  async setChecked(id: string, isChecked: boolean): Promise<void> {
    await this.mutateItem(id, (item) =>
      item.is_checked === isChecked
        ? undefined
        : {
            ...item,
            is_checked: isChecked,
            checked_by: isChecked ? this.userId : null,
            checked_at: isChecked ? new Date().toISOString() : null,
          },
    )
  }

  async update(id: string, fields: { name: string; quantity: string; note: string; category: Category }): Promise<void> {
    const name = fields.name.trim().slice(0, 100)
    if (!name) return
    await this.mutateItem(id, (item) => ({
      ...item,
      name,
      quantity: fields.quantity.trim().slice(0, 40) || null,
      note: fields.note.trim().slice(0, 500) || null,
      category: categoryFrom(fields.category),
    }))
  }

  async delete(id: string): Promise<void> {
    await this.mutateItem(id, (item) => ({ ...item, deleted_at: new Date().toISOString() }))
  }

  /** Soft-deletes every checked item — the "done shopping" action. */
  async clearChecked(listId: string): Promise<void> {
    await this.db.transaction('rw', [this.db.items, this.db.outbox], async () => {
      const now = new Date().toISOString()
      for (const item of await this.activeItems(listId)) {
        if (!item.is_checked) continue
        const next: ItemRow = { ...item, deleted_at: now, updated_by: this.userId, pending: true }
        await this.db.items.put(next)
        await this.enqueue('item', next.id, itemDTO(next))
      }
    })
    this.onLocalChange()
  }

  // Private

  private async mutateItem(id: string, change: (item: ItemRow) => ItemRow | undefined): Promise<void> {
    const changed = await this.db.transaction('rw', [this.db.items, this.db.outbox], async () => {
      const item = await this.db.items.get(id)
      const next = item && change(item)
      if (!next) return false
      const row: ItemRow = { ...next, updated_by: this.userId, pending: true }
      await this.db.items.put(row)
      await this.enqueue('item', id, itemDTO(row))
      return true
    })
    if (changed) this.onLocalChange()
  }

  private async mutateList(id: string, change: (list: ListRow) => ListRow): Promise<void> {
    const changed = await this.db.transaction('rw', [this.db.lists, this.db.outbox], async () => {
      const list = await this.db.lists.get(id)
      if (!list) return false
      const row: ListRow = { ...change(list), pending: true }
      await this.db.lists.put(row)
      await this.enqueue('list', id, listPayload(row))
      return true
    })
    if (changed) this.onLocalChange()
  }

  private async activeItems(listId: string): Promise<ItemRow[]> {
    return (await this.db.items.where('list_id').equals(listId).toArray()).filter((i) => !i.deleted_at)
  }

  /** Coalesces: a row has at most one pending entry, holding its latest snapshot. */
  private async enqueue(entity: OutboxEntry['entity'], rowId: string, payload: OutboxEntry['payload']): Promise<void> {
    const existing = await this.db.outbox.get(rowId)
    await this.db.outbox.put(
      existing
        ? { ...existing, payload, revision: existing.revision + 1 }
        : { row_id: rowId, entity, payload, enqueued_at: Date.now(), revision: 0 },
    )
  }
}
