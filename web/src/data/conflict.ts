/**
 * Row-level last-write-wins by server `updated_at`, protecting pending local edits.
 * Port of `Data/Sync/ConflictResolver.swift` (docs/sync.md#conflict-resolution).
 */
export type Decision = 'insert' | 'overwrite' | 'skip'

export function decide(local: { serverUs: number; pending: boolean } | undefined, remoteUs: number): Decision {
  if (!local) return 'insert'
  if (local.pending) return 'skip' // our pending write will land later and win
  // Equal timestamps mean we already have this exact version (typically our own write echoing back).
  return remoteUs > local.serverUs ? 'overwrite' : 'skip'
}
