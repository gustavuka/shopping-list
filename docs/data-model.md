# Data model

All tables live in the `public` schema, are created only via `supabase/migrations`, and have **RLS enabled**. IDs are UUIDs **generated on the client** so rows can be created offline.

## Tables

### `profiles`
| column | type | notes |
|---|---|---|
| `id` | `uuid` PK | = `auth.users.id` |
| `display_name` | `text` | shown in partner-activity hints |
| `created_at` | `timestamptz` | default `now()` |

Created by a trigger on `auth.users` insert; `display_name` comes from the sign-up metadata (guests send the name they typed on the welcome screen).

### `lists`
| column | type | notes |
|---|---|---|
| `id` | `uuid` PK | client-generated |
| `name` | `text` not null | e.g. "Groceries" |
| `emoji` | `text` | optional list icon |
| `invite_code` | `text` unique not null | 6 chars, uppercase, no ambiguous chars (no `0 O 1 I L`) |
| `created_by` | `uuid` → `profiles.id` | |
| `created_at` / `updated_at` | `timestamptz` | `updated_at` set by trigger |
| `deleted_at` | `timestamptz` null | soft delete |

### `list_members`
| column | type | notes |
|---|---|---|
| `list_id` | `uuid` → `lists.id` | PK part |
| `user_id` | `uuid` → `profiles.id` | PK part |
| `joined_at` | `timestamptz` | default `now()` |

Creator is inserted as a member by a trigger on `lists` insert.

### `items`
| column | type | notes |
|---|---|---|
| `id` | `uuid` PK | client-generated |
| `list_id` | `uuid` → `lists.id` not null | |
| `name` | `text` not null | trimmed, 1–100 chars (check constraint) |
| `quantity` | `text` null | free text: "2", "500 g", "a dozen" |
| `note` | `text` null | |
| `category` | `text` not null | one of `Category` raw values; default `'other'` |
| `position` | `double precision` not null | fractional ordering (insert between = midpoint) |
| `is_checked` | `boolean` not null | default `false` |
| `checked_by` | `uuid` null | → `profiles.id` |
| `checked_at` | `timestamptz` null | |
| `created_by` | `uuid` not null | → `profiles.id` |
| `updated_by` | `uuid` not null | → `profiles.id`; used for echo suppression and activity hints |
| `created_at` | `timestamptz` | |
| `updated_at` | `timestamptz` not null | **set by trigger to `now()`** on every insert/update — server clock is authoritative |
| `deleted_at` | `timestamptz` null | soft delete; tombstones purged after 30 days |

**Indexes:** `items (list_id, updated_at)` for delta fetches; `list_members (user_id)`.

## Why soft deletes

Realtime cannot filter `DELETE` events by column, and an offline device needs to learn about deletions during a delta fetch (`updated_at > lastSync`). A tombstone (`deleted_at`) is just another update, so both paths work uniformly. A scheduled job (pg_cron) hard-deletes tombstones older than 30 days.

## RLS

Helper (avoids recursive policy evaluation on `list_members`):

```sql
create function public.is_list_member(p_list_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.list_members
    where list_id = p_list_id and user_id = (select auth.uid())
  );
$$;
```

| table | select | insert | update | delete |
|---|---|---|---|---|
| `profiles` | self, or shares a list with self | self (via trigger) | self | — |
| `lists` | `is_list_member(id)` | `created_by = auth.uid()` | member | — (soft delete via update) |
| `list_members` | `is_list_member(list_id)` | only via `join_list` RPC | — | self (leave list) |
| `items` | `is_list_member(list_id)` | member and `created_by = auth.uid()` | member | — (soft delete via update) |

Always write `(select auth.uid())` rather than `auth.uid()` in policies so Postgres caches it per statement.

### `list_secrets`
| column | type | notes |
|---|---|---|
| `list_id` | `uuid` PK → `lists.id` | |
| `password_hash` | `text` | bcrypt (`extensions.crypt` + `gen_salt('bf', 10)`) |
| `updated_at` | `timestamptz` | |

RLS enabled with **no policies** and all privileges revoked: clients can never read it. `lists.has_password` (server-maintained) tells members whether the room can be joined yet.

### `join_attempts`
Failed `join_list` calls (`user_id`, `list_id` when the code matched a room, `attempted_at`). Same lockdown as `list_secrets`; only `join_list` touches it. Purged after a day.

## Limits ([ADR 0010](decisions/0010-public-web-hardening.md))

- Text: `items.name` 1–100, `quantity` ≤ 40, `note` ≤ 500, `category` ≤ 32; `lists.name` 1–60, `emoji` ≤ 16; `profiles.display_name` ≤ 50 (truncated at sign-up).
- Rows: 2000 items per list and 50 lists per creator, tombstones included (`enforce_row_caps` trigger, `P0001`). Upserts of existing rows always pass.
- Server-owned: `updated_at`, `updated_by`, `created_by`, `checked_by` (whoever checked it), and on `lists` `invite_code` + `has_password` (only the RPCs change them).

## RPCs

- `set_list_password(p_list_id uuid, p_password text)` — member only; ≥ 6 characters; stores the hash and sets `lists.has_password`.
- `join_list(p_invite_code text, p_password text) returns jsonb` — `security definer`; requires a matching code **and** password, inserts the caller into `list_members` (idempotent). Returns `{"list": <row>}`, or `{"error": "invalid"}` for a wrong code *or* password (indistinguishable), or `{"error": "throttled"}` after 5 failures by this user in 15 min or 20 against this room in an hour. It returns instead of raising so the failed attempt is kept.
- `purge_tombstones()` — not callable by clients; run daily at 04:17 UTC by `pg_cron`. Deletes tombstones older than 30 days, join attempts older than a day, and guests older than a week with no room and no authored rows.
- `regenerate_invite_code(p_list_id uuid) returns text` — member only.

## Realtime

Add `items` and `lists` to the `supabase_realtime` publication. Realtime respects RLS, so clients only receive rows of lists they belong to.

## Local (SwiftData) models

Mirror the remote rows; field names in camelCase. Extra local-only fields:

```swift
@Model final class ItemRecord {
    @Attribute(.unique) var id: UUID
    var listID: UUID
    var name: String
    var quantity: String?
    var note: String?
    var categoryRaw: String
    var position: Double
    var isChecked: Bool
    var checkedBy: UUID?
    var checkedAt: Date?
    var createdBy: UUID
    var updatedBy: UUID
    var createdAt: Date
    var updatedAt: Date          // last server-confirmed updated_at
    var deletedAt: Date?
    var hasPendingChanges: Bool  // local-only: true while an outbox entry exists
}

@Model final class OutboxEntry {
    var id: UUID
    var entity: String           // "item" | "list"
    var rowID: UUID
    var payload: Data            // JSON snapshot of the full row to upsert
    var enqueuedAt: Date
    var attempts: Int
}
```

Also `ListRecord`. Sync cursors (per list: last `updated_at` seen) live in `UserDefaults` via `SyncCursors`; partner names are fetched into memory, not persisted.

DTOs in `Data/Remote/DTOs.swift` are `Codable, Sendable` structs with `snake_case` coding keys; mapping DTO ⇄ `@Model` lives in one place.
