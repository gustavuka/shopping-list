# 0008. Optional email + password accounts on top of guests

- **Status:** Accepted
- **Date:** 2026-10-22
- **Amends:** [0007](0007-guest-users-and-room-passwords.md) (rooms and guests stay as they are)

## Context
Guests ([ADR 0007](0007-guest-users-and-room-passwords.md)) are the fastest start, but a guest identity lives on one phone: a new phone means typing your name again and rejoining every room. Some people want to "log in and have their name already". Email *delivery* is the constraint (free-plan Supabase only emails team members, 2/hour), so whatever we add must not depend on sending email.

## Decision
- Offer **email + password accounts** next to guests: *Create account* and *Sign in* on the welcome screen, *Save as account* / *Sign in* in Settings.
- **Email confirmation stays off** (`enable_confirmations = false`), so sign-up returns a session immediately and no email is ever sent.
- **Guests upgrade in place:** `auth.update(user: email + password)` turns the anonymous user into a permanent one with the **same user id**, so name, lists and room memberships carry over. With confirmations off this applies immediately (verified locally and on the cloud project).
- **Rooms are unchanged:** joining is still code + password, for guests and accounts alike.
- Signing in to a *different* account on a phone replaces the current user: local data is wiped and the new account's rooms are pulled from the server. For guests, Settings warns about this.

## Consequences
- Accounts work today on the free plan, with no email infrastructure.
- **No "forgot password" yet:** resetting needs a working email sender (custom SMTP). Until then, a forgotten password means using a guest and rejoining rooms.
- Emails aren't verified, so anyone could register an address they don't own. Acceptable for a household app; revisit with SMTP (turn confirmations on) before relying on email for anything else.
- Sign in with Apple can be added later as another identity (requires the paid developer account); guests and email accounts can link to it.
