# Sync

Goal: every interaction feels instant, the app works fully offline (supermarkets have terrible signal), and both phones converge within ~1 second when online.

## Lifecycle

**Cold launch**
1. Render immediately from SwiftData. No spinner, ever, if there's cached data.
2. In the background: restore the Supabase session → drain the outbox → delta fetch → subscribe to Realtime.

**Foreground (scenePhase → .active)**
- Reconnect Realtime if needed, drain the outbox, delta fetch. Realtime events missed while backgrounded are recovered by the delta fetch.

**Background**
- Unsubscribe from Realtime channels (iOS will kill the socket anyway). Ask for a short background task to finish draining the outbox.

## Writes: the outbox

```
ListStore.toggleChecked(item)
  ├─ item.isChecked.toggle(), checkedBy/checkedAt, updatedBy = me, hasPendingChanges = true
  ├─ insert OutboxEntry(entity: "item", rowID, payload: full row snapshot)
  ├─ modelContext.save()        ← single transaction
  └─ syncEngine.kick()          ← non-blocking
```

- One outbox entry per row; a newer mutation of the same row **replaces** the pending payload (coalescing), so toggling a checkbox five times sends one request.
- `SyncEngine` drains in FIFO order using `upsert` (insert-or-update by id), with `.select()` to get the server row back.
- On success: delete the entry, write the returned row (server `updated_at`) into SwiftData, clear `hasPendingChanges`.
- On network error: exponential backoff (1s, 2s, 4s… capped at 60s) and retry on connectivity regained (`NWPathMonitor`).
- On a 4xx (RLS rejection, constraint violation): drop the entry, re-fetch that row from the server to restore the truth, log it, and show a non-blocking toast. Never retry forever.

## Reads: delta fetch + Realtime

- **Delta fetch:** for each list, `select * from items where list_id = ? and updated_at > cursor order by updated_at`. Advance `SyncCursor` to the max `updated_at` seen. Lists and members are fetched the same way.
- **Realtime:** one channel per open list, `postgres_changes` on `items` with filter `list_id=eq.<id>` (INSERT + UPDATE; deletes are soft so they arrive as UPDATE). Also listen on `lists` for renames.
- Subscribe **before** running the delta fetch, so no change falls in the gap; applying a row twice is harmless (idempotent upsert).

## Conflict resolution

Row-level **last-write-wins by server `updated_at`**, with one guard:

```
apply(remoteRow):
  local = fetch(remoteRow.id)
  if local == nil                         → insert
  else if local.hasPendingChanges         → skip (our pending write will land later and win)
  else if remoteRow.updatedAt >= local.updatedAt → overwrite
  else                                    → skip (stale event)
```

Why this is good enough: two people rarely edit the *same item* at the same instant, and the common collision (both tap "check" on milk) converges to the same value anyway. Field-level merging is not worth its complexity for v1. Revisit with an ADR if real conflicts show up.

## Echo suppression

Our own upserts come back through Realtime. They're harmless (`updatedAt` equal → overwrite with identical data), but to avoid redundant animations, `ConflictResolver` ignores events where `updated_by == me` and the local row already has that `updatedAt`.

## Partner activity

Remote changes with `updated_by != me` raise a lightweight `ActivityEvent` ("Ana checked Milk") consumed by the UI for the subtle hint described in [design-system.md](design-system.md#partner-activity). Batch delta fetches don't emit events (only live Realtime ones).

## UI states

| State | UI |
|---|---|
| Synced | Nothing. Silence is golden. |
| Pending changes, online | Nothing for < 3 s; after that, a tiny dot on the row. |
| Offline | Small glass capsule in the toolbar: "Offline — changes will sync". No alerts, no blocking. |
| Write rejected | Toast with the row restored to server state. |

## Ordering

`position` is a `Double`. Insert at the end = `max + 1`; move between A and B = `(A + B) / 2`. When the gap gets below `1e-9`, renormalize the list's positions (one batch upsert). New items go to the top of their category by default.
