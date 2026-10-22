import Foundation

/// Everything `SyncEngine` needs from the backend. `SupabaseRemote` is the real one;
/// tests and previews use fakes. Implementations run off the main actor.
protocol RemoteSyncing: Sendable {
    func upsertLists(_ lists: [ListDTO]) async throws -> [ListDTO]
    func upsertItems(_ items: [ItemDTO]) async throws -> [ItemDTO]
    /// All lists the user is a member of, including soft-deleted ones (tombstones).
    func fetchLists() async throws -> [ListDTO]
    func fetchItems(listID: UUID, updatedAfter: Date?) async throws -> [ItemDTO]
    func fetchItems(ids: [UUID]) async throws -> [ItemDTO]
    /// Own profile plus everyone sharing a list with the user.
    func fetchProfiles() async throws -> [ProfileDTO]
    func updateDisplayName(_ name: String, userID: UUID) async throws
    /// Joins a room. Throws `JoinError` when refused; wrong code and wrong password fail the same way.
    func joinList(inviteCode: String, password: String) async throws -> ListDTO
    func setListPassword(listID: UUID, password: String) async throws
    /// Live changes for the given lists. Returns once subscribed, so a fetch issued afterwards
    /// can't miss an event. Cancel by dropping/terminating the stream.
    func changes(listIDs: [UUID]) async -> AsyncStream<RemoteChange>
    /// Whether a failed write should be retried or given up on.
    func classify(_ error: any Error) -> RemoteFailure
}

enum RemoteChange: Sendable {
    case item(ItemDTO)
    case list(ListDTO)
}

struct ProfileDTO: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// `join_list` refused the join.
enum JoinError: Error, Equatable {
    /// No room with this code and password (indistinguishable on purpose).
    case invalidCodeOrPassword
    /// Too many failed tries from this user or against this room; wait and retry.
    case tooManyAttempts
}

enum RemoteFailure {
    /// The server understood and refused the write (RLS, constraint, bad data). Retrying won't help.
    case rejected
    /// Network, timeout, 5xx, expired token… Retry with backoff.
    case transient
}
