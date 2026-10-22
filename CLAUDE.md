# Shopping List

A native iOS app for a couple to share one live shopping list. Both partners add items at home; at the market either one checks items off and the other phone updates instantly. It must feel **instant, fluid, and delightful** — snappiness is a feature, not a nice-to-have.

**Stack:** Swift 6 · SwiftUI · iOS 26+ (Liquid Glass) · SwiftData (local cache) · Supabase (Postgres + RLS + Realtime + guest / email-password auth) via `supabase-swift` · XcodeGen

**Web app:** `web/` is a PWA client of the same backend (Vite · React · TypeScript · Dexie/IndexedDB · supabase-js), a port of the iOS sync design with the same names ([ADR 0009](docs/decisions/0009-web-pwa-client.md)). Sync, schema, or `Domain/` changes go into both clients.

**Identity & sharing:** each phone is a guest (just a name) or an email + password account; guests can upgrade in place. A list is a *room* joined with its code + password, whoever you are ([ADR 0007](docs/decisions/0007-guest-users-and-room-passwords.md), [0008](docs/decisions/0008-optional-email-accounts.md)). Never add a flow that needs email delivery — the free plan can't send it.

**Status:** see the milestones in [docs/product.md](docs/product.md#milestones). Feature-complete for v1; next is shipping to both phones (M6).

## Commands

```sh
xcodegen generate                                   # regenerate ShoppingList.xcodeproj from project.yml
xcodebuild -scheme ShoppingList -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme ShoppingList -destination 'platform=iOS Simulator,name=iPhone 17' test
TEST_RUNNER_RUN_PERF=1 xcodebuild … test            # also run the (slow) launch performance test
TEST_RUNNER_RUN_INTEGRATION=1 xcodebuild … test     # also run tests against local Supabase (needs `supabase start`)
xcrun simctl launch booted com.gustavomartins.shoppinglist -uiTesting -seeded   # signed-in demo, no backend
swift scripts/make-app-icon.swift ShoppingList/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cd web && npm run dev                               # web app (PWA); needs web/.env.local, see docs/setup.md
cd web && npm test                                  # web unit tests (Vitest)
cd web && npm run build                             # typecheck + static build in web/dist
supabase start                                      # local Supabase (needs Docker)
supabase db reset                                   # re-apply all migrations + seed locally
supabase migration new <name>                       # new SQL migration in supabase/migrations
supabase test db                                    # pgTAP tests for schema + RLS
supabase db push -p "$SUPABASE_DB_PASSWORD"         # migrations → cloud (password in supabase/.env)
```

The `.xcodeproj` is generated — never edit it by hand; change `project.yml` and regenerate.

## Hard rules

1. **UI reads only from the local store.** Views render from SwiftData; the network never blocks a frame or a launch.
2. **All mutations are optimistic.** Write locally → enqueue in the outbox → `SyncEngine` pushes in the background. See [docs/sync.md](docs/sync.md).
3. **Client generates UUIDs** for every row so offline creates need no round-trip.
4. **Schema changes only via `supabase/migrations`.** Every table has RLS enabled with policies; no table is reachable without list membership.
5. **Never commit secrets.** `Config/Secrets.xcconfig` is gitignored; only the anon key ships in the app, never the service-role key.
6. **Swift 6 strict concurrency.** `@Observable` + `@MainActor` models (incl. `SyncEngine`, see ADR 0006), `Sendable` DTOs and remotes. No Combine, no third-party UI libraries.
7. **Every user-facing interaction gets motion + haptics** per [docs/design-system.md](docs/design-system.md), with a Reduce Motion fallback.
8. **Stay inside the performance budgets** in [docs/performance.md](docs/performance.md).
9. **Significant decisions get an ADR** in [docs/decisions/](docs/decisions/) — don't silently diverge from an existing one; supersede it.

## Read before working on…

| Area | Doc |
|---|---|
| What we're building / scope | [docs/product.md](docs/product.md) |
| Code layout, layers, DI | [docs/architecture.md](docs/architecture.md) |
| Database schema, RLS, SwiftData models | [docs/data-model.md](docs/data-model.md) |
| Offline, realtime, conflicts | [docs/sync.md](docs/sync.md) |
| Visuals, motion, haptics, a11y | [docs/design-system.md](docs/design-system.md) |
| Launch time, scrolling, profiling | [docs/performance.md](docs/performance.md) |
| Swift conventions | [docs/swift-style.md](docs/swift-style.md) |
| Tests | [docs/testing.md](docs/testing.md) |
| Dev environment, Supabase, installing on phones, web app | [docs/setup.md](docs/setup.md) |
| Why things are the way they are | [docs/decisions/](docs/decisions/) |
