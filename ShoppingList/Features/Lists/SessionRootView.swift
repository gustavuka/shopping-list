import SwiftData
import SwiftUI
import UIKit

enum SessionSheet: Identifiable, Equatable {
    case share
    case join(code: String?)
    case settings

    var id: String {
        switch self {
        case .share: "share"
        case .join: "join"
        case .settings: "settings"
        }
    }
}

/// Signed-in shell: picks the current list, drives sync with the app lifecycle, handles deep links.
struct SessionRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ListStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<ListRecord> { $0.deletedAt == nil }, sort: \ListRecord.createdAt)
    private var lists: [ListRecord]
    @AppStorage("selectedListID") private var selectedListID = ""
    @State private var sheet: SessionSheet?

    private var currentList: ListRecord? {
        lists.first { $0.id.uuidString == selectedListID } ?? lists.first
    }

    var body: some View {
        NavigationStack {
            if let list = currentList {
                ShoppingListView(
                    list: list,
                    lists: lists,
                    onSelect: { selectedListID = $0.id.uuidString },
                    onShow: { sheet = $0 }
                )
            } else {
                // First launch on this device: fetch existing lists before creating a new one.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .task { sync.start() }
        // First launch on this device: create "Groceries" only once a pull has succeeded, so a flaky
        // network can't hide the account's existing lists and leave a duplicate behind.
        .onChange(of: sync.status.lastSyncedAt != nil, initial: true) { _, hasPulled in
            if hasPulled { store.ensureDefaultList() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: sync.start()
            case .background:
                sync.stop()
                flushInBackground()
            default: break
            }
        }
        .onChange(of: model.pendingJoinCode, initial: true) { _, code in
            guard let code else { return }
            sheet = .join(code: code.isEmpty ? nil : code)
            model.pendingJoinCode = nil
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .share:
                if let list = currentList { ShareRoomSheet(list: list) }
            case .join(let code):
                JoinListView(initialCode: code) { didJoin(listID: $0) }
            case .settings:
                SettingsView()
            }
        }
    }

    /// Asks iOS for a few seconds to push anything still in the outbox before suspension.
    private func flushInBackground() {
        guard sync.status.pendingCount > 0 else { return }
        let token = BackgroundTaskToken()
        token.id = UIApplication.shared.beginBackgroundTask(withName: "FlushOutbox") { token.end() }
        Task {
            await sync.push()
            token.end()
        }
    }

    /// Switch to the joined list; drop our own list if it was an untouched empty default.
    private func didJoin(listID: UUID) {
        if let current = currentList,
           current.id != listID,
           current.createdBy == sync.userID,
           store.activeItemCount(in: current.id) == 0 {
            store.deleteList(current)
        }
        selectedListID = listID.uuidString
    }
}

@MainActor
private final class BackgroundTaskToken {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
