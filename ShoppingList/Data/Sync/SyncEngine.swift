import Foundation
import Observation
import OSLog
import SwiftData

/// Reconciles the local store with Supabase (docs/sync.md):
/// pushes the outbox, pulls deltas, applies Realtime events, and reports status + partner activity.
///
/// Runs on the main actor because it is the *only other writer* of the main `ModelContext`
/// (single context → no merge conflicts). All network I/O and JSON work happens inside
/// `RemoteSyncing`, off the main actor; what's left here is cheap bookkeeping on small batches.
@MainActor
@Observable
final class SyncEngine {
    struct Status: Equatable {
        var pendingCount = 0
        var lastSyncedAt: Date?
        var isSyncing = false
        /// Set when the server refused a change; the row was restored to the server's version.
        var lastRejection: Date?
    }

    private(set) var status = Status()
    /// Most recent change made by someone else, for the activity pill.
    private(set) var latestActivity: ActivityEvent?
    /// Rows changed by someone else in the last moment, for the row highlight.
    private(set) var recentlyChangedIDs: Set<UUID> = []
    private(set) var memberNames: [UUID: String] = [:]

    @ObservationIgnored let userID: UUID
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let remote: any RemoteSyncing
    @ObservationIgnored private let cursors: SyncCursors

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPush = false
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var subscribedListIDs: Set<UUID> = []
    @ObservationIgnored private var isShutDown = false

    init(context: ModelContext, remote: any RemoteSyncing, userID: UUID, cursors: SyncCursors? = nil) {
        self.context = context
        self.remote = remote
        self.userID = userID
        self.cursors = cursors ?? SyncCursors(userID: userID)
        refreshPendingCount()
    }

    // MARK: Lifecycle

    /// Push, then pull and (re)subscribe. Safe to call repeatedly; concurrent calls share one run.
    @discardableResult
    func start() -> Task<Void, Never> {
        if let syncTask { return syncTask }
        let task = Task {
            await syncNow()
            syncTask = nil
        }
        syncTask = task
        return task
    }

    /// Drops Realtime (iOS kills the socket in background anyway). Pending writes stay in the outbox.
    func stop() {
        realtimeTask?.cancel()
        realtimeTask = nil
        subscribedListIDs = []
        retryTask?.cancel()
        retryTask = nil
    }

    /// Ends this engine for good (sign-out): nothing it scheduled may run with the old account.
    func shutdown() {
        stop()
        debounceTask?.cancel()
        debounceTask = nil
        syncTask?.cancel()
        isShutDown = true
    }

    func syncNow() async {
        guard !isShutDown else { return }
        status.isSyncing = true
        defer { status.isSyncing = false }
        await push()
        await pull()
    }

    /// Called by `ListStore` after every local change. Debounced so rapid taps become one request.
    func kick() {
        refreshPendingCount()
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    // MARK: Joining

    /// Joins a room by code + password and pulls its items. Returns the joined list's id.
    func join(inviteCode: String, password: String) async throws -> UUID {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let list = try await remote.joinList(inviteCode: code, password: password)
        apply(lists: [list], removeMissing: false)
        await pull()
        return list.id
    }

    /// Sets (or changes) the room password. Pushes the list first so it exists on the server.
    func setPassword(_ password: String, for list: ListRecord) async throws {
        await push()
        try await remote.setListPassword(listID: list.id, password: password)
        list.hasPassword = true
        save()
    }

    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await remote.updateDisplayName(trimmed, userID: userID)
        memberNames[userID] = trimmed
    }

    // MARK: Push

    func push() async {
        guard !isShutDown else { return }
        if let pushTask {
            needsAnotherPush = true
            await pushTask.value
            return
        }
        let task = Task {
            repeat {
                needsAnotherPush = false
                await drainOutbox()
            } while needsAnotherPush
        }
        pushTask = task
        await task.value
        pushTask = nil
        refreshPendingCount()
    }

