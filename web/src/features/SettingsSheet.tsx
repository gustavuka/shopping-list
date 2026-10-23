import { useState, useSyncExternalStore, type FormEvent } from 'react'
import { auth } from '../data/auth'
import { haptic } from '../ui/haptics'
import { Sheet } from '../ui/Sheet'
import { AccountForm, type AccountMode } from './AccountForm'
import { useSession, useSyncState } from './session'

/** Name, account, sign out. Port of `SettingsView.swift`. */
export function SettingsSheet({ onClose }: { onClose: () => void }) {
  const { sync } = useSession()
  const { memberNames, pendingCount } = useSyncState()
  const { email } = useSyncExternalStore(auth.subscribe, auth.getState)
  const [name, setName] = useState(memberNames.get(sync.userId) ?? '')
  const [accountMode, setAccountMode] = useState<AccountMode>()
  const [nameError, setNameError] = useState<string>()

  async function saveName(event: FormEvent) {
    event.preventDefault()
    try {
      await sync.updateDisplayName(name)
      haptic('success')
    } catch {
      setNameError("Couldn't save your name. Check your connection.")
    }
  }

  async function signOut() {
    const warnings = [
      pendingCount > 0 && `${pendingCount} change(s) haven't synced yet and will be lost.`,
      !email && "You're a guest: to come back, you'll rejoin your lists with their code + password.",
    ].filter(Boolean)
    if (warnings.length && !confirm(`${warnings.join('\n')}\n\nSign out anyway?`)) return
    await auth.signOut()
  }

  if (accountMode) {
    return (
      <Sheet title="Account" onClose={onClose}>
        <AccountForm mode={accountMode} onCancel={() => setAccountMode(undefined)} onDone={() => setAccountMode(undefined)} />
      </Sheet>
    )
  }

  return (
    <Sheet title="Settings" onClose={onClose}>
      <form className="form" onSubmit={saveName}>
        <label className="footnote secondary" htmlFor="display-name">
          Your name (your partner sees it)
        </label>
        <div className="inline">
          <input id="display-name" className="field" maxLength={50} value={name} onChange={(e) => setName(e.target.value)} />
          <button type="submit" className="button" disabled={!name.trim()}>
            Save
          </button>
        </div>
        {nameError && <p className="footnote error">{nameError}</p>}
      </form>

      <div className="form">
        <p className="footnote secondary">{email ? `Signed in as ${email}` : 'Guest on this device'}</p>
        {!email && (
          <button type="button" className="button" onClick={() => setAccountMode('upgrade')}>
            Save as account
          </button>
        )}
        <button type="button" className="button destructive" onClick={signOut}>
          Sign out
        </button>
      </div>
    </Sheet>
  )
}
