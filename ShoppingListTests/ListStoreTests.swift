import Foundation
import SwiftData
import Testing
@testable import ShoppingList

@MainActor
struct ListStoreTests {
    let container: ModelContainer
    let store: ListStore
    let me = UUID()

    init() throws {
        container = try .app(inMemory: true)
        store = ListStore(context: container.mainContext, currentUserID: me)
    }

    private func outbox() throws -> [OutboxEntry] {
        try container.mainContext.fetch(FetchDescriptor<OutboxEntry>())
    }

    @Test func defaultListIsCreatedOnceAndQueued() throws {
        let first = store.ensureDefaultList()
        let second = store.ensureDefaultList()
        #expect(first.id == second.id)
        #expect(first.hasPendingChanges)
        #expect(try outbox().map(\.entity) == [.list])
    }

    @Test func addingTrimsGuessesCategoryAndGoesOnTop() throws {
        let list = store.ensureDefaultList()
        let milk = try #require(store.addItem(named: "  Milk ", to: list))
        let bread = try #require(store.addItem(named: "Bread", to: list))

        #expect(milk.name == "Milk")
        #expect(milk.category == .dairy)
        #expect(milk.createdBy == me)
        #expect(bread.position < milk.position)
        #expect(store.addItem(named: "   ", to: list) == nil)
    }

    @Test func repeatedMutationsCoalesceIntoOneOutboxEntry() throws {
        let list = store.ensureDefaultList()
        let item = try #require(store.addItem(named: "Eggs", to: list))
        store.setChecked(true, for: item)
        store.setChecked(false, for: item)
        store.setChecked(true, for: item)

        let entries = try outbox().filter { $0.rowID == item.id }
        #expect(entries.count == 1)

        let sent = try JSONDecoder.iso8601Fractional.decode(ItemDTO.self, from: entries[0].payload)
        #expect(sent.isChecked)
        #expect(sent.checkedBy == me)
    }

    @Test func clearingFieldsSendsExplicitNulls() throws {
        let list = store.ensureDefaultList()
        let item = try #require(store.addItem(named: "Rice", to: list))
        store.update(item, name: "Rice", quantity: "2 kg", note: nil, category: .pantry)
        store.update(item, name: "Rice", quantity: "  ", note: nil, category: .pantry)

        let entry = try #require(try outbox().first { $0.rowID == item.id })
        let json = try #require(try JSONSerialization.jsonObject(with: entry.payload) as? [String: Any])
        #expect(json["quantity"] is NSNull)
        #expect(json["deleted_at"] is NSNull)
    }

    @Test func clearCheckedSoftDeletesOnlyCheckedItems() throws {
        let list = store.ensureDefaultList()
        let milk = try #require(store.addItem(named: "Milk", to: list))
        let bread = try #require(store.addItem(named: "Bread", to: list))
        store.setChecked(true, for: milk)

        store.clearChecked(in: list.id)

        #expect(milk.deletedAt != nil)
        #expect(bread.deletedAt == nil)
    }

    @Test func notifiesSyncOnEveryChange() throws {
        var notifications = 0
        store.onLocalChange = { notifications += 1 }
        let list = store.ensureDefaultList()
        let item = try #require(store.addItem(named: "Tea", to: list))
        store.delete(item)
        #expect(notifications == 3)
    }
}

extension JSONDecoder {
    static let iso8601Fractional: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return try Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        return decoder
    }()
}
