import Testing
@testable import ShoppingList

struct OrderingTests {
    @Test func topOfEmptyListIsZero() {
        #expect(Ordering.positionAtTop(of: []) == 0)
    }

    @Test func topIsAboveEverything() {
        #expect(Ordering.positionAtTop(of: [3, -2, 5]) == -3)
    }

    @Test func betweenIsMidpoint() {
        #expect(Ordering.position(between: 1, and: 2) == 1.5)
        #expect(Ordering.position(between: 4, and: nil) == 5)
        #expect(Ordering.position(between: nil, and: 4) == 3)
        #expect(Ordering.position(between: nil, and: nil) == 0)
    }

    @Test func detectsCollapsedGaps() {
        #expect(!Ordering.needsRenormalization([0, 1, 2]))
        #expect(Ordering.needsRenormalization([0, 1, 1 + 1e-12]))
    }

    @Test func repeatedMidpointsEventuallyNeedRenormalization() {
        var above = 0.0
        let below = 1.0
        var steps = 0
        while !Ordering.needsRenormalization([above, below]) {
            above = Ordering.position(between: above, and: below)
            steps += 1
        }
        #expect(steps > 20)
        #expect(Ordering.renormalized(count: 3) == [0, 1, 2])
    }
}
