/** Fractional ordering for `position` (docs/sync.md#ordering). Port of `Domain/Ordering.swift`. */

/** New items go above everything else. */
export function positionAtTop(positions: number[]): number {
  return positions.length ? Math.min(...positions) - 1 : 0
}
