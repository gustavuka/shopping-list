import SwiftUI

/// Small floating glass capsule for partner activity, offline state, and sync problems.
struct StatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
