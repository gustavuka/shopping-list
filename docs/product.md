# Product

## Vision

One shared list for a household. Add things the moment you notice you're out of them; at the market, check them off with one tap and watch your partner's phone update live. It should open instantly, feel buttery, and be a small joy to use.

## Users

Two people (a couple) sharing one household. Both are equal editors — there is no "owner vs. guest" in the UX, even though the data model records who created a list.

## Core jobs

1. **Capture** — "We're out of milk." Add an item in under 2 seconds from app launch.
2. **Shop** — At the market, walk the list, tap to check items into the cart, even with bad signal.
3. **Coordinate** — See what the other person added or already grabbed, live (e.g. splitting up in the store).

## MVP scope (v1)

- Start as a guest (just a name — [ADR 0007](decisions/0007-guest-users-and-room-passwords.md)) or with an email + password account; guests can save themselves as an account later, keeping everything ([ADR 0008](decisions/0008-optional-email-accounts.md)).
- Every list is a room: share its code + a password you choose; the partner taps **Join a room** and enters both. A `shoppinglist://join/CODE` link pre-fills the code.
- Multiple lists supported in the model, but the UX is optimized for one main list (opens straight into it).
- Items: name, optional quantity, optional note, category (auto-guessed from name, editable).
- Add, edit, delete (swipe), reorder within the list.
- Check / uncheck; checked items animate into an "In cart" section.
- "Clear checked" action (soft-deletes checked items) after shopping.
- Grouping by category so the list follows the store's layout.
- Live sync between devices; full offline use with automatic catch-up.
- Subtle indicator of partner activity ("Ana added Eggs").

## Non-goals for v1

- Prices, budgets, receipts.
- Recipes / meal planning.
- A native Android app (the web app covers Android — [ADR 0009](decisions/0009-web-pwa-client.md)).
- More than one household / complex permission roles.
- Push notifications (needs a paid Apple Developer account).

## Milestones

- [x] **M0 — Foundations:** docs, Supabase schema + RLS + pgTAP tests, XcodeGen project.
- [x] **M1 — Local list:** add / check / edit / delete / clear cart, category grouping, motion + haptics. Works fully offline; changes are queued in the outbox.
- [x] **M2 — Auth:** guest users (originally email OTP; replaced by ADR 0007), session restore from Keychain, per-user session, reset wipes local data.
- [x] **M3 — Sync:** outbox push (with mid-flight revisions), delta fetch, Realtime, conflict resolution, offline pill, rejection handling.
- [x] **M4 — Sharing:** rooms with code + password, share sheet + `shoppinglist://join/CODE` deep link, join flow, list switcher, partner-activity pill + row highlight, display names.
- [x] **M5 — Polish:** unsynced-row marker, background flush of the outbox, app icon, celebration on last item, drag to reorder, UI smoke test, launch timer.
- [ ] **M6 — Ship to both phones:** ~~Supabase cloud project~~ (done: `shopping-list`, São Paulo), install on both iPhones, Instruments pass on device, two-device checklist ([testing.md](testing.md)).
- [x] **M6.5 — Accounts:** optional email + password accounts, guest → account upgrade keeping the same user.
- [ ] **M6.6 — Web app (PWA):** use it from a link, no install ([ADR 0009](decisions/0009-web-pwa-client.md)). *Started:* `web/` with guest/account sign-in, rooms (share, join, `?join=` links), add / check / edit / swipe-delete / clear cart, category grouping, offline outbox, delta fetch, Realtime, partner activity. *Hardened* for a public URL ([ADR 0010](decisions/0010-public-web-hardening.md)). *Next:* host it (static), try it on both phones, drag to reorder, captcha (web ready; needs iOS support) before sharing the link widely.
- [ ] **M7 — App Store (later):** paid Apple Developer account, captcha on sign-up, leave room / delete my account & data, Sign in with Apple, password reset (SMTP), privacy policy, paid Supabase plan.

## Future ideas

- Sign in with Apple as another way to sign in (needs the paid developer account).
- "Forgot password" (needs an email sender / custom SMTP).
- Home Screen / Lock Screen widgets; interactive widget to check items.
- App Intents / Siri: "Add eggs to the shopping list".
- Live Activity while in "shopping mode".
- Suggestions from purchase history ("You usually buy bread on Fridays").
- Push notification when the partner starts shopping.
