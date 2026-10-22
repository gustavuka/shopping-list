# Swift style

## Language & concurrency

- **Swift 6 language mode**, strict concurrency checking `complete`. Fix warnings, don't silence them with `@unchecked Sendable` or `nonisolated(unsafe)` unless there's a comment explaining why it is safe.
- Feature models: `@MainActor @Observable final class`. Views own them with `@State`.
- `SyncEngine` is `@MainActor` and shares the main `ModelContext`; anything slow belongs in `RemoteSyncing` implementations, which are `Sendable` and run off the main actor ([ADR 0006](decisions/0006-sync-on-main-context.md)).
- DTOs and domain types are `struct`s conforming to `Sendable` (and `Codable`/`Hashable` where useful).
- Prefer `async/await` and `AsyncStream`. **No Combine.**
- Use structured concurrency (`.task`, `async let`, task groups). Unstructured `Task {}` only at intent boundaries (button actions), and store/cancel long-running ones.

## SwiftUI

- Small views: if `body` scrolls past a screen, extract subviews (as `struct`s, not functions returning `some View`, so SwiftUI can diff them).
- Use `@Environment` for app services; never singletons or `static shared`.
- `@State` for view-local state; `@Bindable` to bind into an `@Observable` model.
- Use `.task` (auto-cancels) instead of `.onAppear { Task { } }`.
- Every screen has a `#Preview` using `PreviewSupport` with sample data, including a dark mode and a large Dynamic Type variant for key screens.
- Strings in `Localizable.xcstrings` (String Catalog) from day one — English first.

## Naming & files

- One primary type per file, file named after the type.
- Views end in `View` (or `Sheet`, `Row`, `Bar` for specific roles); models end in `Model`; SwiftData models end in `Record`.
- Booleans read as assertions: `isChecked`, `hasPendingChanges`.
- No abbreviations except well-known ones (`id`, `url`, `dto`).

## Errors & logging

- Define typed errors per area (`enum SyncError: Error`, `enum AuthError: LocalizedError`) with user-facing messages where shown to users.
- Never `try!` / force-unwrap outside tests and previews.
- Log with `os.Logger` (one per subsystem category: `sync`, `auth`, `store`). Use privacy annotations — item names are `.private`.
- Don't swallow errors silently: log, and surface to the UI if the user's data is affected.

## Formatting

- 4-space indent, 120-column soft limit.
- Use `swift format` (bundled with the Xcode toolchain); config in `.swift-format` at the repo root.
- Trailing closures for the last closure argument only; one-statement closures may use `$0`.

## Dependencies

- Swift Package Manager only.
- Allowed: `supabase-swift`. Anything else requires an ADR. Prefer Apple frameworks.
