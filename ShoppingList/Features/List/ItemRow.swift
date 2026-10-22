import SwiftUI

/// One item. Tapping toggles; checking shows the check + strikethrough immediately, then
/// commits after `checkSettleDelay` so the row glides into "In cart". Tapping again during
/// the delay cancels (docs/design-system.md#motion).
struct ItemRow: View {
    let item: ItemRecord
    let onSetChecked: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingCheck: Task<Void, Never>?
    @State private var showsCheckedEarly = false
    /// Only surfaces after a few seconds: brief pending states are normal and shouldn't flicker.
    @State private var showsUnsynced = false

    private var isChecked: Bool { item.isChecked || showsCheckedEarly }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isChecked)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .strikethrough(isChecked, color: .secondary)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if showsUnsynced {
                    Image(systemName: "icloud.slash")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                        .accessibilityLabel("Not synced yet")
                }

                CategoryBadge(category: item.category, size: 28)
                    .opacity(isChecked ? 0.4 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("item.\(item.name)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityHint(isChecked ? "Double-tap to put back on the list" : "Double-tap to mark as in cart")
        .onDisappear { pendingCheck?.cancel() }
        .task(id: item.hasPendingChanges) {
            guard item.hasPendingChanges else {
                withAnimation { showsUnsynced = false }
                return
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showsUnsynced = true }
        }
    }

    private var detail: String? {
        let parts = [item.quantity, item.note].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let state = isChecked ? String(localized: "in cart") : String(localized: "not in cart")
        let sync = showsUnsynced ? String(localized: "not synced yet") : nil
        return [item.name, detail, String(localized: item.category.displayName), state, sync]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func toggle() {
        if let pendingCheck {
            // Second tap during the settle delay: undo.
            pendingCheck.cancel()
            self.pendingCheck = nil
            withMotion(.check, reduceMotion: reduceMotion) { showsCheckedEarly = false }
            return
        }

        if item.isChecked {
            withMotion(.move, reduceMotion: reduceMotion) { onSetChecked(false) }
            return
        }

        withMotion(.check, reduceMotion: reduceMotion) { showsCheckedEarly = true }
        pendingCheck = Task {
            try? await Task.sleep(for: checkSettleDelay)
            guard !Task.isCancelled else { return }
            withMotion(.move, reduceMotion: reduceMotion) {
                onSetChecked(true)
                showsCheckedEarly = false
            }
            pendingCheck = nil
        }
    }
}
