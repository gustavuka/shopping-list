import Foundation
import SwiftData

/// Local mirror of `public.lists` (see docs/data-model.md).
@Model
final class ListRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String?
    /// Assigned by the server on first sync; nil for a list created offline.
    var inviteCode: String?
    /// Whether a member has set the room password (only then can others join).
    var hasPassword: Bool = false
    var createdBy: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var hasPendingChanges: Bool

    init(id: UUID = UUID(), name: String, emoji: String? = nil, createdBy: UUID, now: Date = .now) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.inviteCode = nil
        self.createdBy = createdBy
        self.createdAt = now
        self.updatedAt = .distantPast
        self.deletedAt = nil
        self.hasPendingChanges = false
    }
}
