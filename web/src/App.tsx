import { useEffect, useState, useSyncExternalStore } from 'react'
import { auth } from './data/auth'
import { db } from './data/db'
import { Remote } from './data/remote'
import { ListStore } from './data/store'
import { supabase } from './data/supabase'
import { SyncEngine } from './data/sync'
import { SessionContext, type Session } from './features/session'
import { SessionRoot } from './features/SessionRoot'
import { Welcome } from './features/Welcome'

/** `?join=CODE` (the web form of `shoppinglist://join/CODE`) pre-fills the join form. */
function takeJoinCode(): string | undefined {
  const url = new URL(location.href)
  const code = url.searchParams.get('join')
  if (code === null) return undefined
  history.replaceState(null, '', '/')
  return code.toUpperCase()
}

export function App() {
  const { userId } = useSyncExternalStore(auth.subscribe, auth.getState)
  const [pendingJoinCode, setPendingJoinCode] = useState(takeJoinCode)
  // Kept here so the name survives backing out of the join form to the welcome screen.
  const [welcomeName, setWelcomeName] = useState('')
  const [joinFromWelcome, setJoinFromWelcome] = useState(false)

  if (!userId) {
    return (
      <Welcome
        name={welcomeName}
        onNameChange={setWelcomeName}
        joinCode={pendingJoinCode}
        onStart={(joining) => {
          setJoinFromWelcome(joining)
          if (joining) setPendingJoinCode((c) => c ?? '')
        }}
      />
    )
  }
  return (
    <SignedIn
      key={userId}
      userId={userId}
      joinCode={pendingJoinCode}
      joinFromWelcome={joinFromWelcome}
      onJoinHandled={() => setPendingJoinCode(undefined)}
    />
  )
}

function SignedIn({
  userId,
  joinCode,
  joinFromWelcome,
  onJoinHandled,
}: {
  userId: string
  joinCode?: string
  joinFromWelcome: boolean
  onJoinHandled: () => void
}) {
  const [session, setSession] = useState<Session>()

  useEffect(() => {
    let cancelled = false
    const store = new ListStore(db, userId)
    const sync = new SyncEngine(db, new Remote(supabase), userId)
    store.onLocalChange = sync.kick
    void (async () => {
      // A different account on this browser starts clean (ADR 0008). One IndexedDB read; no network.
      const owner = (await db.meta.get('owner'))?.value
      if (owner && owner !== userId) await db.wipe()
      await db.meta.put({ key: 'owner', value: userId })
      if (!cancelled) setSession({ store, sync })
    })()
    return () => {
      cancelled = true
      sync.shutdown()
      setSession(undefined)
    }
  }, [userId])

  if (!session) return null
  return (
    <SessionContext.Provider value={session}>
      <SessionRoot joinCode={joinCode} joinFromWelcome={joinFromWelcome} onJoinHandled={onJoinHandled} />
    </SessionContext.Provider>
  )
}
