import SwiftData
import SwiftUI

/// The main screen: items grouped by store section, checked items in "In cart" at the bottom.
struct ShoppingListView: View {
    let list: ListRecord
    let lists: [ListRecord]
    let onSelect: (ListRecord) -> Void
    let onShow: (SessionSheet) -> Void

    @Environment(ListStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var items: [ItemRecord]
    @State private var editingItem: ItemRecord?
    @State private var visibleActivity: ActivityEvent?
    @State private var showsRejection = false
    @State private var isCelebrating = false

    // Haptics fire only for local actions, never for partner changes (docs/design-system.md#haptics).
    @State private var addedTick = 0
    @State private var checkedTick = 0
    @State private var uncheckedTick = 0
    @State private var deletedTick = 0
    @State private var movedTick = 0

    init(
        list: ListRecord,
        lists: [ListRecord],
        onSelect: @escaping (ListRecord) -> Void,
        onShow: @escaping (SessionSheet) -> Void
    ) {
        self.list = list
        self.lists = lists
        self.onSelect = onSelect
        self.onShow = onShow
        let listID = list.id
        _items = Query(
            filter: #Predicate<ItemRecord> { $0.listID == listID && $0.deletedAt == nil },
            sort: \ItemRecord.position
        )
    }

    var body: some View {
        let sections = ItemSections(items)

        overlays(on: listContent(sections))
            .navigationTitle(list.name)
            .navigationSubtitle(subtitle(remaining: sections.remainingCount, total: items.count))
            .toolbar { toolbarContent(hasChecked: !sections.inCart.isEmpty) }
            .toolbarTitleMenu { listSwitcher }
            .refreshable { await sync.syncNow() }
            .onAppear { LaunchTimer.firstFrameRendered("list") }
            .task(id: sync.latestActivity?.id) { await showActivity() }
            .task(id: sync.status.lastRejection) { await showRejection() }
            .sheet(item: $editingItem) { item in
                ItemEditorSheet(item: item)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: addedTick)
            .sensoryFeedback(.success, trigger: checkedTick)
            .sensoryFeedback(.impact(weight: .light), trigger: uncheckedTick)
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: deletedTick)
            .sensoryFeedback(.selection, trigger: movedTick)
    }

    private func listContent(_ sections: ItemSections) -> some View {
        List {
            ForEach(sections.toBuy, id: \.category) { section in
                Section {
                    ForEach(section.items) { row(for: $0) }
                        .onMove { move(in: section.items, from: $0, to: $1) }
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
    }

    private func overlays(on content: some View) -> some View {
        content
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
            .overlay(alignment: .top) { statusPills }
            .overlay {
                if isCelebrating {
                    CelebrationView()
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                AddItemBar { name in
                    withMotion(.pop, reduceMotion: reduceMotion) {
                        if store.addItem(named: name, to: list) != nil { addedTick += 1 }
                    }
                }
            }
    }

    private var listSwitcher: some View {
        ForEach(lists) { other in
            Button {
                onSelect(other)
            } label: {
                Label(other.name, systemImage: other.id == list.id ? "checkmark" : "list.bullet")
            }
        }
    }

    private func row(for item: ItemRecord) -> some View {
        ItemRow(item: item) { isChecked in
            store.setChecked(isChecked, for: item)
            if isChecked { checkedTick += 1 } else { uncheckedTick += 1 }
            if isChecked && !items.contains(where: { !$0.isChecked && $0.id != item.id }) {
                celebrate()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .listRowBackground(
            sync.recentlyChangedIDs.contains(item.id) ? Color.accentColor.opacity(0.15) : nil
        )
        .animation(.easeOut(duration: 0.8), value: sync.recentlyChangedIDs.contains(item.id))
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

    private func move(in rows: [ItemRecord], from source: IndexSet, to destination: Int) {
        guard let index = source.first else { return }
        var remaining = rows
        let item = remaining.remove(at: index)
        let insertAt = destination > index ? destination - 1 : destination
        let above = insertAt > 0 ? remaining[insertAt - 1] : nil
        let below = insertAt < remaining.count ? remaining[insertAt] : nil
        withMotion(.move, reduceMotion: reduceMotion) {
            store.move(item, between: above, and: below)
        }
        movedTick += 1
    }

    private func celebrate() {
        Task {
            try? await Task.sleep(for: checkSettleDelay)
            withMotion(.pop, reduceMotion: reduceMotion) { isCelebrating = true }
            AccessibilityNotification.Announcement(String(localized: "Everything's in the cart")).post()
            try? await Task.sleep(for: .seconds(1.6))
            withMotion(.move, reduceMotion: reduceMotion) { isCelebrating = false }
        }
    }

    @ViewBuilder
    private var statusPills: some View {
        VStack(spacing: 8) {
            if !network.isOnline {
                StatusPill(
                    text: String(localized: "Offline — changes will sync"),
                    systemImage: "wifi.slash",
                    tint: .orange
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let visibleActivity {
                StatusPill(text: visibleActivity.message, systemImage: visibleActivity.symbolName)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(visibleActivity.id)
            }
            if showsRejection {
                StatusPill(
                    text: String(localized: "A change couldn't be saved and was undone"),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 4)
        .animation(reduceMotion ? .reduced : .pop, value: network.isOnline)
        .allowsHitTesting(false)
    }

    private func showActivity() async {
        guard let event = sync.latestActivity else { return }
        withMotion(.pop, reduceMotion: reduceMotion) { visibleActivity = event }
        AccessibilityNotification.Announcement(event.message).post()
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        withMotion(.move, reduceMotion: reduceMotion) { visibleActivity = nil }
    }

    private func showRejection() async {
        guard sync.status.lastRejection != nil else { return }
        withMotion(.pop, reduceMotion: reduceMotion) { showsRejection = true }
        try? await Task.sleep(for: .seconds(3))
        withMotion(.move, reduceMotion: reduceMotion) { showsRejection = false }
    }

    @ToolbarContentBuilder
    private func toolbarContent(hasChecked: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu("People", systemImage: "person.2.fill") {
                Button("Share list", systemImage: "person.badge.plus") { onShow(.share) }
                Button("Join a list", systemImage: "door.left.hand.open") { onShow(.join(code: nil)) }
                Divider()
                Button("Settings", systemImage: "gearshape") { onShow(.settings) }
            }
        }
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
