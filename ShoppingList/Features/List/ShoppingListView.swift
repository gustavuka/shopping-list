import SwiftData
import SwiftUI

/// The main screen: items grouped by store section, checked items in "In cart" at the bottom.
struct ShoppingListView: View {
    let list: ListRecord

    @Environment(ListStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var items: [ItemRecord]
    @State private var editingItem: ItemRecord?

    // Haptics fire only for local actions, never for partner changes (docs/design-system.md#haptics).
    @State private var addedTick = 0
    @State private var checkedTick = 0
    @State private var uncheckedTick = 0
    @State private var deletedTick = 0

    init(list: ListRecord) {
        self.list = list
        let listID = list.id
        _items = Query(
            filter: #Predicate<ItemRecord> { $0.listID == listID && $0.deletedAt == nil },
            sort: \ItemRecord.position
        )
    }

    var body: some View {
        let sections = ItemSections(items)

        List {
            ForEach(sections.toBuy, id: \.category) { section in
                Section {
                    ForEach(section.items) { row(for: $0) }
                } header: {
                    Label {
                        Text(section.category.displayName)
                    } icon: {
                        Image(systemName: section.category.symbolName)
                            .foregroundStyle(section.category.tint)
                    }
                    .font(.headline)
                }
            }

            if !sections.inCart.isEmpty {
                Section {
                    ForEach(sections.inCart) { row(for: $0) }
                } header: {
                    Label("In cart", systemImage: "cart.fill")
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to buy", systemImage: "cart")
                        .symbolEffect(.wiggle, options: .nonRepeating)
                } description: {
                    Text("Add what you need below — it shows up on both phones.")
                }
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            AddItemBar { name in
                withMotion(.pop, reduceMotion: reduceMotion) {
                    if store.addItem(named: name, to: list) != nil { addedTick += 1 }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationSubtitle(subtitle(remaining: sections.remainingCount, total: items.count))
        .toolbar { toolbarContent(hasChecked: !sections.inCart.isEmpty) }
        .sheet(item: $editingItem) { item in
            ItemEditorSheet(item: item)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addedTick)
        .sensoryFeedback(.success, trigger: checkedTick)
        .sensoryFeedback(.impact(weight: .light), trigger: uncheckedTick)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: deletedTick)
    }

    private func row(for item: ItemRecord) -> some View {
        ItemRow(item: item) { isChecked in
            store.setChecked(isChecked, for: item)
            if isChecked { checkedTick += 1 } else { uncheckedTick += 1 }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withMotion(.move, reduceMotion: reduceMotion) { store.delete(item) }
                deletedTick += 1
            }
        }
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil") { editingItem = item }
                .tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingItem = item }
            Button("Delete", systemImage: "trash", role: .destructive) {
                withMotion(.move, reduceMotion: reduceMotion) { store.delete(item) }
                deletedTick += 1
            }
        }
    }

    private func subtitle(remaining: Int, total: Int) -> String {
        if total == 0 { return "" }
        return remaining == 0 ? String(localized: "All in the cart 🎉") : String(localized: "\(remaining) left")
    }

    @ToolbarContentBuilder
    private func toolbarContent(hasChecked: Bool) -> some ToolbarContent {
        if hasChecked {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear cart", systemImage: "cart.badge.minus") {
                    withMotion(.move, reduceMotion: reduceMotion) { store.clearChecked(in: list.id) }
                    deletedTick += 1
                }
            }
        }
    }
}

/// Groups items for display. Plain value type so grouping logic is testable without SwiftUI.
struct ItemSections {
    struct Group {
        let category: Category
        let items: [ItemRecord]
    }

    let toBuy: [Group]
    let inCart: [ItemRecord]

    var remainingCount: Int { toBuy.reduce(0) { $0 + $1.items.count } }

    init(_ items: [ItemRecord]) {
        let unchecked = Dictionary(grouping: items.filter { !$0.isChecked }, by: \.category)
        toBuy = Category.allCases.compactMap { category in
            guard let items = unchecked[category], !items.isEmpty else { return nil }
            return Group(category: category, items: items)
        }
        inCart = items
            .filter(\.isChecked)
            .sorted { ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast) }
    }
}
