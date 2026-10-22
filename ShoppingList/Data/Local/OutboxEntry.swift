import Foundation
import SwiftData

enum OutboxEntity: String, Codable, Sendable {
    case item
    case list
}

/// A pending upsert, persisted so changes survive app kills (see docs/sync.md#writes-the-outbox).
/// One entry per row: newer mutations replace `payload` instead of adding entries.
@Model
final class OutboxEntry {
    #Index<OutboxEntry>([\.rowID], [\.enqueuedAt])

    var entityRaw: String
    var rowID: UUID
    /// JSON-encoded DTO snapshot of the full row.
    var payload: Data
    var enqueuedAt: Date
    var attempts: Int

    var entity: OutboxEntity {
        OutboxEntity(rawValue: entityRaw) ?? .item
    }

    init(entity: OutboxEntity, rowID: UUID, payload: Data, now: Date = .now) {
        self.entityRaw = entity.rawValue
        self.rowID = rowID
        self.payload = payload
        self.enqueuedAt = now
        self.attempts = 0
    }
}
