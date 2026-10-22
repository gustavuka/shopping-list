import SwiftData

extension ModelContainer {
    static let appSchema = Schema([ListRecord.self, ItemRecord.self, OutboxEntry.self])

    static func app(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: appSchema,
            configurations: ModelConfiguration(schema: appSchema, isStoredInMemoryOnly: inMemory)
        )
    }
}
