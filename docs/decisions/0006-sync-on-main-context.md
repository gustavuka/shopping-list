# 0006. SyncEngine runs on the main actor with the main ModelContext

- **Status:** Accepted
- **Date:** 2026-10-21
- **Amends:** [0004](0004-offline-first-local-cache.md) (which suggested a background `@ModelActor`)

## Context
`ListStore` writes the main `ModelContext` on every tap. A sync engine with its own background context would be a second writer to the same rows (`hasPendingChanges`, `updatedAt`, outbox entries), which means merge conflicts and subtle races, e.g. a push retiring an outbox entry that the user just updated. Our batches are tiny: two people, tens to a few hundred items.

## Decision
`SyncEngine` is `@MainActor` and uses the main `ModelContext`, so there is a single writer and no cross-context merging. All slow work (HTTP, WebSocket, JSON encode/decode) lives in `RemoteSyncing` implementations, which are `Sendable` and run off the main actor. The engine only does bookkeeping on the main actor between awaits. Outbox entries carry a `revision` so edits made while a request is in flight are never lost.

## Consequences
- Simple and race-free reasoning: every SwiftData mutation happens on one actor.
- Applying a very large batch (thousands of rows) could hitch the UI. Not a realistic size for this app; if Instruments shows hangs, move appliers to a `@ModelActor` with an explicit merge strategy and supersede this ADR.
