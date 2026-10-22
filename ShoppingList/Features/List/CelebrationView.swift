import SwiftUI

/// Shown briefly when the last item goes into the cart.
struct CelebrationView: View {
    @State private var popped = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange, .pink)
                .symbolEffect(.bounce, value: popped)
            Text("All done!")
                .font(.title2.bold())
        }
        .padding(32)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .allowsHitTesting(false)
        .accessibilityHidden(true)  // announced separately
        .onAppear { popped = true }
    }
}
