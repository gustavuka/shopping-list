import { useLiveQuery } from 'dexie-react-hooks'
import { useEffect, useState, useSyncExternalStore } from 'react'
import { db } from '../data/db'
import { JoinSheet } from './JoinSheet'
import { ListView } from './ListView'
import { useSession } from './session'
import { SettingsSheet } from './SettingsSheet'
import { ShareSheet } from './ShareSheet'

export type SessionSheet = { kind: 'share' } | { kind: 'join'; code?: string } | { kind: 'settings' }

const selectedKey = 'selectedListID'

/** Signed-in shell: picks the current list, drives sync with the page lifecycle, handles join links. */
export function SessionRoot({ joinCode, onJoinHandled }: { joinCode?: string; onJoinHandled: () => void }) {
  const { store, sync } = useSession()
  const lists = useLiveQuery(async () =>
    (await db.lists.toArray()).filter((l) => !l.deleted_at).sort((a, b) => a.created_at.localeCompare(b.created_at)),
  )
  const [selectedId, setSelectedId] = useState(() => localStorage.getItem(selectedKey) ?? '')
  const [sheet, setSheet] = useState<SessionSheet>()
  const currentList = lists?.find((l) => l.id === selectedId) ?? lists?.[0]
  const hasPulled = useSyncExternalStore(sync.subscribe, () => sync.getState().lastSyncedAt !== undefined)

  function select(id: string) {
    setSelectedId(id)
    localStorage.setItem(selectedKey, id)
  }

  useEffect(() => {
    void sync.start()

    const onVisibility = () => {
      // Foreground: reconnect Realtime if the socket died, push, delta fetch. Background: flush.
      if (document.visibilityState === 'visible') void sync.start()
      else void sync.push()
    }
    const onOnline = () => sync.setOnline(true)
    const onOffline = () => sync.setOnline(false)
    document.addEventListener('visibilitychange', onVisibility)
    window.addEventListener('online', onOnline)
    window.addEventListener('offline', onOffline)
    return () => {
      document.removeEventListener('visibilitychange', onVisibility)
      window.removeEventListener('online', onOnline)
      window.removeEventListener('offline', onOffline)
    }
  }, [store, sync])

  // First launch in this browser: create "Groceries" only once a pull has succeeded, so a flaky
  // network can't hide the account's existing lists and leave a duplicate behind.
  useEffect(() => {
    if (hasPulled) void store.ensureDefaultList()
  }, [hasPulled, store])

  useEffect(() => {
    if (joinCode === undefined) return
    setSheet({ kind: 'join', code: joinCode || undefined })
    onJoinHandled()
  }, [joinCode, onJoinHandled])

  /** Switch to the joined list; drop our own list if it was an untouched empty default. */
  async function didJoin(listId: string) {
    setSheet(undefined)
    if (
      currentList &&
      currentList.id !== listId &&
      currentList.created_by === sync.userId &&
      (await store.activeItemCount(currentList.id)) === 0
    ) {
      await store.deleteList(currentList.id)
    }
    select(listId)
  }

  if (!lists) return null
  return (
    <>
      {currentList ? (
        <ListView list={currentList} lists={lists} onSelect={select} onShow={setSheet} />
      ) : (
        <div className="loading" aria-label="Loading" />
      )}
      {sheet?.kind === 'share' && currentList && <ShareSheet list={currentList} onClose={() => setSheet(undefined)} />}
      {sheet?.kind === 'join' && (
        <JoinSheet initialCode={sheet.code} onJoined={didJoin} onClose={() => setSheet(undefined)} />
      )}
      {sheet?.kind === 'settings' && <SettingsSheet onClose={() => setSheet(undefined)} />}
    </>
  )
}
