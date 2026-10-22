# 0003. Email OTP authentication

- **Status:** Superseded by [0007](0007-guest-users-and-room-passwords.md)
- **Date:** 2026-10-21

## Context
Users need an identity so RLS can restrict lists to household members. Sign in with Apple has the best UX but requires a paid developer account. Passwords add friction and reset flows. Magic links require deep-link plumbing and switching to the mail app.

## Decision
Use Supabase **email OTP**: the user enters an email, receives a 6-digit code, and types it in (`signInWithOTP(email:)` then `verifyOTP(email:token:type: .email)`). The session persists in the Keychain via `supabase-swift`, so this happens once per device. The code field uses `.textContentType(.oneTimeCode)` so iOS can autofill it from Mail.

## Consequences
- No paid account or extra provider config needed.
- One-time friction per device; sessions refresh automatically.
- Email template must include `{{ .Token }}` (see [setup.md](../setup.md)).
- When we join the Apple Developer Program, add Sign in with Apple as an additional provider (new ADR) — existing accounts can be linked by email.
