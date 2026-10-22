# Docs

| Doc | Purpose |
|---|---|
| [product.md](product.md) | Vision, users, MVP scope, non-goals |
| [architecture.md](architecture.md) | Layers, folder layout, data flow, dependency injection |
| [data-model.md](data-model.md) | Postgres schema, RLS, RPCs, SwiftData models |
| [sync.md](sync.md) | Offline-first sync, outbox, realtime, conflict resolution |
| [design-system.md](design-system.md) | Visual language, motion, haptics, accessibility |
| [performance.md](performance.md) | Budgets and rules that keep the app snappy |
| [swift-style.md](swift-style.md) | Swift / SwiftUI conventions |
| [testing.md](testing.md) | What to test and how |
| [setup.md](setup.md) | Dev environment, Supabase project, installing on devices |
| [decisions/](decisions/) | Architecture Decision Records (ADRs) |

## Adding an ADR

1. Copy the format below into `decisions/NNNN-short-title.md` with the next number.
2. Keep it short — a page at most.
3. Never rewrite an accepted ADR's decision. To change course, write a new ADR and mark the old one `Superseded by NNNN`.

```markdown
# NNNN. Title

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
What problem or force made this decision necessary.

## Decision
What we chose.

## Consequences
What gets easier, what gets harder, what we must now do.
```

## Current ADRs

- [0001 — Native SwiftUI, iOS 26 minimum](decisions/0001-swiftui-ios26.md)
- [0002 — Supabase as backend](decisions/0002-supabase-backend.md)
- [0003 — Email OTP authentication](decisions/0003-email-otp-auth.md) *(superseded by 0007)*
- [0004 — Offline-first with a local SwiftData cache](decisions/0004-offline-first-local-cache.md)
- [0005 — XcodeGen for project generation](decisions/0005-xcodegen.md)
- [0006 — SyncEngine on the main actor / main context](decisions/0006-sync-on-main-context.md)
- [0007 — Guest users and password-protected rooms](decisions/0007-guest-users-and-room-passwords.md)
- [0008 — Optional email + password accounts](decisions/0008-optional-email-accounts.md)
