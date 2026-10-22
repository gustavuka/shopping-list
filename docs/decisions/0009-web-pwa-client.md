# 0009. A web (PWA) client next to the iOS app

- **Status:** Accepted
- **Date:** 2026-10-22
- **Amends:** [0001](0001-swiftui-ios26.md) (the iOS app stays native SwiftUI); lifts the "no web client" non-goal in [product.md](../product.md)

## Context
Installing the native app on a phone needs Xcode, a cable, and (with a free Apple ID) a re-sign every 7 days. That blocks the simplest use: a partner — or anyone — opening the list without installing anything. The backend was chosen partly to keep a web client possible ([ADR 0002](0002-supabase-backend.md)).

## Decision
- Build a **Progressive Web App** in `web/`: Vite + React + TypeScript, `supabase-js`, **Dexie** (IndexedDB) as the local store, and `vite-plugin-pwa` (Workbox) to precache the app shell. It installs to the Home Screen and runs standalone.
- It is a **second client of the same backend**: same schema, RLS, RPCs, rooms and accounts. A web user and an iPhone user share a room normally. No schema changes were needed.
- It keeps the same rules as the iOS app, ported one-to-one: the UI reads only from the local store (`useLiveQuery`), every mutation is an optimistic write + outbox entry in one transaction, client-generated UUIDs, the same push / delta-fetch / Realtime / conflict rules as [sync.md](../sync.md). `Data/Sync/SyncEngine.swift` ↔ `web/src/data/sync.ts` and friends keep the same names so changes can be mirrored.
- Timestamps are compared in **microseconds** (`timestampMicros`), since a JS `Date` would drop the precision that echo suppression relies on.
- Join links are `https://<host>/?join=CODE` (the web form of `shoppinglist://join/CODE`). Static hosting only; no server code.

## Consequences
- Anyone can use the list from a link, on iPhone, Android, or desktop. No App Store, no re-signing.
- Two clients to keep in step: a sync or schema change must be made in both (`Domain/` ports: categories, category guesser, ordering, conflict resolver). Shared pure logic is small and covered by tests on both sides.
- The web is a lesser platform for "delightful": no Liquid Glass (approximated with `backdrop-filter`), no SF Symbols (emoji), no Vibration API on iPhone (we tick a hidden `<input switch>`, which Safari 18+ turns into a haptic). iOS may evict an installed PWA's storage after weeks of non-use; the server copy makes that harmless except for unsynced changes.
- A public URL makes bulk anonymous sign-ups easier: add the captcha planned in ADR 0007 before advertising the link. See [ADR 0010](0010-public-web-hardening.md) for the hardening done for the public URL.
