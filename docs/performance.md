# Performance

"Snappy" is a requirement. These budgets are measured on a physical iPhone (not the simulator), release build.

## Budgets

| Metric | Budget |
|---|---|
| Cold launch → list visible with cached data | < 400 ms |
| Warm launch / resume | instant (no visible loading) |
| Tap → visual response | same frame (< 16 ms of main-thread work) |
| Scrolling a 200-item list | steady 120 fps on ProMotion, zero hitches |
| Local change visible on partner's phone (both online) | < 1 s |
| Main-thread hang | never > 100 ms |

## Rules

**Launch**
- Do nothing in `App.init` except open the `ModelContainer` and construct services (cheap).
- Session restore, network, Realtime connect all start in a `.task` *after* the first frame.
- No splash screen / launch-time spinner. The launch screen matches the first frame (same background + nav bar).
- Defer anything non-essential (category guesser warm-up, purging old tombstones) with low-priority tasks.

**Main actor**
- Main actor does UI + SwiftData writes on the main context (small and fast). Networking and JSON decoding run off the main actor inside `SupabaseRemote`; applying the (small) resulting batches happens on the main context ([ADR 0006](decisions/0006-sync-on-main-context.md)). If Instruments ever shows hangs from big batches, revisit that ADR.
- Never `await` the network inside a user-intent handler.

**SwiftUI**
- Lists use `List` or `LazyVStack` with stable `id`s (the row UUID) — never array indices.
- Keep views small so invalidation is narrow; pass the minimum data a row needs.
- `@Observable` models: read only the properties a view needs; avoid computing large derived arrays in `body` — precompute in the model when the source changes.
- No `AnyView`. Avoid `GeometryReader` in rows.
- Don't put `.animation(...)` on large containers; animate explicitly with `withAnimation` at the state change.
- Images/symbols only — no network images in v1.

**SwiftData**
- Fetch with predicates scoped to the current list; use `#Index` on `listID` and `updatedAt`.
- Batch remote applies: one `save()` per batch, not per row.

**Network**
- Coalesce outbox writes per row; batch upserts when more than one row is pending.
- Select only needed columns in delta fetches.

## Measuring

- Debug builds (and Release with `-measureLaunch`) log `First frame (…): X ms since process start, Y ms since App.init` under the `performance` log category (`LaunchTimer`).
- Simulator baseline (Release, iPhone 17 sim, Oct 2026): ~425 ms since `App.init` to a seeded list; "since process start" adds ~1.7 s of simulator spawn overhead and is not meaningful there. Of our time, opening the store is ~55 ms and building `AppModel` ~40 ms; the rest is SwiftUI's first render.
- The 400 ms budget is for a physical device — confirm with Instruments there.

## Profiling checklist (before each TestFlight/install)

1. Instruments → **App Launch** template on device: confirm the < 400 ms budget.
2. Instruments → **SwiftUI** template: look for views with excessive body evaluations while scrolling/checking items.
3. Instruments → **Hangs** + **Time Profiler**: no main-thread work > 100 ms during sync of a large batch (seed 500 items).
4. Xcode Organizer / MetricKit later for real-world launch and hang data.
5. Test with Network Link Conditioner → "Very Bad Network" and airplane mode: the UI must behave identically.
