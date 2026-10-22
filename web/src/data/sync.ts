import type { RealtimeChannel } from '@supabase/supabase-js'
import { canMerge, type ActivityEvent, type ActivityVerb } from '../domain/activity'
import { decide } from './conflict'
import type { LocalDB, OutboxEntry } from './db'
import { RemoteError, type Remote } from './remote'
import { fromServer, timestampMicros, type ItemDTO, type ListDTO } from './rows'

export interface SyncState {
  pendingCount: number
  lastSyncedAt?: number
  isSyncing: boolean
  isOnline: boolean
  /** Set when the server refused a change; the row was restored to the server's version. */
  lastRejection?: number
  /** Most recent change made by someone else, for the activity pill. */
  latestActivity?: ActivityEvent
  /** Rows changed by someone else in the last moment, for the row highlight. */
  recentlyChanged: ReadonlySet<string>
  memberNames: ReadonlyMap<string, string>
}

/**
 * Reconciles IndexedDB with Supabase (docs/sync.md): pushes the outbox, pulls deltas, applies
 * Realtime events, and reports status + partner activity. Port of `Data/Sync/SyncEngine.swift`.
 * The UI subscribes through `useSyncExternalStore(engine.subscribe, engine.getState)`.
 */
export class SyncEngine {
  private state: SyncState = {
    pendingCount: 0,
    isSyncing: false,
    isOnline: navigator.onLine,
    recentlyChanged: new Set(),
    memberNames: new Map(),
  }
  private listeners = new Set<() => void>()

  private syncRun?: Promise<void>
  private pushRun?: Promise<void>
  private needsAnotherPush = false
  private debounce?: ReturnType<typeof setTimeout>
  private retry?: ReturnType<typeof setTimeout>
  private retryAttempt = 0
  private channels = new Map<string, RealtimeChannel>()
  private isShutDown = false

  constructor(
    private readonly db: LocalDB,
    private readonly remote: Remote,
    readonly userId: string,
  ) {
    void this.refreshPendingCount()
  }

  // Observable state

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  getState = (): SyncState => this.state

  private set(patch: Partial<SyncState>): void {
    this.state = { ...this.state, ...patch }
    this.listeners.forEach((l) => l())
  }

  // Lifecycle

  /** Push, then pull and (re)subscribe. Safe to call repeatedly; concurrent calls share one run. */
  start(): Promise<void> {
    this.syncRun ??= this.syncNow().finally(() => (this.syncRun = undefined))
    return this.syncRun
  }

  /** Ends this engine for good (sign-out): nothing it scheduled may run with the old account. */
  shutdown(): void {
    this.isShutDown = true
    clearTimeout(this.debounce)
    clearTimeout(this.retry)
    for (const channel of this.channels.values()) void this.remote.unsubscribe(channel)
    this.channels.clear()
    this.listeners.clear()
  }

  setOnline(isOnline: boolean): void {
    this.set({ isOnline })
    if (isOnline) void this.start()
  }

  private async syncNow(): Promise<void> {
    if (this.isShutDown) return
    this.set({ isSyncing: true })
    try {
      await this.push()
      await this.pull()
    } finally {
      this.set({ isSyncing: false })
    }
  }

  /** Called by `ListStore` after every local change. Debounced so rapid taps become one request. */
  kick = (): void => {
    void this.refreshPendingCount()
    clearTimeout(this.debounce)
    this.debounce = setTimeout(() => void this.push(), 250)
  }

  // Joining & room passwords

  /** Joins a room by code + password and pulls its items. Returns the joined list's id. */
  async join(inviteCode: string, password: string): Promise<string> {
    const list = await this.remote.joinList(inviteCode.trim().toUpperCase(), password)
    await this.applyLists([list], false)
    await this.pull()
    return list.id
  }

  /** Sets (or changes) the room password. Pushes the list first so it exists on the server. */
  async setPassword(listId: string, password: string): Promise<void> {
    await this.push()
    await this.remote.setListPassword(listId, password)
    await this.db.lists.update(listId, { has_password: true })
  }

  async updateDisplayName(name: string): Promise<void> {
    const trimmed = name.trim()
    if (!trimmed) return
    await this.remote.updateDisplayName(trimmed, this.userId)
    this.set({ memberNames: new Map(this.state.memberNames).set(this.userId, trimmed) })
  }

  // Push

  push(): Promise<void> {
    if (this.isShutDown) return Promise.resolve()
    if (this.pushRun) {
      this.needsAnotherPush = true
      return this.pushRun
    }
    this.pushRun = (async () => {
      do {
        this.needsAnotherPush = false
        await this.drainOutbox()
      } while (this.needsAnotherPush && !this.isShutDown)
    })().finally(() => {
      this.pushRun = undefined
      void this.refreshPendingCount()
    })
    return this.pushRun
  }

