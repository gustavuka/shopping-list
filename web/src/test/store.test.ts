import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it } from 'vitest'
import { LocalDB } from '../data/db'
import { ListStore } from '../data/store'

const me = '00000000-0000-4000-8000-000000000001'

describe('ListStore', () => {
  let db: LocalDB
  let store: ListStore
  let changes: number

  beforeEach(async () => {
    db = new LocalDB(`test-${Math.random()}`)
    store = new ListStore(db, me)
    changes = 0
    store.onLocalChange = () => changes++
  })

  it('creates one default list and enqueues it', async () => {
    const a = await store.ensureDefaultList()
    const b = await store.ensureDefaultList()
    expect(b.id).toBe(a.id)
    expect(await db.lists.count()).toBe(1)
    expect((await db.outbox.get(a.id))?.payload).not.toHaveProperty('invite_code')
    expect(changes).toBe(1)
  })

  it('adds items on top with a guessed category, pending until pushed', async () => {
    const list = await store.ensureDefaultList()
    const milk = await store.addItem('  Milk ', list.id)
    const bread = await store.addItem('Bread', list.id)
    expect(milk).toMatchObject({ name: 'Milk', category: 'dairy', pending: true, created_by: me })
    expect(bread!.position).toBeLessThan(milk!.position)
    expect(await store.addItem('   ', list.id)).toBeUndefined()
    expect(await db.outbox.count()).toBe(3)
  })

  it('coalesces repeated edits of a row into one outbox entry with a bumped revision', async () => {
    const list = await store.ensureDefaultList()
    const item = (await store.addItem('Eggs', list.id))!
    await store.setChecked(item.id, true)
    await store.setChecked(item.id, false)
    await store.setChecked(item.id, true)
    const entry = await db.outbox.get(item.id)
    expect(entry?.revision).toBe(3)
    expect(entry?.payload).toMatchObject({ is_checked: true, checked_by: me })
    expect(entry?.payload).not.toHaveProperty('pending')
  })

  it('soft-deletes checked items on clear', async () => {
    const list = await store.ensureDefaultList()
    const a = (await store.addItem('Apples', list.id))!
    await store.addItem('Beer', list.id)
    await store.setChecked(a.id, true)
    await store.clearChecked(list.id)
    expect((await db.items.get(a.id))?.deleted_at).toBeTruthy()
    expect(await store.activeItemCount(list.id)).toBe(1)
  })

  it('wipes everything', async () => {
    const list = await store.ensureDefaultList()
    await store.addItem('Tea', list.id)
    await db.wipe()
    expect(await db.items.count()).toBe(0)
    expect(await db.outbox.count()).toBe(0)
  })
})
