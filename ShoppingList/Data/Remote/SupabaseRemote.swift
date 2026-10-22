import Foundation
import OSLog
import Supabase

/// `RemoteSyncing` backed by Supabase (PostgREST + Realtime). Stateless apart from the client.
final class SupabaseRemote: RemoteSyncing {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: Writes

    func upsertLists(_ lists: [ListDTO]) async throws -> [ListDTO] {
        // One request per list: lists without a known invite_code omit that key, and a bulk upsert
        // needs every object to have the same keys. Lists are few, so this costs nothing.
        var result: [ListDTO] = []
        for list in lists {
            let rows: [ListDTO] = try await client.from("lists").upsert(list, onConflict: "id").execute().value
            result += rows
        }
        return result
    }

    func upsertItems(_ items: [ItemDTO]) async throws -> [ItemDTO] {
        guard !items.isEmpty else { return [] }
        return try await client.from("items").upsert(items, onConflict: "id").execute().value
    }

    func updateDisplayName(_ name: String, userID: UUID) async throws {
        try await client.from("profiles")
            .update(["display_name": name], returning: .minimal)
            .eq("id", value: userID)
            .execute()
    }

    func joinList(inviteCode: String, password: String) async throws -> ListDTO {
        try await client.rpc("join_list", params: ["p_invite_code": inviteCode, "p_password": password]).execute().value
    }

    func setListPassword(listID: UUID, password: String) async throws {
        try await client.rpc(
            "set_list_password",
            params: ["p_list_id": listID.uuidString, "p_password": password]
        ).execute()
    }

    // MARK: Reads

    func fetchLists() async throws -> [ListDTO] {
        try await client.from("lists").select().execute().value
    }

    func fetchItems(listID: UUID, updatedAfter: Date?) async throws -> [ItemDTO] {
        var query = client.from("items").select().eq("list_id", value: listID)
        if let updatedAfter {
            query = query.gt("updated_at", value: updatedAfter)
        }
        return try await query.order("updated_at").execute().value
    }

    func fetchItems(ids: [UUID]) async throws -> [ItemDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("items").select().in("id", values: ids).execute().value
    }

    func fetchProfiles() async throws -> [ProfileDTO] {
        try await client.from("profiles").select("id, display_name").execute().value
    }

    // MARK: Realtime

    /// Returns once each list's database-change feed is confirmed live (or after a timeout).
    func changes(listIDs: [UUID]) async -> AsyncStream<RemoteChange> {
        let (stream, continuation) = AsyncStream<RemoteChange>.makeStream(bufferingPolicy: .unbounded)
        var channels: [RealtimeChannelV2] = []
        var tasks: [Task<Void, Never>] = []

        for listID in listIDs {
            // Unique suffix: a previous channel for the same list may still be tearing down.
            let channel = client.channel("list-\(listID.uuidString)-\(UUID().uuidString.prefix(8))")
            let itemChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "items", filter: .eq("list_id", value: listID)
            )
            let listChanges = channel.postgresChange(
                UpdateAction.self, schema: "public", table: "lists", filter: .eq("id", value: listID)
            )
            let systemMessages = channel.system()
            if await Self.subscribe(channel, listID: listID),
               await !Self.waitForDatabaseFeed(systemMessages) {
                Logger.sync.notice("Realtime feed for \(listID) not confirmed live; the next fetch covers any gap")
            }
            channels.append(channel)

            tasks.append(Task {
                for await action in itemChanges {
                    if let dto = Self.decode(ItemDTO.self, from: action) {
                        continuation.yield(.item(dto))
                    }
                }
            })
            tasks.append(Task {
                for await action in listChanges {
                    do {
                        continuation.yield(.list(try action.decodeRecord(as: ListDTO.self, decoder: AnyJSON.decoder)))
                    } catch {
                        Logger.sync.error("Undecodable list change: \(error)")
                    }
                }
            })
        }

        let client = client
        let ownedChannels = channels
        let ownedTasks = tasks
        continuation.onTermination = { _ in
            ownedTasks.forEach { $0.cancel() }
            Task {
                for channel in ownedChannels {
                    await client.removeChannel(channel)
                }
            }
        }
        return stream
    }

    /// Retries with backoff: a cold Realtime server (e.g. right after `supabase start`) can reject
    /// the first join. If all attempts fail, the next foreground resubscribes.
    private static func subscribe(_ channel: RealtimeChannelV2, listID: UUID) async -> Bool {
        for attempt in 1...3 {
            do {
                try await channel.subscribeWithError()
                return true
            } catch {
                Logger.sync.error("Realtime subscribe attempt \(attempt) failed for \(listID): \(error)")
                try? await Task.sleep(for: .seconds(attempt))
            }
        }
        return false
    }

    /// The channel reports "subscribed" before its database-change feed is live; Realtime confirms the
    /// feed with a system message ("Subscribed to PostgreSQL"). Waiting for it is what makes
    /// "subscribe, then fetch" gap-free. Gives up after `timeout` (the next delta fetch covers it).
    private static func waitForDatabaseFeed(
        _ messages: AsyncStream<RealtimeMessageV2>,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await message in messages where message.payload["extension"]?.stringValue == "postgres_changes" {
                    return message.payload["status"]?.stringValue == "ok"
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let isLive = await group.next() ?? false
            group.cancelAll()
            return isLive
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from action: AnyAction) -> T? {
        do {
            switch action {
            case .insert(let insert): return try insert.decodeRecord(as: T.self, decoder: AnyJSON.decoder)
            case .update(let update): return try update.decodeRecord(as: T.self, decoder: AnyJSON.decoder)
            case .delete: return nil  // we only soft-delete; hard deletes are tombstone purges
            }
        } catch {
            Logger.sync.error("Undecodable item change: \(error)")
            return nil
        }
    }

    // MARK: Errors

    func classify(_ error: any Error) -> RemoteFailure {
        if let error = error as? PostgrestError, let code = error.code {
            // Postgres SQLSTATE classes: 22 data exception, 23 integrity, 42 privilege/syntax, P0 raised.
            // PGRST* codes (e.g. expired JWT) are transient.
            let rejectedClasses = ["22", "23", "42", "P0"]
            return rejectedClasses.contains(where: code.hasPrefix) ? .rejected : .transient
        }
        return .transient
    }
}
