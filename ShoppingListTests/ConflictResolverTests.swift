import Foundation
import Testing
@testable import ShoppingList

struct ConflictResolverTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)

    @Test func unknownRowIsInserted() {
        #expect(ConflictResolver.decide(local: nil, remoteUpdatedAt: t0) == .insert)
    }

    @Test func newerRemoteOverwrites() {
        #expect(ConflictResolver.decide(local: .init(updatedAt: t0, hasPendingChanges: false), remoteUpdatedAt: t1) == .overwrite)
    }

    @Test func pendingLocalEditIsProtected() {
        #expect(ConflictResolver.decide(local: .init(updatedAt: t0, hasPendingChanges: true), remoteUpdatedAt: t1) == .skip)
    }

    @Test func staleEventIsSkipped() {
        #expect(ConflictResolver.decide(local: .init(updatedAt: t1, hasPendingChanges: false), remoteUpdatedAt: t0) == .skip)
    }

    @Test func ownEchoIsSkipped() {
        #expect(ConflictResolver.decide(local: .init(updatedAt: t1, hasPendingChanges: false), remoteUpdatedAt: t1) == .skip)
    }
}

struct DeepLinkTests {
    @Test func parsesJoinLinks() throws {
        #expect(DeepLink(url: try #require(URL(string: "shoppinglist://join/abc234"))) == .join(code: "ABC234"))
        #expect(DeepLink(url: try #require(URL(string: "shoppinglist://join/"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "https://example.com/join/ABC234"))) == nil)
    }

    @Test func roundTrips() {
        #expect(DeepLink(url: DeepLink.joinURL(code: "XYZ789")) == .join(code: "XYZ789"))
    }
}

struct ActivityEventTests {
    @Test func mergesRapidEventsFromSamePerson() {
        let ana = UUID()
        let first = ActivityEvent(actorID: ana, actorName: "Ana", verb: .added, itemNames: ["Milk"], date: .now)
        let second = ActivityEvent(actorID: ana, actorName: "Ana", verb: .added, itemNames: ["Eggs"], date: .now)
        let different = ActivityEvent(actorID: ana, actorName: "Ana", verb: .checked, itemNames: ["Eggs"], date: .now)
        #expect(first.canMerge(second))
        #expect(!first.canMerge(different))
    }

    @Test func messageSummarizesMultipleItems() {
        let event = ActivityEvent(actorID: UUID(), actorName: "Ana", verb: .added, itemNames: ["Milk", "Eggs", "Tea"], date: .now)
        #expect(event.message == "Ana added 3 items")
    }
}
