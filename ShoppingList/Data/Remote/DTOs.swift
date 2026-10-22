import Foundation

/// Wire format for `public.items`. Optionals encode as explicit `null` so clearing a field
/// (e.g. removing a quantity) actually clears it on the server during an upsert.
struct ItemDTO: Codable, Sendable, Equatable {
    var id: UUID
    var listID: UUID
    var name: String
    var quantity: String?
    var note: String?
    var category: String
    var position: Double
    var isChecked: Bool
    var checkedBy: UUID?
    var checkedAt: Date?
    var createdBy: UUID
    var updatedBy: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case listID = "list_id"
        case name, quantity, note, category, position
        case isChecked = "is_checked"
        case checkedBy = "checked_by"
        case checkedAt = "checked_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(listID, forKey: .listID)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(note, forKey: .note)
        try c.encode(category, forKey: .category)
        try c.encode(position, forKey: .position)
        try c.encode(isChecked, forKey: .isChecked)
        try c.encode(checkedBy, forKey: .checkedBy)
        try c.encode(checkedAt, forKey: .checkedAt)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

/// Wire format for `public.lists`. `invite_code` is omitted when unknown so the server generates one.
struct ListDTO: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var emoji: String?
    var inviteCode: String?
    var createdBy: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case inviteCode = "invite_code"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(emoji, forKey: .emoji)
        try c.encodeIfPresent(inviteCode, forKey: .inviteCode)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ItemDTO {
    init(_ record: ItemRecord) {
        self.init(
            id: record.id, listID: record.listID, name: record.name, quantity: record.quantity,
            note: record.note, category: record.categoryRaw, position: record.position,
            isChecked: record.isChecked, checkedBy: record.checkedBy, checkedAt: record.checkedAt,
            createdBy: record.createdBy, updatedBy: record.updatedBy, createdAt: record.createdAt,
            updatedAt: record.updatedAt, deletedAt: record.deletedAt
        )
    }
}

extension ListDTO {
    init(_ record: ListRecord) {
        self.init(
            id: record.id, name: record.name, emoji: record.emoji, inviteCode: record.inviteCode,
            createdBy: record.createdBy, createdAt: record.createdAt, updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }
}

extension JSONEncoder {
    /// Encoder for outbox payloads. ISO 8601 with fractional seconds, matching Postgres `timestamptz`.
    static let outbox: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }()
}
