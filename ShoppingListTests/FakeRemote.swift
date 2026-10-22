import Foundation
@testable import ShoppingList

/// Thrown for writes the fake server refuses (the analogue of an RLS violation).
struct FakeRejection: Error {}

/// In-memory stand-in for Supabase that mimics the server rules that matter to sync:
/// server-set `updated_at` (monotonic fake clock) and immutable `created_by`.
actor FakeRemote: RemoteSyncing {
    private(set) var lists: [UUID: ListDTO] = [:]
    private(set) var items: [UUID: ItemDTO] = [:]
    private(set) var upsertCalls = 0
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var rejectedItemIDs: Set<UUID> = []
    private var liveContinuation: AsyncStream<RemoteChange>.Continuation?
    /// Runs inside `upsertItems` before the write lands — lets a test edit locally "mid-flight".
    private var beforeItemUpsert: (@Sendable () async -> Void)?

    let me: UUID

    init(me: UUID) {
        self.me = me
    }

    // MARK: Test controls

    func reject(itemID: UUID) { rejectedItemIDs.insert(itemID) }
    func setBeforeItemUpsert(_ hook: (@Sendable () async -> Void)?) { beforeItemUpsert = hook }

    /// A write by someone else, landing on the server (and broadcast live if subscribed).
    @discardableResult
    func partnerWrites(_ item: ItemDTO, partner: UUID, live: Bool = true) -> ItemDTO {
        var row = item
        row.createdBy = items[item.id]?.createdBy ?? partner
        row.updatedBy = partner
        row.updatedAt = tick()
        items[row.id] = row
        if live { liveContinuation?.yield(.item(row)) }
        return row
    }

    func removeList(_ id: UUID) { lists[id] = nil }

    // MARK: RemoteSyncing

    func upsertLists(_ incoming: [ListDTO]) async throws -> [ListDTO] {
        incoming.map { dto in
            var row = dto
            row.createdBy = lists[dto.id]?.createdBy ?? me
            row.inviteCode = lists[dto.id]?.inviteCode ?? "ABC234"
            row.updatedAt = tick()
            lists[row.id] = row
            return row
        }
    }

    func upsertItems(_ incoming: [ItemDTO]) async throws -> [ItemDTO] {
        upsertCalls += 1
        await beforeItemUpsert?()
        if incoming.contains(where: { rejectedItemIDs.contains($0.id) }) {
            throw FakeRejection()
        }
        return incoming.map { dto in
            var row = dto
            row.createdBy = items[dto.id]?.createdBy ?? me
            row.updatedBy = me
            row.updatedAt = tick()
            items[row.id] = row
            return row
        }
    }

    func fetchLists() async throws -> [ListDTO] { Array(lists.values) }

    func fetchItems(listID: UUID, updatedAfter: Date?) async throws -> [ItemDTO] {
        items.values
            .filter { $0.listID == listID && $0.updatedAt > (updatedAfter ?? .distantPast) }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    func fetchItems(ids: [UUID]) async throws -> [ItemDTO] { ids.compactMap { items[$0] } }

    func fetchProfiles() async throws -> [ProfileDTO] { [ProfileDTO(id: me, displayName: "Me")] }

    func updateDisplayName(_ name: String, userID: UUID) async throws {}

    private var passwords: [UUID: String] = [:]

    func joinList(inviteCode: String, password: String) async throws -> ListDTO {
        guard let list = lists.values.first(where: { $0.inviteCode == inviteCode }),
              passwords[list.id] == password else {
            throw FakeRejection()
        }
        return list
    }

    func setListPassword(listID: UUID, password: String) async throws {
        guard password.count >= 4 else { throw FakeRejection() }
        passwords[listID] = password
        lists[listID]?.hasPassword = true
        lists[listID]?.updatedAt = tick()
    }

    func changes(listIDs: [UUID]) async -> AsyncStream<RemoteChange> {
        let (stream, continuation) = AsyncStream<RemoteChange>.makeStream()
        liveContinuation = continuation
        return stream
    }

    nonisolated func classify(_ error: any Error) -> RemoteFailure {
        error is FakeRejection ? .rejected : .transient
    }

    private func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }
}
