import { createContext, useContext, useSyncExternalStore } from 'react'
import type { ListStore } from '../data/store'
import type { SyncEngine, SyncState } from '../data/sync'

/** Per-user services; exist only while signed in (like `AppModel.Session` on iOS). */
export interface Session {
  store: ListStore
  sync: SyncEngine
}

export const SessionContext = createContext<Session | null>(null)

export function useSession(): Session {
  const session = useContext(SessionContext)
  if (!session) throw new Error('useSession outside a signed-in session')
  return session
}

export function useSyncState(): SyncState {
  const { sync } = useSession()
  return useSyncExternalStore(sync.subscribe, sync.getState)
}