  private async drainOutbox(): Promise<void> {
    const entries = await this.db.outbox.orderBy('enqueued_at').toArray()
    if (!entries.length) return
    try {
      // Lists first: items reference them.
      await this.pushLists(entries.filter((e) => e.entity === 'list'))
      await this.pushItems(entries.filter((e) => e.entity === 'item'))
      this.retryAttempt = 0
    } catch (error) {
      console.info('Push failed, will retry:', error)
      this.scheduleRetry()
    }
  }

  private async pushItems(batch: OutboxEntry[]): Promise<void> {
    if (!batch.length) return
    try {
      const saved = await this.remote.upsertItems(batch.map((e) => e.payload as ItemDTO))
      await this.complete(batch, saved, 'item')
    } catch (error) {
      if (!(error instanceof RemoteError) || error.kind !== 'rejected') throw error
      if (batch.length > 1) {
        // Isolate the bad row so one rejection doesn't block everything else.
        for (const one of batch) await this.pushItems([one])
      } else {
        await this.rejectItem(batch[0]!, error)
      }
    }
  }

  private async pushLists(batch: OutboxEntry[]): Promise<void> {
    if (!batch.length) return
    try {
      const saved = await this.remote.upsertLists(batch.map((e) => e.payload as ListDTO))
      await this.complete(batch, saved, 'list')
    } catch (error) {
      if (!(error instanceof RemoteError) || error.kind !== 'rejected') throw error
      console.error('List write rejected:', error)
      await this.db.outbox.bulkDelete(batch.map((e) => e.row_id))
      this.set({ lastRejection: Date.now() })
    }
  }

  /**
   * Retires entries whose revision didn't change while the request was in flight and adopts the
   * server's version of those rows. Entries edited mid-flight stay queued for the next round.
   */
  private async complete(batch: OutboxEntry[], saved: (ItemDTO | ListDTO)[], entity: 'item' | 'list'): Promise<void> {
    const byId = new Map(saved.map((row) => [row.id, row]))
    const table = entity === 'item' ? this.db.items : this.db.lists
    await this.db.transaction('rw', [this.db.outbox, table], async () => {
      for (const sent of batch) {
        const current = await this.db.outbox.get(sent.row_id)
        if (!current) continue // wiped (sign-out) while we were awaiting the network
        if (current.revision !== sent.revision) {
          this.needsAnotherPush = true
          continue
        }
        await this.db.outbox.delete(sent.row_id)
        const server = byId.get(sent.row_id)
        if (server) await table.put(fromServer(server) as never)
      }
    })
  }

  private async rejectItem(entry: OutboxEntry, error: unknown): Promise<void> {
    console.error(`Item write rejected for ${entry.row_id}; restoring server version`, error)
    await this.db.outbox.delete(entry.row_id)
    this.set({ lastRejection: Date.now() })
    try {
      const [server] = await this.remote.fetchItemsById([entry.row_id])
      if (server) await this.db.items.put(fromServer(server))
      else await this.db.items.delete(entry.row_id) // never made it to the server and never will
    } catch {
      await this.db.items.update(entry.row_id, { pending: false })
    }
  }

  private scheduleRetry(): void {
    if (this.retry !== undefined) return
    this.retryAttempt += 1
    const delay = Math.min(60, 2 ** Math.min(this.retryAttempt - 1, 6)) // 1, 2, 4 … 60 s
    this.retry = setTimeout(() => {
      this.retry = undefined
      void this.push()
    }, delay * 1000)
  }

  // Pull

  async pull(): Promise<void> {
    try {
      const lists = await this.remote.fetchLists()
      await this.applyLists(lists, true)

      const activeIds = lists.filter((l) => !l.deleted_at).map((l) => l.id)
      await this.subscribeTo(activeIds) // before fetching items, so nothing falls in the gap

      for (const listId of activeIds) {
        const cursorKey = `cursor:${listId}`
        const cursor = (await this.db.meta.get(cursorKey))?.value
        const items = await this.remote.fetchItems(listId, cursor)
        await this.applyItems(items, false)
        // Only delta fetches advance cursors; rows come back ordered by updated_at.
        const newest = items.at(-1)?.updated_at
        if (newest) await this.db.meta.put({ key: cursorKey, value: newest })
      }

      const profiles = await this.remote.fetchProfiles()
      this.set({ memberNames: new Map(profiles.map((p) => [p.id, p.display_name])), lastSyncedAt: Date.now() })
    } catch (error) {
      console.info('Pull failed:', error)
    }
  }

