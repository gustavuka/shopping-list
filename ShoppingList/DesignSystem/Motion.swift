import SwiftUI

/// Spring presets from docs/design-system.md#motion. Use these instead of ad-hoc animations.
extension Animation {
    static let check = Animation.snappy(duration: 0.3)
    static let move = Animation.smooth(duration: 0.35)
    static let pop = Animation.bouncy(duration: 0.4, extraBounce: 0.1)
    /// Replacement for movement and bounce when Reduce Motion is on.
    static let reduced = Animation.easeInOut(duration: 0.2)
}

/// `withAnimation` that honors Reduce Motion: movement becomes a short cross-fade.
@MainActor
func withMotion<Result>(
    _ animation: Animation,
    reduceMotion: Bool,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(reduceMotion ? .reduced : animation, body)
}

/// How long a freshly checked row lingers (struck through) before gliding into "In cart",
/// so the user sees the check land and can tap again to undo.
let checkSettleDelay: Duration = .milliseconds(350)
