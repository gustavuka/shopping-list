/** "Ana added Eggs" — a live change made by someone else (docs/design-system.md#partner-activity). */
export type ActivityVerb = 'added' | 'checked' | 'unchecked' | 'edited' | 'removed'

export interface ActivityEvent {
  id: string
  actorId: string
  actorName: string
  verb: ActivityVerb
  itemNames: string[]
  date: number
}

export function activityMessage(e: ActivityEvent): string {
  const subject = e.itemNames.length === 1 ? e.itemNames[0] : `${e.itemNames.length} items`
  const verb = { added: 'added', checked: 'got', unchecked: 'put back', edited: 'edited', removed: 'removed' }[e.verb]
  return `${e.actorName} ${verb} ${subject}`
}

/** Consecutive events of the same kind from the same person within a few seconds merge. */
export function canMerge(previous: ActivityEvent, next: ActivityEvent): boolean {
  return previous.actorId === next.actorId && previous.verb === next.verb && next.date - previous.date < 3000
}
