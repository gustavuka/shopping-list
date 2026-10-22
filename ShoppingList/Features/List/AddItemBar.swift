import SwiftUI

/// Floating glass capsule pinned to the bottom. Stays focused after submit for rapid entry.
struct AddItemBar: View {
    let onAdd: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    TextField("Add an item", text: $text)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .autocorrectionDisabled(false)
                        .onSubmit(submit)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .capsule)
                .onTapGesture { isFocused = true }

                if isFocused {
                    Button("Done", systemImage: "keyboard.chevron.compact.down") {
                        isFocused = false
                    }
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.pop, value: isFocused)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func submit() {
        guard canSubmit else {
            isFocused = false
            return
        }
        onAdd(text)
        text = ""
        isFocused = true  // keep the keyboard up for the next item
    }
}
