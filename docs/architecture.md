# Architecture

## Principles

- **Local-first.** SwiftData is the source of truth for the UI. Supabase is the source of truth for the household. `SyncEngine` reconciles them. ([ADR 0004](decisions/0004-offline-first-local-cache.md))
- **Thin layers, no ceremony.** Four layers, plain Swift. No coordinators, no Redux, no Combine.
- **Dependencies point inward.** Features depend on Domain and Data protocols; Domain depends on nothing.

## Layers

```
App        ShoppingListApp, root scene, environment wiring, deep-link handling
  │
Features   SwiftUI views + @Observable @MainActor models, one folder per feature
  │
Domain     Plain Sendable value types and pure logic (Category guessing, sorting, ItemDraft validation)
  │
Data       SwiftData models + ListStore (local reads/writes + outbox)
           SyncEngine (actor) — push outbox, pull deltas, realtime
           Remote (SupabaseClient wrapper, DTOs, AuthService)
```

## Folder layout

```
ShoppingList/
  App/            ShoppingListApp.swift (+ RootView), AppConfig, Log, PreviewSupport
  Features/
    Auth/         SignInView, CodeEntryView, AuthModel
    Lists/        ListsView (switcher), JoinListView
    List/         ShoppingListView, ItemRow, AddItemBar, ListModel
    ItemEditor/   ItemEditorSheet
    Settings/     SettingsView
  Domain/         Item.swift, Category.swift, CategoryGuesser.swift, Ordering.swift
  Data/
    Local/        SwiftData @Model types, ListStore.swift, OutboxEntry.swift
    Sync/         SyncEngine.swift, ConflictResolver.swift
    Remote/       SupabaseService.swift, DTOs.swift, AuthService.swift
  DesignSystem/   Colors, Typography, Motion (spring presets), Haptics, reusable components
  Resources/      Assets.xcassets, Localizable.xcstrings
ShoppingListTests/
ShoppingListUITests/
supabase/
  migrations/     SQL migrations (schema, RLS, functions)
  tests/          pgTAP tests
  seed.sql
Config/
  Base.xcconfig, Secrets.xcconfig (gitignored), Secrets.example.xcconfig
project.yml
```

## Data flow

```
 ┌──────────┐  read (@Query / fetch)   ┌────────────┐
 │  View    │◀────────────────────────│ SwiftData  │◀───────────┐
 └────┬─────┘                          └────▲───────┘            │ apply remote rows
      │ intent (tap, add)                   │ write + enqueue    │
 ┌────▼─────┐   ListStore.mutate(...)  ┌────┴───────┐      ┌─────┴──────┐
 │ Model    │─────────────────────────▶│ ListStore  │─────▶│ SyncEngine │◀── Realtime (postgres_changes)
 └──────────┘   (MainActor, sync)      └────────────┘ kick │  (actor)   │──▶ Supabase REST (upsert)
                                                           └────────────┘
```

1. A user intent calls a `ListStore` method. It writes SwiftData **and** appends an `OutboxEntry` in the same save, then nudges `SyncEngine`. The UI updates on the same frame.
2. `SyncEngine` drains the outbox to Supabase off the main actor.
3. Remote changes arrive via Realtime (or a delta fetch on launch/foreground) and are applied to SwiftData through `ConflictResolver`. Views re-render automatically.

Details: [sync.md](sync.md).

## Dependency injection

- Services (`ListStore`, later `SyncEngine`, `AuthService`) are built once in `ShoppingListApp.init` and injected with `.environment(service)`; views read them with `@Environment(ListStore.self)`. Plain values (config, flags) use `@Entry` environment values.
- Views/models depend on small protocols where a test fake is useful (`RemoteSyncing`, `AuthProviding`), concrete types otherwise. Don't add a protocol with a single implementation and no test need.
- Previews use `PreviewSupport` (in-memory `ModelContainer` + seeded `ListStore`, no network).

## State ownership

| State | Owner |
|---|---|
| Items, lists, members | SwiftData (persisted) |
| Pending changes | `OutboxEntry` in SwiftData (survives app kill) |
| Session / user | `AuthService` (supabase-swift persists the session in the Keychain) |
| Screen-local UI state (text field, sheet flags) | `@State` in the view |
| Feature logic shared across subviews | `@Observable` model owned by the feature root via `@State` |
| Sync status (online, pending count, last sync) | `SyncEngine` publishes a `@MainActor @Observable SyncStatus` |
