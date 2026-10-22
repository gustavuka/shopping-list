/**
 * Wire format for `public.items` / `public.lists` (snake_case, exactly what PostgREST returns),
 * plus the local-only fields we keep next to each row in IndexedDB. Mirrors `Data/Remote/DTOs.swift`.
 */
export interface ItemDTO {
  id: string
  list_id: string
  name: string
  quantity: string | null
  note: string | null
  category: string
  position: number
  is_checked: boolean
  checked_by: string | null
  checked_at: string | null
  created_by: string
  updated_by: string
  created_at: string
  updated_at: string
  deleted_at: string | null
}

export interface ListDTO {
  id: string
  name: string
  emoji: string | null
  /** null until the server generates one. */
  invite_code: string | null
  created_by: string
  created_at: string
  updated_at: string
  deleted_at: string | null
  /** Maintained by the server (`set_list_password`); never sent by the client. */
  has_password: boolean
}

export interface ProfileDTO {
  id: string
  display_name: string
}

/** Local-only bookkeeping, stripped before a row is sent. */
export interface LocalFields {
  /** True while an outbox entry exists for this row. */
  pending: boolean
  /** Last server-confirmed `updated_at` in epoch microseconds; 0 if never synced. */
  serverUs: number
}

export type ItemRow = ItemDTO & LocalFields
export type ListRow = ListDTO & LocalFields

export function itemDTO(row: ItemRow): ItemDTO {
  const { pending: _p, serverUs: _s, ...dto } = row
  return dto
}

/** `invite_code` is omitted when unknown so the server generates one; `has_password` is server-owned. */
export function listPayload(row: ListRow): Partial<ListDTO> {
  const { pending: _p, serverUs: _s, has_password: _h, invite_code, ...rest } = row
  return invite_code ? { ...rest, invite_code } : rest
}

export function fromServer<T extends { updated_at: string }>(dto: T): T & LocalFields {
  return { ...dto, pending: false, serverUs: timestampMicros(dto.updated_at) }
}

/**
 * Postgres keeps microseconds; a JS Date only milliseconds. Echo suppression compares our stored
 * `updated_at` with the one Realtime sends back, so compare at full precision (fits a double exactly).
 * Accepts PostgREST ("…T12:00:00.123456+00:00") and Realtime/text ("… 12:00:00.1234+00") formats.
 */
export function timestampMicros(value: string): number {
  const match = /^(\d{4}-\d\d-\d\d)[T ](\d\d:\d\d:\d\d)(?:\.(\d+))?(Z|[+-]\d\d(?::?\d\d)?)?$/.exec(value.trim())
  if (!match) return Date.parse(value) * 1000
  const [, date, time, fraction = '', zone = 'Z'] = match
  const offset = zone === 'Z' ? 'Z' : zone.length === 3 ? `${zone}:00` : zone.includes(':') ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`
  const seconds = Date.parse(`${date}T${time}${offset}`)
  return seconds * 1000 + Number(fraction.padEnd(6, '0').slice(0, 6))
}

/** RFC 4122 v4. `crypto.randomUUID` only exists in secure contexts (not plain-http LAN testing). */
export function newId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  const b = crypto.getRandomValues(new Uint8Array(16))
  b[6] = (b[6]! & 0x0f) | 0x40
  b[8] = (b[8]! & 0x3f) | 0x80
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
