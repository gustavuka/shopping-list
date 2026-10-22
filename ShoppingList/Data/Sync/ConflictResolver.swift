import Foundation

/// Row-level last-write-wins by server `updated_at`, protecting pending local edits.
/// Pure logic so it's trivially testable (docs/sync.md#conflict-resolution).
enum ConflictResolver {
    struct LocalState: Equatable {
        var updatedAt: Date
        var hasPendingChanges: Bool
    }

    enum Decision: Equatable {
        case insert
        case overwrite
        /// Pending local write will land later and win, or the event is stale / our own echo.
        case skip
    }

    static func decide(local: LocalState?, remoteUpdatedAt: Date) -> Decision {
        guard let local else { return .insert }
        if local.hasPendingChanges { return .skip }
        // Equal timestamps mean we already have this exact version (typically our own write echoing back).
        return remoteUpdatedAt > local.updatedAt ? .overwrite : .skip
    }
}
