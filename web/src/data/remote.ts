import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import type { ItemDTO, ListDTO, ProfileDTO } from './rows'

/** A failed request. `rejected` = the server refused it (don't retry); otherwise transient. */
export class RemoteError extends Error {
  constructor(
    message: string,
    readonly kind: 'rejected' | 'transient',
  ) {
    super(message)
  }
}

/** `join_list` refused: wrong code or password (indistinguishable on purpose), or too many tries. */
export class JoinError extends Error {
  constructor(readonly reason: 'invalid' | 'throttled') {
    super(`join_list: ${reason}`)
  }
}

export type RemoteChange = { kind: 'item'; row: ItemDTO } | { kind: 'list'; row: ListDTO }

/** Supabase (PostgREST + Realtime) calls used by the sync engine. Port of `SupabaseRemote.swift`. */
export class Remote {
  constructor(private readonly client: SupabaseClient) {}

  // Writes

  async upsertLists(lists: Partial<ListDTO>[]): Promise<ListDTO[]> {
    // One request per list: lists without a known invite_code omit that key, and a bulk upsert
    // would fill missing keys with null. Lists are few, so this costs nothing.
    const result: ListDTO[] = []
    for (const list of lists) {
      result.push(...unwrap(await this.client.from('lists').upsert(list, { onConflict: 'id' }).select()))
    }
    return result
  }

  async upsertItems(items: Partial<ItemDTO>[]): Promise<ItemDTO[]> {
    if (!items.length) return []
    return unwrap(await this.client.from('items').upsert(items, { onConflict: 'id' }).select())
  }

  async updateDisplayName(name: string, userId: string): Promise<void> {
    unwrap(await this.client.from('profiles').update({ display_name: name }).eq('id', userId))
  }

  /** The RPC returns failures instead of raising them, so the server can record the attempt. */
  async joinList(inviteCode: string, password: string): Promise<ListDTO> {
    const result = unwrap<{ list?: ListDTO; error?: 'invalid' | 'throttled' }>(
      await this.client.rpc('join_list', { p_invite_code: inviteCode, p_password: password }),
    )
    if (!result.list) throw new JoinError(result.error === 'throttled' ? 'throttled' : 'invalid')
    return result.list
  }

  async setListPassword(listId: string, password: string): Promise<void> {
    unwrap(await this.client.rpc('set_list_password', { p_list_id: listId, p_password: password }))
  }

  // Reads

  async fetchLists(): Promise<ListDTO[]> {
    return unwrap(await this.client.from('lists').select())
  }

  async fetchItems(listId: string, updatedAfter: string | undefined): Promise<ItemDTO[]> {
    let query = this.client.from('items').select().eq('list_id', listId)
    if (updatedAfter) query = query.gt('updated_at', updatedAfter)
    return unwrap(await query.order('updated_at'))
  }

  async fetchItemsById(ids: string[]): Promise<ItemDTO[]> {
    if (!ids.length) return []
    return unwrap(await this.client.from('items').select().in('id', ids))
  }

  async fetchProfiles(): Promise<ProfileDTO[]> {
    return unwrap(await this.client.from('profiles').select('id, display_name'))
  }

  // Realtime

  /**
   * Subscribes to one list's items and list row. Resolves once the database-change feed is
   * confirmed live (or after 5 s), so "subscribe, then fetch" leaves no gap (docs/sync.md).
   */
  async subscribe(listId: string, onChange: (change: RemoteChange) => void): Promise<RealtimeChannel> {
    let confirmFeed: () => void = () => {}
    const feedLive = new Promise<void>((resolve) => (confirmFeed = resolve))

    // Unique suffix: a previous channel for the same list may still be tearing down.
    const channel = this.client
      .channel(`list-${listId}-${Math.random().toString(36).slice(2, 10)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'items', filter: `list_id=eq.${listId}` }, (p) => {
        // Deletes are soft (an UPDATE); hard deletes are tombstone purges and carry no row.
        if (p.eventType !== 'DELETE') onChange({ kind: 'item', row: p.new as ItemDTO })
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'lists', filter: `id=eq.${listId}` }, (p) =>
        onChange({ kind: 'list', row: p.new as ListDTO }),
      )
      .on('system', {}, (p: { extension?: string; status?: string }) => {
        if (p.extension === 'postgres_changes') confirmFeed()
      })
      .subscribe()

    const timeout = new Promise<void>((resolve) => setTimeout(resolve, 5000))
    await Promise.race([feedLive, timeout])
    return channel
  }

  async unsubscribe(channel: RealtimeChannel): Promise<void> {
    await this.client.removeChannel(channel)
  }
}

/** Postgres SQLSTATE classes: 22 data exception, 23 integrity, 42 privilege/syntax, P0 raised. */
const rejectedClasses = ['22', '23', '42', 'P0']

function unwrap<T>(response: { data: T | null; error: { message: string; code?: string } | null }): T {
  if (response.error) {
    const code = response.error.code ?? ''
    const kind = rejectedClasses.some((c) => code.startsWith(c)) ? 'rejected' : 'transient'
    throw new RemoteError(`${code} ${response.error.message}`.trim(), kind)
  }
  return response.data as T
}
