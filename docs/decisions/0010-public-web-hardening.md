# 0010. Hardening the backend for a public web URL

- **Status:** Accepted
- **Date:** 2026-10-22
- **Amends:** [0007](0007-guest-users-and-room-passwords.md) (room passwords), [0009](0009-web-pwa-client.md) (hosting)

## Context
The web client ([ADR 0009](0009-web-pwa-client.md)) puts the app behind a public URL, and anyone who can open it can reach the Supabase project with the publishable key. Room codes aren't secret either: they're in every share text and `?join=` link. Anyone with a code could try passwords as fast as the RPC answers, using as many guest users as they liked. Nothing bounded how much one account could store on the free plan's 500 MB.

## Decision
- **Throttled joins.** `join_list` records each failed attempt in `join_attempts` and refuses further tries after 5 failures per user in 15 minutes, or 20 failures against one room in an hour. Because a raised error would roll back the recorded attempt, `join_list` now **returns `jsonb`** instead of raising: `{"list": …}` on success, `{"error": "invalid" | "throttled"}` otherwise. Both clients map that to `JoinError`.
- **Stronger room passwords.** New passwords need 6+ characters (was 4) and are hashed with bcrypt cost 10. Existing 4–5 character passwords still work, so the join forms keep accepting 4.
- **Bounded storage.** Length checks on every free-text column (`display_name` ≤ 50, `emoji` ≤ 16, `category` ≤ 32). At most 2000 items per list and 50 lists per creator, with tombstones counted until purged. Over the cap, the write is rejected like any other refused write.
- **Server-owned columns.** Client writes can't choose `invite_code` or flip `has_password` (only the RPCs can), and `checked_by` is always whoever checked the item.
- **Scheduled cleanup.** A daily `pg_cron` job runs `purge_tombstones()`: tombstones older than 30 days, join attempts older than a day, and guest users older than a week who never kept a room or authored a row.
- **Captcha: ready, off.** The web client sends a Cloudflare Turnstile token when `VITE_TURNSTILE_SITE_KEY` is set. It stays off until the iOS app can send tokens too, because the Supabase setting applies to every client.
- **Web hosting.** The build emits `_headers` (CSP scoped to the Supabase project, `nosniff`, no framing, `sw.js` never cached) and fails without the Supabase settings or with a secret key. Service worker updates wait until the app is backgrounded instead of reloading it mid-use.

## Consequences
- Brute-forcing a room now takes years, not hours. Someone who floods failed joins can lock a room's joins for an hour; existing members are unaffected.
- Old app builds that expect `join_list` to return a `lists` row fail to join until they're updated.
- Until captcha is on, bulk guest sign-ups are limited only by Supabase's per-IP rate limit, and the cleanup job removes the empty ones.
