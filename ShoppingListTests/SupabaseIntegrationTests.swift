import Foundation
import Testing
@testable import ShoppingList

/// Two guest users against the local Supabase stack, through the app's real `AuthService` and
/// `SupabaseRemote`: rooms, passwords, live updates, names.
/// Opt-in: needs `supabase start`; run with `TEST_RUNNER_RUN_INTEGRATION=1 xcodebuild test …`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUN_INTEGRATION"] != nil))
struct SupabaseIntegrationTests {
    /// A fresh "phone": its own client with an in-memory session.
    private func phone() throws -> (auth: AuthService, remote: SupabaseRemote) {
        let config = try #require(AppConfig.current, "simulator build must point at the local stack")
        let client = AuthService.makeClient(url: config.supabaseURL, key: config.supabaseKey, persistSession: false)
        return (AuthService(client: client), SupabaseRemote(client: client))
    }

    private func guest(_ name: String) async throws -> (remote: SupabaseRemote, id: UUID) {
        let phone = try phone()
        let id = try await phone.auth.signInAsGuest(name: name)
        return (phone.remote, id)
    }

    private func newList(by user: UUID) -> ListDTO {
        ListDTO(id: UUID(), name: "Groceries", emoji: nil, inviteCode: nil, createdBy: user,
                createdAt: .now, updatedAt: .distantPast, deletedAt: nil)
    }

    private func newItem(_ name: String, in listID: UUID, by user: UUID) -> ItemDTO {
        ItemDTO(id: UUID(), listID: listID, name: name, quantity: nil, note: nil, category: "other",
                position: 0, isChecked: false, checkedBy: nil, checkedAt: nil, createdBy: user, updatedBy: user,
                createdAt: .now, updatedAt: .distantPast, deletedAt: nil)
    }

    @Test func twoGuestsShareARoom() async throws {
        let gus = try await guest("Gus")
        let ana = try await guest("Ana")

        let room = try #require(try await gus.remote.upsertLists([newList(by: gus.id)]).first)
        let code = try #require(room.inviteCode)
        #expect(!room.hasPassword)

        await #expect(throws: (any Error).self, "a room without a password can't be joined") {
            _ = try await ana.remote.joinList(inviteCode: code, password: "anything")
        }

        try await gus.remote.setListPassword(listID: room.id, password: "pao-de-queijo")

        await #expect(throws: JoinError.invalidCodeOrPassword, "a wrong password is refused like a wrong code") {
            _ = try await ana.remote.joinList(inviteCode: code, password: "wrong-one")
        }
        #expect(try await ana.remote.fetchLists().isEmpty, "not a member yet")

        let joined = try await ana.remote.joinList(inviteCode: code.lowercased(), password: "pao-de-queijo")
        #expect(joined.id == room.id)
        #expect(joined.hasPassword)

        // Live: Ana sees Gus's new item with the exact server timestamp (echo suppression relies on it).
        let stream = await ana.remote.changes(listIDs: [room.id])  // returns once the feed is live
        let collector = Task { () -> [ItemDTO] in
            var seen: [ItemDTO] = []
            for await change in stream {
                if case .item(let item) = change { seen.append(item) }
                if seen.contains(where: { $0.name == "Milk" }) { break }
            }
            return seen
        }
        let milk = try #require(try await gus.remote.upsertItems([newItem("Milk", in: room.id, by: gus.id)]).first)
        let timeout = Task {
            try await Task.sleep(for: .seconds(8))
            collector.cancel()
        }
        let seen = await collector.value
        timeout.cancel()
        #expect(seen.contains { $0.id == milk.id && $0.updatedAt == milk.updatedAt })

        let names = Dictionary(uniqueKeysWithValues: try await ana.remote.fetchProfiles().map { ($0.id, $0.displayName) })
        #expect(names[gus.id] == "Gus")
        #expect(names[ana.id] == "Ana")
    }

    @Test func guestUpgradesAndGetsRoomsBackOnAnotherPhone() async throws {
        let email = "it\(UUID().uuidString.prefix(8).lowercased())@example.com"

        // Phone 1: a guest makes a room, then saves the account.
        let first = try phone()
        let guestID = try await first.auth.signInAsGuest(name: "Gus")
        #expect(first.auth.isGuest)
        let room = try #require(try await first.remote.upsertLists([newList(by: guestID)]).first)
        try await first.auth.upgradeGuest(email: email, password: "secret123")
        #expect(!first.auth.isGuest)
        #expect(first.auth.email == email)
        #expect(first.auth.state == .signedIn(userID: guestID), "same user id after upgrading")

        // Phone 2: signing in brings back the same user and its rooms.
        let second = try phone()
        do {
            try await second.auth.signIn(email: email, password: "wrong-password")
            Issue.record("signed in with a wrong password")
        } catch {
            #expect(AuthService.message(for: error) == "Wrong email or password.")
        }
        try await second.auth.signIn(email: email, password: "secret123")
        #expect(second.auth.state == .signedIn(userID: guestID))
        #expect(try await second.remote.fetchLists().map(\.id).contains(room.id))

        // The email is taken now.
        let third = try phone()
        do {
            try await third.auth.createAccount(email: email, password: "secret123", name: "Copycat")
            Issue.record("created a duplicate account")
        } catch {
            #expect(AuthService.message(for: error).contains("already an account"))
        }
    }

    @Test func createAccountDirectly() async throws {
        let email = "it\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let phone = try phone()
        try await phone.auth.createAccount(email: email, password: "secret123", name: "Ana")
        guard case .signedIn(let id) = phone.auth.state else {
            Issue.record("not signed in")
            return
        }
        #expect(phone.auth.email == email)
        let names = try await phone.remote.fetchProfiles()
        #expect(names.first { $0.id == id }?.displayName == "Ana")
    }
}
