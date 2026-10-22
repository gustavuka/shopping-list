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

- Sign in with email + 6-digit code.
- Create a list; invite the partner with a short invite code (shareable via the share sheet as a deep link).
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
- Android or web clients (Supabase keeps the door open — see [ADR 0002](decisions/0002-supabase-backend.md)).
- More than one household / complex permission roles.
- Push notifications (needs a paid Apple Developer account).

## Milestones

- [x] **M0 — Foundations:** docs, Supabase schema + RLS + pgTAP tests, XcodeGen project.
- [x] **M1 — Local list:** add / check / edit / delete / clear cart, category grouping, motion + haptics. Works fully offline; changes are queued in the outbox.
- [ ] **M2 — Auth:** email OTP sign-in screens, session restore, replace `LocalIdentity` with the real user id.
- [ ] **M3 — Sync:** `SyncEngine` drains the outbox, delta fetch, Realtime, conflict resolution, offline indicator.
- [ ] **M4 — Sharing:** invite code / share link, join flow, partner-activity hint.
- [ ] **M5 — Polish:** app icon, celebration on last item, reorder, Instruments pass, two-device checklist.

## Future ideas

- Sign in with Apple (once a paid developer account exists).
- Home Screen / Lock Screen widgets; interactive widget to check items.
- App Intents / Siri: "Add eggs to the shopping list".
- Live Activity while in "shopping mode".
- Suggestions from purchase history ("You usually buy bread on Fridays").
- Push notification when the partner starts shopping.
