# 0004. Offline-first with a local SwiftData cache

- **Status:** Accepted
- **Date:** 2026-10-21

## Context
The app must launch instantly and respond to every tap immediately. It is used inside supermarkets, which often have poor or no signal. Querying Supabase directly from views would mean spinners on launch and failures mid-shop.

## Decision
SwiftData is the local source of truth for the UI. All mutations are written locally first and queued in a persisted **outbox**; a `SyncEngine` actor pushes them, pulls deltas by `updated_at`, and applies Realtime events. Conflicts are resolved row-level last-write-wins by server `updated_at`, with pending local changes protected. Deletes are soft (`deleted_at`). Full design in [sync.md](../sync.md).

## Consequences
- Instant launch from cache, instant interactions, full offline use.
- We own the sync code, so it needs strong tests (see [testing.md](../testing.md)).
- Client-generated UUIDs and server-set `updated_at` are mandatory schema conventions.
- Tombstones need periodic purging.
- Row-level LWW can lose a concurrent edit to different fields of the same item; accepted for v1.
