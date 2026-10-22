import SwiftData
import SwiftUI

@main
struct ShoppingListApp: App {
    // Keep init cheap: open the store, build services. Nothing touches the network here
    // (docs/performance.md#launch).
    private let container: ModelContainer
    private let store: ListStore

    init() {
        do {
            container = try .app()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        store = ListStore(context: container.mainContext, currentUserID: LocalIdentity.userID)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .environment(store)
        }
        .modelContainer(container)
    }
}

/// Opens straight into the main list. Rendered from the local store on the first frame.
struct RootView: View {
    @Environment(ListStore.self) private var store
    @Query(filter: #Predicate<ListRecord> { $0.deletedAt == nil }, sort: \ListRecord.createdAt)
    private var lists: [ListRecord]

    var body: some View {
        NavigationStack {
            if let list = lists.first {
                ShoppingListView(list: list)
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                    .onAppear { store.ensureDefaultList() }
            }
        }
    }
}

#Preview("List") {
    PreviewSupport.root(seeded: true)
}

#Preview("Empty") {
    PreviewSupport.root(seeded: false)
}

#Preview("Large type, dark") {
    PreviewSupport.root(seeded: true)
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