  // Realtime

  private async subscribeTo(listIds: string[]): Promise<void> {
    const wanted = new Set(listIds)
    for (const [listId, channel] of this.channels) {
      // Drop channels for lists we left, and dead sockets (e.g. a PWA resumed from the background).
      if (!wanted.has(listId) || channel.state !== 'joined') {
        this.channels.delete(listId)
        void this.remote.unsubscribe(channel)
      }
    }
    await Promise.all(
      listIds
        .filter((id) => !this.channels.has(id))
        .map(async (listId) => {
          const channel = await this.remote.subscribe(listId, (change) => {
            // Cursors only advance on delta fetches: if an event were ever dropped, the next fetch
            // still covers it. Re-applying already-seen rows is a cheap no-op.
            if (change.kind === 'item') void this.applyItems([change.row], true)
            else void this.applyLists([change.row], false)
          })
          if (this.isShutDown) void this.remote.unsubscribe(channel)
          else this.channels.set(listId, channel)
        }),
    )
  }

  // Applying remote rows

  private async applyItems(rows: ItemDTO[], live: boolean): Promise<void> {
    if (!rows.length || this.isShutDown) return
    const events: { row: ItemDTO; isNew: boolean; wasChecked?: boolean }[] = []
    await this.db.transaction('rw', this.db.items, async () => {
      for (const row of rows) {
        const local = await this.db.items.get(row.id)
        const decision = decide(local, timestampMicros(row.updated_at))
        if (decision === 'skip') continue
        await this.db.items.put(fromServer(row))
        if (live && row.updated_by !== this.userId) {
          events.push({ row, isNew: decision === 'insert', wasChecked: local?.is_checked })
        }
      }
    })
    for (const e of events) this.noteActivity(e.row, e.isNew, e.wasChecked)
  }

  private async applyLists(rows: ListDTO[], removeMissing: boolean): Promise<void> {
    if (this.isShutDown) return
    await this.db.transaction('rw', [this.db.lists, this.db.items, this.db.meta], async () => {
      for (const row of rows) {
        const local = await this.db.lists.get(row.id)
        const decision = decide(local, timestampMicros(row.updated_at))
        if (decision !== 'skip') {
          await this.db.lists.put(fromServer({ ...row, has_password: row.has_password ?? false }))
        } else if (local) {
          // Server-maintained fields aren't part of conflict resolution: adopt them whenever we learn them.
          const patch: Partial<ListDTO> = {}
          if (!local.invite_code && row.invite_code) patch.invite_code = row.invite_code
          if (row.has_password && !local.has_password) patch.has_password = true
          if (Object.keys(patch).length) await this.db.lists.update(row.id, patch)
        }
      }

      if (removeMissing) {
        // Lists we synced before but can no longer see (left, or removed) disappear locally.
        const serverIds = new Set(rows.map((r) => r.id))
        const gone = (await this.db.lists.toArray()).filter((l) => !serverIds.has(l.id) && !l.pending && l.serverUs > 0)
        for (const list of gone) {
          await this.db.items.where('list_id').equals(list.id).delete()
          await this.db.lists.delete(list.id)
          await this.db.meta.delete(`cursor:${list.id}`)
        }
      }
    })
  }

  private noteActivity(row: ItemDTO, isNew: boolean, wasChecked: boolean | undefined): void {
    const verb: ActivityVerb = row.deleted_at
      ? 'removed'
      : isNew
        ? 'added'
        : wasChecked === false && row.is_checked
          ? 'checked'
          : wasChecked === true && !row.is_checked
            ? 'unchecked'
            : 'edited'

    let event: ActivityEvent = {
      id: crypto.getRandomValues(new Uint32Array(1))[0]!.toString(36),
      actorId: row.updated_by,
      actorName: this.state.memberNames.get(row.updated_by) || 'Your partner',
      verb,
      itemNames: [row.name],
      date: Date.now(),
    }
    const latest = this.state.latestActivity
    if (latest && canMerge(latest, event)) event = { ...event, itemNames: [...latest.itemNames, row.name] }

    this.set({ latestActivity: event, recentlyChanged: new Set(this.state.recentlyChanged).add(row.id) })
    setTimeout(() => {
      const next = new Set(this.state.recentlyChanged)
      next.delete(row.id)
      this.set({ recentlyChanged: next })
    }, 1200)
  }

  // Helpers

  private async refreshPendingCount(): Promise<void> {
    const pendingCount = await this.db.outbox.count()
    if (pendingCount !== this.state.pendingCount) this.set({ pendingCount })
  }
}
