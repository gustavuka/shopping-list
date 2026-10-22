# Testing

Focus tests where bugs would hurt most: **sync correctness** and **data access rules**. Don't chase coverage on trivial views.

## Unit tests (Swift Testing)

Use `import Testing`, `@Test`, `#expect`. XCTest only for UI tests.

Must-have suites:
- **ConflictResolver** — insert / overwrite / skip-because-pending / skip-stale / echo suppression.
- **Outbox** — coalescing multiple mutations of one row; FIFO drain; backoff on network error; drop + restore on 4xx.
- **SyncEngine** against `FakeRemote` (`ShoppingListTests/FakeRemote.swift`: in-memory server with a fake clock, rejections, live events, and a hook to edit locally while a request is in flight).
- **Ordering** — midpoint insertion, renormalization trigger.
- **CategoryGuesser** — table-driven `@Test(arguments:)` for common items ("milk" → dairy, "bananas" → produce).

SwiftData tests use an in-memory `ModelContainer` (`ModelConfiguration(isStoredInMemoryOnly: true)`), fresh per test.

## Database tests (pgTAP)

In `supabase/tests/`, run with `supabase test db` against the local stack:
- RLS: a non-member cannot select/insert/update items or lists of another household.
- Rooms: no join before a password is set; only members set it (≥ 4 chars); hashes unreadable; wrong code/password give the same error; join is case-insensitive on the code and idempotent.
- `updated_at` trigger always sets server time, ignoring client-sent values.
- Profile is auto-created on sign-up; creator is auto-added as list member.

## Integration tests against local Supabase (opt-in)

Need `supabase start`; run with `TEST_RUNNER_RUN_INTEGRATION=1 xcodebuild … test`.
- `SupabaseIntegrationTests` (unit target): two guest users through the real `AuthService` + `SupabaseRemote` — room without a password can't be joined, wrong password rejected, join with code + password, live Realtime item with the exact server `updated_at`, display names.
- `SupabaseIntegrationTests` also covers accounts: a guest upgrades in place (same user id), signs in on a second "phone" and gets its room back; wrong password and duplicate email give the right messages; direct sign-up sets the display name.
- `WelcomeFlowTests` (UI target), launched with `-signOutOnLaunch` (debug-only): guest → new list → Share room → password shown; and Create account → list → Settings shows the email.

Run them after changing the schema, RLS, `SupabaseRemote`, `AuthService`, or the welcome/share flows. Right after `supabase start`, the first Realtime subscription can fail while the server warms up; `SupabaseRemote` retries it.

## UI tests

`ShoppingListUITests` launch the app with `-uiTesting`: a signed-in session on an in-memory store with the offline `PreviewRemote` (add `-seeded` for sample items). Rows are found by accessibility identifier `item.<name>` (query `descendants(matching: .any)` — SwiftUI list rows aren't always exposed as buttons).
- `SmokeTests`: add three items → category guessed → check one → it lands in "In cart" → clear cart.
- `LaunchPerformanceTests`: opt-in (`TEST_RUNNER_RUN_PERF=1`), measures launch with `XCTApplicationLaunchMetric`.

XCUITest waits for the app to go idle after each action, so short-lived UI (the 1.6 s celebration, activity pills) is hard to assert on; verify those by eye or with a screenshot.

The same `-uiTesting -seeded` flags are handy for screenshots: `xcrun simctl launch booted com.gustavomartins.shoppinglist -uiTesting -seeded`.

## Manual two-device checklist (before installing a new build for both of you)

- [ ] Add on phone A → appears on B within ~1 s, with the partner-activity hint.
- [ ] Check on B → A updates.
- [ ] Airplane mode on A; add 3, check 2; turn off airplane mode → B converges.
- [ ] Both check the same item offline, then go online → no duplicate, consistent state.
- [ ] Kill the app with pending changes, relaunch offline → changes still there; online → synced.
- [ ] Cold launch with 100+ items feels instant.
- [ ] VoiceOver can add and check an item.
