# 0007. Guest users and password-protected rooms instead of email sign-in

- **Status:** Accepted
- **Date:** 2026-10-22
- **Supersedes:** [0003](0003-email-otp-auth.md)

## Context
Email sign-in turned out to be the heaviest part of the app for the least value:
- On Supabase's free plan, the built-in email sender only delivers to members of the project's team, at 2 emails/hour, and email templates can't be customized (so no 6-digit codes, only magic links).
- Reaching anyone else (a partner, or App Store users later) would need a custom SMTP sender on a domain we own.
- For a shared shopping list, the thing that matters is the *room*, not proving who a person is.

## Decision
- Every phone signs in as a Supabase **anonymous (guest) user** on first launch. The only input is a display name, stored in the user metadata → `profiles.display_name`. No email, no password.
- A list is a **room**: members share its 6-character `invite_code` plus a **room password** chosen by a member (≥ 4 characters, required before anyone can join). Passwords are bcrypt-hashed in `list_secrets`, a table with RLS and no policies, touched only by `set_list_password` / `join_list` (security definer). Wrong code and wrong password produce the same error.
- RLS is unchanged: guests are `authenticated` users with a real `auth.uid()`.
- Losing the phone or resetting the app loses that guest identity, not the room: rejoin with code + password.

## Consequences
- No email infrastructure at all; works for anyone, today, on the free plan.
- First launch needs the network once (≈1 request) to create the guest user.
- Guest users can't be recovered on a new phone except by rejoining rooms. Later, a guest can be upgraded to a full account (email or Sign in with Apple via `linkIdentity` / `updateUser`) **keeping the same user id**, so no data migration is needed.
- Before a public App Store release: add a captcha to anonymous sign-ins (Supabase supports Turnstile/hCaptcha) to stop bulk user creation, add "leave room / delete my data", and consider a paid Supabase plan (free projects pause after ~7 days idle).
