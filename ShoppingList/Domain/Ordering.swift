import Foundation

/// Fractional ordering for `position` (see docs/sync.md#ordering).
enum Ordering {
    /// Gap below which positions should be renormalized to avoid running out of floating-point precision.
    static let minimumGap = 1e-9

    /// New items go above everything else.
    static func positionAtTop(of positions: some Sequence<Double>) -> Double {
        (positions.min() ?? 1) - 1
    }

    /// Position for an item dropped between `above` and `below` (either may be nil at the list edges).
    static func position(between above: Double?, and below: Double?) -> Double {
        switch (above, below) {
        case let (above?, below?): (above + below) / 2
        case let (above?, nil): above + 1
        case let (nil, below?): below - 1
        case (nil, nil): 0
        }
    }

    static func needsRenormalization(_ sortedPositions: [Double]) -> Bool {
        zip(sortedPositions, sortedPositions.dropFirst()).contains { $1 - $0 < minimumGap }
    }

    /// Evenly spaced positions 0, 1, 2… for `count` items, preserving their order.
    static func renormalized(count: Int) -> [Double] {
        (0..<count).map(Double.init)
    }
}
