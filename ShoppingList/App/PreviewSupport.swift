import Foundation
import SwiftData
import SwiftUI

/// In-memory store with sample data and an offline backend, for `#Preview`s.
@MainActor
enum PreviewSupport {
    static func session(seeded: Bool) -> some View {
        let container = try! ModelContainer.app(inMemory: true)  // previews only
        let userID = UUID()
        let store = ListStore(context: container.mainContext, currentUserID: userID)
        let sync = SyncEngine(
            context: container.mainContext,
            remote: PreviewRemote(),
            userID: userID,
            cursors: SyncCursors(userID: userID, defaults: UserDefaults(suiteName: "previews")!)
        )
        if seeded {
            seed(store)
        }
        return SessionRootView()
            .fontDesign(.rounded)
            .environment(store)
            .environment(sync)
            .environment(NetworkMonitor())
            .modelContainer(container)
    }
}

extension PreviewSupport {
    /// A realistic list: several sections, a couple of items already in the cart.
    static func seed(_ store: ListStore) {
        let list = store.ensureDefaultList()
        for name in ["Bananas", "Milk", "Sourdough bread", "Eggs", "Chicken thighs", "Olive oil",
                     "Ice cream", "Toilet paper", "Tomatoes", "Coffee"] {
            store.addItem(named: name, to: list)
        }
        let descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.name == "Coffee" || $0.name == "Eggs" })
        for item in (try? store.context.fetch(descriptor)) ?? [] {
            store.setChecked(true, for: item)
        }
    }
}

/// A backend that is always empty and never fails.
struct PreviewRemote: RemoteSyncing {
    func upsertLists(_ lists: [ListDTO]) async throws -> [ListDTO] { lists }
    func upsertItems(_ items: [ItemDTO]) async throws -> [ItemDTO] { items }
    func fetchLists() async throws -> [ListDTO] { [] }
    func fetchItems(listID: UUID, updatedAfter: Date?) async throws -> [ItemDTO] { [] }
    func fetchItems(ids: [UUID]) async throws -> [ItemDTO] { [] }
    func fetchProfiles() async throws -> [ProfileDTO] { [] }
    func updateDisplayName(_ name: String, userID: UUID) async throws {}
    func joinList(inviteCode: String, password: String) async throws -> ListDTO { throw CancellationError() }
    func setListPassword(listID: UUID, password: String) async throws {}
    func changes(listIDs: [UUID]) async -> AsyncStream<RemoteChange> { AsyncStream { $0.finish() } }
    func classify(_ error: any Error) -> RemoteFailure { .transient }
}

#Preview("List") {
    PreviewSupport.session(seeded: true)
}

#Preview("Empty") {
    PreviewSupport.session(seeded: false)
}

#Preview("Large type, dark") {
    PreviewSupport.session(seeded: true)
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
