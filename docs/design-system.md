# Design system

The app should feel like a first-party iOS 26 app with a bit more personality: Liquid Glass chrome, bold rounded type, colorful categories, and springy, tactile interactions.

## Principles

1. **Content first, chrome in glass.** The list is the hero. Toolbars, the add bar, and floating controls use Liquid Glass; rows stay crisp and readable.
2. **Every tap answers.** Visual change on the same frame + a haptic where it adds meaning.
3. **Motion explains state.** Things move to where they now belong (checked items glide into "In cart"), they don't just blink.
4. **Calm by default.** Sync, network, and errors stay quiet unless the user must act.

## Liquid Glass

- Use system components first (`NavigationStack` toolbars, `.toolbar`, sheets, `TabView`) — they adopt glass automatically.
- Custom floating controls (the bottom **add bar**, offline capsule, partner-activity pill) use `.glassEffect(.regular.interactive(), in: .capsule)`.
- Group adjacent glass elements in a `GlassEffectContainer` so they blend and morph; use `glassEffectID(_:in:)` for morphing transitions (e.g. add bar expanding into the item editor).
- Don't stack glass on glass, and don't put glass behind long text.
- Primary actions: `.buttonStyle(.glassProminent)`; secondary: `.buttonStyle(.glass)`.

## Typography

- `.fontDesign(.rounded)` applied at the root.
- Item names `.body` weight `.medium`; quantities `.subheadline` `.secondary`; section headers `.headline` with a category symbol.
- List title uses the large navigation title.
- Always use text styles (never fixed point sizes) so Dynamic Type works up to AX sizes.

## Color & categories

- Accent color: a fresh green (`AccentColor` in the asset catalog, with dark variant).
- Each `Category` has an SF Symbol and a tint, defined in one place (`DesignSystem/Category+Style.swift`):

| Category | Symbol | Tint |
|---|---|---|
| produce | `carrot.fill` | green |
| bakery | `birthday.cake.fill` | brown |
| dairy | `cup.and.saucer.fill` | cyan/blue |
| meat & fish | `fish.fill` | red |
| pantry | `takeoutbag.and.cup.and.straw.fill` | orange |
| frozen | `snowflake` | teal |
| drinks | `wineglass.fill` | purple |
| household | `house.fill` | indigo |
| personal care | `heart.fill` | pink |
| other | `basket.fill` | gray |

- Rows show the symbol in a small tinted circle (`.tint.opacity(0.15)` background). Use semantic system colors otherwise; everything must look right in light and dark.

## Motion

Defined once in `DesignSystem/Motion.swift`:

```swift
extension Animation {
    static let check  = Animation.snappy(duration: 0.3)
    static let move   = Animation.smooth(duration: 0.35)
    static let pop    = Animation.bouncy(duration: 0.4, extraBounce: 0.1)
}
```

Key moments:

- **Add item:** row inserts at its position with `.transition(.move(edge: .top).combined(with: .opacity))` and `.pop`; text field stays focused for rapid entry.
- **Check item:** checkbox fills with `symbolEffect(.bounce)` + `contentTransition(.symbolEffect(.replace))`, name gets an animated strikethrough, then after ~350 ms the row moves into the "In cart" section (`.move`). The short delay lets the user see the check land and undo-tap if wrong.
- **Uncheck:** reverse, immediately.
- **Delete:** swipe action; row collapses with `.opacity` + height.
- **Clear checked:** rows cascade out with a small stagger (20 ms each, capped).
- **Number changes** (counts, "3 left"): `.contentTransition(.numericText())`.
- **Empty state:** a playful `ContentUnavailableView` with an animated SF Symbol.

**Reduce Motion:** when `accessibilityReduceMotion` is on, replace movement with cross-fades and drop bounces. Wrap this in a helper (`withMotion(_:)`) so call sites don't branch.

## Haptics

Use `.sensoryFeedback` (declarative), not `UIFeedbackGenerator`.

| Event | Feedback |
|---|---|
| Item added | `.impact(weight: .light)` |
| Item checked | `.success` |
| Item unchecked | `.impact(weight: .light)` |
| Item deleted | `.impact(flexibility: .rigid)` |
| Reorder pick-up / drop | `.selection` |
| Last item checked (list done 🎉) | `.success` + small celebration animation |
| Error | `.error` |

Never fire haptics for remote (partner) changes.

## Partner activity

When a Realtime change from the partner arrives:
- The affected row briefly highlights (tint wash fading out over ~1 s).
- A small glass pill at the top shows "Ana added Eggs" for 2 s; consecutive events coalesce ("Ana added 3 items").
- No sound, no haptic.

## Accessibility

- Every icon-only button has an `accessibilityLabel`; rows combine into one element ("Milk, 2 liters, dairy, not in cart") with a custom action for check/uncheck.
- Hit targets ≥ 44×44 pt.
- Verify contrast of tinted symbols in both appearances.
- Support Dynamic Type up to AX5 (rows grow; no truncating item names to one line at AX sizes).
- Test with VoiceOver at least once per feature.
