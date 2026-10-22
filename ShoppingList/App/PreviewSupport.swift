import SwiftData
import SwiftUI

/// In-memory store with sample data for `#Preview`s.
@MainActor
enum PreviewSupport {
    static func root(seeded: Bool) -> some View {
        let container = try! ModelContainer.app(inMemory: true)  // previews only
        let store = ListStore(context: container.mainContext, currentUserID: UUID())
        let list = store.ensureDefaultList()
        if seeded {
            for name in ["Bananas", "Milk", "Sourdough bread", "Eggs", "Chicken thighs", "Olive oil",
                         "Ice cream", "Toilet paper", "Tomatoes", "Coffee"] {
                store.addItem(named: name, to: list)
            }
            let descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.name == "Coffee" || $0.name == "Eggs" })
            for item in (try? container.mainContext.fetch(descriptor)) ?? [] {
                store.setChecked(true, for: item)
            }
        }
        return RootView()
            .fontDesign(.rounded)
            .environment(store)
            .modelContainer(container)
    }
}
