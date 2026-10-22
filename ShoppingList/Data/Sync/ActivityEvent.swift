import Foundation

/// "Ana added Eggs" — a live change made by someone else (docs/design-system.md#partner-activity).
struct ActivityEvent: Equatable, Identifiable, Sendable {
    enum Verb: Equatable, Sendable {
        case added, checked, unchecked, edited, removed
    }

    let id = UUID()
    let actorID: UUID
    let actorName: String
    let verb: Verb
    var itemNames: [String]
    var date: Date

    var message: String {
        let subject = itemNames.count == 1
            ? itemNames[0]
            : String(localized: "\(itemNames.count) items")
        return switch verb {
        case .added: String(localized: "\(actorName) added \(subject)")
        case .checked: String(localized: "\(actorName) got \(subject)")
        case .unchecked: String(localized: "\(actorName) put back \(subject)")
        case .edited: String(localized: "\(actorName) edited \(subject)")
        case .removed: String(localized: "\(actorName) removed \(subject)")
        }
    }

    var symbolName: String {
        switch verb {
        case .added: "plus.circle.fill"
        case .checked: "checkmark.circle.fill"
        case .unchecked: "arrow.uturn.backward.circle.fill"
        case .edited: "pencil.circle.fill"
        case .removed: "minus.circle.fill"
        }
    }

    /// Consecutive events of the same kind from the same person within a few seconds merge
    /// ("Ana added 3 items") instead of flashing one pill per row.
    func canMerge(_ other: ActivityEvent) -> Bool {
        other.actorID == actorID && other.verb == verb && other.date.timeIntervalSince(date) < 3
    }
}
