# Testing

Focus tests where bugs would hurt most: **sync correctness** and **data access rules**. Don't chase coverage on trivial views.

## Unit tests (Swift Testing)

Use `import Testing`, `@Test`, `#expect`. XCTest only for UI tests.

Must-have suites:
- **ConflictResolver** — insert / overwrite / skip-because-pending / skip-stale / echo suppression.
- **Outbox** — coalescing multiple mutations of one row; FIFO drain; backoff on network error; drop + restore on 4xx.
- **SyncEngine** against a `FakeRemote` (in-memory server with a controllable clock): offline create → reconnect → server has row; two clients editing the same item converge.
- **Ordering** — midpoint insertion, renormalization trigger.
- **CategoryGuesser** — table-driven `@Test(arguments:)` for common items ("milk" → dairy, "bananas" → produce).

SwiftData tests use an in-memory `ModelContainer` (`ModelConfiguration(isStoredInMemoryOnly: true)`), fresh per test.

## Database tests (pgTAP)

In `supabase/tests/`, run with `supabase test db` against the local stack:
- RLS: a non-member cannot select/insert/update items or lists of another household.
- `join_list` with a valid code adds membership; an invalid code errors; joining twice is idempotent.
- `updated_at` trigger always sets server time, ignoring client-sent values.
- Profile is auto-created on sign-up; creator is auto-added as list member.

## UI tests

A small smoke path with XCUITest, running against a launch argument that swaps in `FakeRemote` + in-memory store:
1. Launch signed in → empty state.
2. Add three items → they appear grouped by category.
3. Check one → it moves to "In cart".
4. Clear checked → it disappears.

## Manual two-device checklist (before installing a new build for both of you)

- [ ] Add on phone A → appears on B within ~1 s, with the partner-activity hint.
- [ ] Check on B → A updates.
- [ ] Airplane mode on A; add 3, check 2; turn off airplane mode → B converges.
- [ ] Both check the same item offline, then go online → no duplicate, consistent state.
- [ ] Kill the app with pending changes, relaunch offline → changes still there; online → synced.
- [ ] Cold launch with 100+ items feels instant.
- [ ] VoiceOver can add and check an item.
