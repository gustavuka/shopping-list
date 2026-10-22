import { useLayoutEffect, useRef, type RefObject } from 'react'

/** Spring-ish curves standing in for `Animation.check / .move / .pop` (docs/design-system.md#motion). */
export const easing = {
  move: 'cubic-bezier(0.32, 0.72, 0, 1)',
  pop: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
}

export function prefersReducedMotion(): boolean {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/**
 * FLIP: after every render, rows marked `data-flip="<id>"` glide from where they were to where
 * they are now (checked items moving into "In cart"), and new rows pop in. Reduce Motion: fades only.
 */
export function useFlip(container: RefObject<HTMLElement | null>): void {
  const previous = useRef(new Map<string, number>())
  const hasRows = useRef(false)

  useLayoutEffect(() => {
    const root = container.current
    if (!root) return
    const reduce = prefersReducedMotion()
    const isFirstLayout = !hasRows.current
    const origin = root.getBoundingClientRect().top
    const next = new Map<string, number>()

    for (const el of root.querySelectorAll<HTMLElement>('[data-flip]')) {
      const id = el.dataset.flip!
      const top = el.getBoundingClientRect().top - origin
      next.set(id, top)
      const before = previous.current.get(id)
      if (before === undefined) {
        if (isFirstLayout) continue
        el.animate(
          reduce
            ? [{ opacity: 0 }, { opacity: 1 }]
            : [{ opacity: 0, transform: 'translateY(-12px) scale(0.96)' }, { opacity: 1, transform: 'none' }],
          { duration: reduce ? 200 : 400, easing: easing.pop },
        )
      } else if (before !== top) {
        el.animate(
          reduce
            ? [{ opacity: 0.4 }, { opacity: 1 }]
            : [{ transform: `translateY(${before - top}px)` }, { transform: 'none' }],
          { duration: 350, easing: easing.move },
        )
      }
    }
    previous.current = next
    if (next.size) hasRows.current = true
  })
}
