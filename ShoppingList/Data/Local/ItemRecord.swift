import Foundation
import SwiftData

/// Local mirror of `public.items` (see docs/data-model.md).
@Model
final class ItemRecord {
    #Index<ItemRecord>([\.listID], [\.updatedAt])

    @Attribute(.unique) var id: UUID
    var listID: UUID
    var name: String
    var quantity: String?
    var note: String?
    var categoryRaw: String
    var position: Double
    var isChecked: Bool
    var checkedBy: UUID?
    var checkedAt: Date?
    var createdBy: UUID
    var updatedBy: UUID
    var createdAt: Date
    /// Last server-confirmed `updated_at` (local edits don't bump it; see docs/sync.md#conflict-resolution).
    var updatedAt: Date
    var deletedAt: Date?
    /// Local-only: true while an outbox entry for this row exists.
    var hasPendingChanges: Bool

    var category: Category {
        get { Category(storedValue: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        listID: UUID,
        name: String,
        quantity: String? = nil,
        note: String? = nil,
        category: Category,
        position: Double,
        createdBy: UUID,
        now: Date = .now
    ) {
        self.id = id
        self.listID = listID
        self.name = name
        self.quantity = quantity
        self.note = note
        self.categoryRaw = category.rawValue
        self.position = position
        self.isChecked = false
        self.checkedBy = nil
        self.checkedAt = nil
        self.createdBy = createdBy
        self.updatedBy = createdBy
        self.createdAt = now
        self.updatedAt = .distantPast
        self.deletedAt = nil
        self.hasPendingChanges = false
    }
}
