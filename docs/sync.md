# Sync

Goal: every interaction feels instant, the app works fully offline (supermarkets have terrible signal), and both phones converge within ~1 second when online.

## Lifecycle

**Cold launch**
1. Render immediately from SwiftData. No spinner, ever, if there's cached data.
2. In the background: restore the Supabase session → drain the outbox → delta fetch → subscribe to Realtime.

**Foreground (scenePhase → .active)**
- Reconnect Realtime if needed, drain the outbox, delta fetch. Realtime events missed while backgrounded are recovered by the delta fetch.

**Background**
- Unsubscribe from Realtime channels (iOS will kill the socket anyway) and, if the outbox isn't empty, request background time (`beginBackgroundTask`) to finish pushing. Whatever doesn't make it stays persisted and goes out on the next foreground.

**Sign-out / account switch**
- Local data and cursors are wiped, so a different account on the same phone starts clean. Unsynced changes are lost; Settings warns before signing out.

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

- **Delta fetch:** lists are few, so all of them are fetched every time (that also reveals newly joined and removed lists). Then for each list, `select * from items where list_id = ? and updated_at > cursor order by updated_at`, and the list's cursor advances to the max `updated_at` seen. Cursors are **per list** so a newly joined list is fetched in full. Only delta fetches advance cursors — never Realtime — so a dropped event is always recovered by the next fetch.
- **Realtime:** one channel per open list, `postgres_changes` on `items` with filter `list_id=eq.<id>` (INSERT + UPDATE; deletes are soft so they arrive as UPDATE). Also listen on `lists` for renames.
- Subscribe **before** running the delta fetch, so no change falls in the gap; applying a row twice is harmless (idempotent upsert).
- Realtime may replay changes committed shortly *before* the subscription; the resolver skips them as stale/equal.
- A channel reports "subscribed" before its database-change feed is live; Realtime confirms the feed with a system message ("Subscribed to PostgreSQL"). `SupabaseRemote.changes()` waits for that message (up to 5 s, then logs and moves on) so "subscribe, then fetch" really has no gap.

## Conflict resolution

Row-level **last-write-wins by server `updated_at`**, with one guard:

```
apply(remoteRow):
  local = fetch(remoteRow.id)
  if local == nil                         → insert
  else if local.hasPendingChanges         → skip (our pending write will land later and win)
  else if remoteRow.updatedAt > local.updatedAt → overwrite
  else                                    → skip (stale event, or our own echo)
```

Why this is good enough: two people rarely edit the *same item* at the same instant, and the common collision (both tap "check" on milk) converges to the same value anyway. Field-level merging is not worth its complexity for v1. Revisit with an ADR if real conflicts show up.

## Echo suppression

Our own upserts come back through Realtime. After a push we store the server's returned `updated_at`, and the echo carries the identical timestamp (verified against a real Realtime server), so the resolver's `>` comparison skips it — no redundant re-render or animation.

## Mid-flight edits

Each `OutboxEntry` has a `revision`, bumped whenever its payload is replaced. A push retires an entry only if the revision it sent is still current; otherwise the newer edit stays queued and the push loop runs again. This is what makes "tap check, tap uncheck while the request is in flight" end in the right state.

## Partner activity

Remote changes with `updated_by != me` raise a lightweight `ActivityEvent` ("Ana checked Milk") consumed by the UI for the subtle hint described in [design-system.md](design-system.md#partner-activity). Batch delta fetches don't emit events (only live Realtime ones).

## UI states

| State | UI |
|---|---|
| Synced | Nothing. Silence is golden. |
| Pending changes | Nothing for 3 s; then a small `icloud.slash` marker on the row (also announced by VoiceOver). |
| Offline | Small glass capsule in the toolbar: "Offline — changes will sync". No alerts, no blocking. |
| Write rejected | Red status pill; the row is restored to the server's version. |
| Partner change (live) | Activity pill ("Ana got Milk") + brief row highlight; no haptic. |

## Ordering

`position` is a `Double`. Insert at the end = `max + 1`; move between A and B = `(A + B) / 2`. When the gap gets below `1e-9`, renormalize the list's positions (one batch upsert). New items go to the top of their category by default.