    private func drainOutbox() async {
        let entries = (try? context.fetch(FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.enqueuedAt)]))) ?? []
        guard !entries.isEmpty else { return }

        do {
            // Lists first: items reference them.
            try await pushLists(entries.filter { $0.entity == .list })
            try await pushItems(entries.filter { $0.entity == .item })
            retryAttempt = 0
        } catch {
            Logger.sync.notice("Push failed, will retry: \(error)")
            scheduleRetry()
        }
    }

    private struct Snapshot<DTO> {
        let entry: OutboxEntry
        let revision: Int
        let dto: DTO
    }

    private func snapshots<DTO: Decodable>(_ entries: [OutboxEntry], as type: DTO.Type) -> [Snapshot<DTO>] {
        entries.compactMap { entry in
            do {
                return Snapshot(entry: entry, revision: entry.revision, dto: try JSONDecoder.outbox.decode(type, from: entry.payload))
            } catch {
                Logger.sync.error("Dropping undecodable outbox entry \(entry.rowID): \(error)")
                context.delete(entry)
                return nil
            }
        }
    }

    private func pushItems(_ entries: [OutboxEntry]) async throws {
        let batch = snapshots(entries, as: ItemDTO.self)
        guard !batch.isEmpty else { return }
        do {
            let saved = try await remote.upsertItems(batch.map(\.dto))
            complete(batch, saved: Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { $1 })) { dto in
                self.item(id: dto.id)?.apply(dto)
            }
        } catch where remote.classify(error) == .rejected {
            if batch.count > 1 {
                // Isolate the bad row so one rejection doesn't block everything else.
                for one in batch where one.entry.modelContext != nil {
                    try await pushItems([one.entry])
                }
            } else {
                await reject(itemEntry: batch[0].entry)
            }
        }
    }

    private func pushLists(_ entries: [OutboxEntry]) async throws {
        let batch = snapshots(entries, as: ListDTO.self)
        guard !batch.isEmpty else { return }
        do {
            let saved = try await remote.upsertLists(batch.map(\.dto))
            complete(batch, saved: Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { $1 })) { dto in
                self.list(id: dto.id)?.apply(dto)
            }
        } catch where remote.classify(error) == .rejected {
            Logger.sync.error("List write rejected: \(error)")
            for one in batch where one.entry.modelContext != nil {
                context.delete(one.entry)
            }
            status.lastRejection = .now
            save()
        }
    }

    /// Retires entries whose revision didn't change while the request was in flight and adopts the
    /// server's version of those rows. Entries edited mid-flight stay queued for the next round.
    private func complete<DTO: Identifiable>(
        _ batch: [Snapshot<DTO>],
        saved: [UUID: DTO],
        apply: (DTO) -> Void
    ) where DTO.ID == UUID {
        for snapshot in batch {
            // Entry may have vanished (sign-out wipe) while we were awaiting the network.
            guard snapshot.entry.modelContext != nil else { continue }
            if snapshot.entry.revision == snapshot.revision {
                context.delete(snapshot.entry)
                if let server = saved[snapshot.dto.id] {
                    apply(server)
                }
            } else {
                needsAnotherPush = true
            }
        }
        save()
    }

    private func reject(itemEntry entry: OutboxEntry) async {
        let rowID = entry.rowID
        Logger.sync.error("Item write rejected for \(rowID); restoring server version")
        context.delete(entry)
        status.lastRejection = .now
        let local = item(id: rowID)
        do {
            if let server = try await remote.fetchItems(ids: [rowID]).first {
                local?.apply(server)
            } else if let local {
                context.delete(local)  // never made it to the server and never will
            }
        } catch {
            local?.hasPendingChanges = false
        }
        save()
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryAttempt += 1
        let delay = min(60, 1 << min(retryAttempt - 1, 6))  // 1, 2, 4 … 60 s
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            retryTask = nil
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    // MARK: Pull

    func pull() async {
        do {
            let lists = try await remote.fetchLists()
            apply(lists: lists, removeMissing: true)

            let activeIDs = Set(lists.filter { $0.deletedAt == nil }.map(\.id))
            await subscribe(to: activeIDs)  // before fetching items, so nothing falls in the gap

            for listID in activeIDs {
                let items = try await remote.fetchItems(listID: listID, updatedAfter: cursors[listID])
                apply(items: items, live: false)
                if let newest = items.map(\.updatedAt).max() {
                    cursors[listID] = newest
                }
            }

            let profiles = try await remote.fetchProfiles()
            memberNames = Dictionary(profiles.map { ($0.id, $0.displayName) }, uniquingKeysWith: { $1 })
            status.lastSyncedAt = .now
        } catch {
            Logger.sync.notice("Pull failed: \(error)")
        }
    }

    // MARK: Realtime

    private func subscribe(to listIDs: Set<UUID>) async {
        guard listIDs != subscribedListIDs || realtimeTask == nil else { return }
        realtimeTask?.cancel()
        subscribedListIDs = listIDs
        guard !listIDs.isEmpty else {
            realtimeTask = nil
            return
        }
        let stream = await remote.changes(listIDs: Array(listIDs))
        realtimeTask = Task { [weak self] in
            for await change in stream {
                guard let self else { return }
                switch change {
                case .item(let dto):
                    // Cursors only advance on delta fetches: if an event were ever dropped, the next
                    // fetch still covers it. Re-applying already-seen rows is a cheap no-op.
                    apply(items: [dto], live: true)
                case .list(let dto):
                    apply(lists: [dto], removeMissing: false)
                }
            }
        }
    }

    // MARK: Applying remote rows

    private func apply(items: [ItemDTO], live: Bool) {
        guard !items.isEmpty else { return }
        for dto in items {
            let local = item(id: dto.id)
            let decision = ConflictResolver.decide(
                local: local.map { .init(updatedAt: $0.updatedAt, hasPendingChanges: $0.hasPendingChanges) },
                remoteUpdatedAt: dto.updatedAt
            )
            let wasChecked = local?.isChecked
            switch decision {
            case .insert: context.insert(ItemRecord(dto))
            case .overwrite: local?.apply(dto)
            case .skip: continue
            }
            if live && dto.updatedBy != userID {
                noteActivity(dto, isNew: decision == .insert, wasChecked: wasChecked)
            }
        }
        save()
    }

    private func apply(lists: [ListDTO], removeMissing: Bool) {
        for dto in lists {
            let local = list(id: dto.id)
            let decision = ConflictResolver.decide(
                local: local.map { .init(updatedAt: $0.updatedAt, hasPendingChanges: $0.hasPendingChanges) },
                remoteUpdatedAt: dto.updatedAt
            )
            switch decision {
            case .insert: context.insert(ListRecord(dto))
            case .overwrite: local?.apply(dto)
            case .skip:
                // Server-maintained fields aren't part of conflict resolution: adopt them whenever we learn them.
                if local?.inviteCode == nil { local?.inviteCode = dto.inviteCode }
                if dto.hasPassword { local?.hasPassword = true }
            }
        }

        if removeMissing {
            // Lists we synced before but can no longer see (left, or removed) disappear locally.
            let serverIDs = Set(lists.map(\.id))
            let gone = ((try? context.fetch(FetchDescriptor<ListRecord>())) ?? []).filter {
                !serverIDs.contains($0.id) && !$0.hasPendingChanges && $0.updatedAt != .distantPast
            }
            for list in gone {
                let listID = list.id
                try? context.delete(model: ItemRecord.self, where: #Predicate { $0.listID == listID })
                context.delete(list)
                cursors[listID] = nil
            }
        }
        save()
    }

    private func noteActivity(_ dto: ItemDTO, isNew: Bool, wasChecked: Bool?) {
        let verb: ActivityEvent.Verb =
            if dto.deletedAt != nil { .removed }
            else if isNew { .added }
            else if wasChecked == false && dto.isChecked { .checked }
            else if wasChecked == true && !dto.isChecked { .unchecked }
            else { .edited }

        var event = ActivityEvent(
            actorID: dto.updatedBy,
            actorName: memberNames[dto.updatedBy] ?? String(localized: "Your partner"),
            verb: verb,
            itemNames: [dto.name],
            date: .now
        )
        if let latest = latestActivity, latest.canMerge(event) {
            event.itemNames = latest.itemNames + [dto.name]
        }
        latestActivity = event

        let id = dto.id
        recentlyChangedIDs.insert(id)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            recentlyChangedIDs.remove(id)
        }
    }

    // MARK: Helpers

    private func item(id: UUID) -> ItemRecord? {
        var descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func list(id: UUID) -> ListRecord? {
        var descriptor = FetchDescriptor<ListRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func refreshPendingCount() {
        status.pendingCount = (try? context.fetchCount(FetchDescriptor<OutboxEntry>())) ?? 0
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Logger.sync.error("Save failed: \(error)")
        }
    }
}
