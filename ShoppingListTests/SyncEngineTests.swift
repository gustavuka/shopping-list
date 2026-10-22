import Foundation
import SwiftData
import Testing
@testable import ShoppingList

@MainActor
struct SyncEngineTests {
    let me = UUID()
    let partner = UUID()
    let container: ModelContainer
    let store: ListStore
    let remote: FakeRemote
    let sync: SyncEngine

    init() throws {
        container = try .app(inMemory: true)
        store = ListStore(context: container.mainContext, currentUserID: me)
        remote = FakeRemote(me: me)
        sync = SyncEngine(
            context: container.mainContext,
            remote: remote,
            userID: me,
            cursors: SyncCursors(userID: me, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }

    private func outboxCount() throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<OutboxEntry>())
    }

    private func items() throws -> [ItemRecord] {
        try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
    }

    @Test func pushDrainsOutboxAndAdoptsServerVersion() async throws {
        let list = store.ensureDefaultList()
        let milk = try #require(store.addItem(named: "Milk", to: list))

        await sync.push()

        #expect(try outboxCount() == 0)
        #expect(!milk.hasPendingChanges)
        #expect(milk.updatedAt > .distantPast)
        #expect(list.inviteCode == "ABC234")
        #expect(await remote.items[milk.id]?.name == "Milk")
    }

    @Test func editDuringInFlightPushIsNotLost() async throws {
        let list = store.ensureDefaultList()
        let eggs = try #require(store.addItem(named: "Eggs", to: list))
        await sync.push()

        store.setChecked(true, for: eggs)
        let store = store
        let eggsID = eggs.id
        await remote.setBeforeItemUpsert { @MainActor in
            // The user taps again while the request is in flight.
            let descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == eggsID })
            if let again = try? store.context.fetch(descriptor).first {
                store.setChecked(false, for: again)
            }
        }
        await sync.push()
        await remote.setBeforeItemUpsert(nil)

        #expect(await remote.items[eggs.id]?.isChecked == false, "the newer edit was pushed in a second round")
        #expect(try outboxCount() == 0)
        #expect(!eggs.isChecked)
    }

    @Test func pullBringsInPartnerItemsButKeepsPendingLocalEdits() async throws {
        let list = store.ensureDefaultList()
        let bread = try #require(store.addItem(named: "Bread", to: list))
        await sync.push()

        let serverBread = try #require(await remote.items[bread.id])
        var partnerEdit = serverBread
        partnerEdit.name = "Sourdough"
        await remote.partnerWrites(partnerEdit, partner: partner, live: false)
        var coffee = serverBread
        coffee.id = UUID()
        coffee.name = "Coffee"
        await remote.partnerWrites(coffee, partner: partner, live: false)

        store.update(bread, name: "Rye bread", quantity: nil, note: nil, category: .bakery)  // pending local edit
        await sync.pull()

        #expect(bread.name == "Rye bread", "pending local edit wins until it is pushed")
        #expect(try items().contains { $0.name == "Coffee" })
    }

    @Test func liveChangesFromPartnerApplyAndRaiseActivity() async throws {
        let list = store.ensureDefaultList()
        let milk = try #require(store.addItem(named: "Milk", to: list))
        await sync.syncNow()  // push + pull + subscribe

        var checked = try #require(await remote.items[milk.id])
        checked.isChecked = true
        await remote.partnerWrites(checked, partner: partner)
        try await Task.sleep(for: .milliseconds(100))

        #expect(milk.isChecked)
        #expect(sync.latestActivity?.verb == .checked)
        #expect(sync.recentlyChangedIDs.contains(milk.id))
    }

    @Test func rejectedWriteRestoresServerVersion() async throws {
        let list = store.ensureDefaultList()
        let tea = try #require(store.addItem(named: "Tea", to: list))
        await sync.push()

        store.update(tea, name: "Green tea", quantity: nil, note: nil, category: .pantry)
        await remote.reject(itemID: tea.id)
        await sync.push()

        #expect(tea.name == "Tea")
        #expect(!tea.hasPendingChanges)
        #expect(try outboxCount() == 0)
        #expect(sync.status.lastRejection != nil)
    }

    @Test func listsRemovedOnServerDisappearLocally() async throws {
        let list = store.ensureDefaultList()
        store.addItem(named: "Rice", to: list)
        await sync.syncNow()

        await remote.removeList(list.id)
        await sync.pull()

        #expect(try container.mainContext.fetchCount(FetchDescriptor<ListRecord>()) == 0)
        #expect(try items().isEmpty)
    }
}

extension SyncEngineTests {
    @Test func sharingAndJoiningARoom() async throws {
        let list = store.ensureDefaultList()
        try await sync.setPassword("pao-de-queijo", for: list)
        #expect(list.hasPassword)
        #expect(list.inviteCode == "ABC234", "setting a password pushes the list first")

        await #expect(throws: FakeRejection.self) {
            _ = try await sync.join(inviteCode: "abc234", password: "wrong")
        }
        let joinedID = try await sync.join(inviteCode: "abc234", password: "pao-de-queijo")
        #expect(joinedID == list.id)
    }
}
