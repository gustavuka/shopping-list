# 0002. Supabase as backend

- **Status:** Accepted
- **Date:** 2026-10-21

## Context
Two users must share a list with live updates. Options considered:
- **CloudKit + CKShare** — Apple-native and free, but requires a paid Apple Developer account, which we don't have yet. Sharing UX and debugging are also harder.
- **Firebase Firestore** — mature offline/realtime, but a NoSQL model, Google SDK weight, and a vendor-specific security-rules language.
- **Supabase** — Postgres, Row Level Security, Realtime, Auth, a generous free tier, and an official Swift SDK.

## Decision
Use **Supabase** (`supabase-swift` via SPM) for auth, data, and realtime. Schema and policies live in versioned SQL migrations under `supabase/migrations`, developed locally with the Supabase CLI.

## Consequences
- Works today without a paid Apple account; free tier is far beyond our needs.
- Real SQL + RLS: access rules are explicit and testable with pgTAP.
- Offline support is **not** provided by the SDK — we build it ourselves ([ADR 0004](0004-offline-first-local-cache.md)).
- Free projects pause after ~7 days of inactivity; mitigated as described in [setup.md](../setup.md).
- Leaves the door open for a web or Android client later.
