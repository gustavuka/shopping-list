import { useState, type FormEvent } from 'react'
import type { ListRow } from '../data/rows'
import { haptic } from '../ui/haptics'
import { Sheet } from '../ui/Sheet'
import { useSession } from './session'

/** Room code + password (ADR 0007). A password must be set before anyone can join. */
export function ShareSheet({ list, onClose }: { list: ListRow; onClose: () => void }) {
  const { sync } = useSession()
  const [password, setPassword] = useState('')
  const [isEditing, setEditing] = useState(!list.has_password)
  const [isWorking, setWorking] = useState(false)
  const [error, setError] = useState<string>()
  const [copied, setCopied] = useState(false)
  const link = list.invite_code ? `${location.origin}/?join=${list.invite_code}` : undefined

  async function savePassword(event: FormEvent) {
    event.preventDefault()
    if (password.length < 6 || isWorking) return
    setWorking(true)
    setError(undefined)
    try {
      await sync.setPassword(list.id, password)
      haptic('success')
      setEditing(false)
    } catch {
      setError("Couldn't save the password. Check your connection and try again.")
      haptic('error')
    } finally {
      setWorking(false)
    }
  }

  async function share() {
    if (!link || !list.invite_code) return
    const text = `Join my shopping list "${list.name}": code ${list.invite_code}. I'll tell you the password.`
    if (navigator.share) {
      await navigator.share({ title: list.name, text, url: link }).catch(() => {})
    } else {
      await navigator.clipboard.writeText(`${text}\n${link}`)
      setCopied(true)
    }
  }

  return (
    <Sheet title="Share this list" onClose={onClose}>
      <div className="form">
        <p className="secondary">Your partner joins with the room code and the password you choose.</p>
        <div className="room-code" aria-label={`Room code ${list.invite_code ?? 'not ready yet'}`}>
          {list.invite_code ?? <span className="secondary">Connecting…</span>}
        </div>

        {isEditing ? (
          <form className="form" onSubmit={savePassword}>
            <input
              className="field"
              type="text"
              placeholder="Room password (6+ characters)"
              autoComplete="off"
              autoCapitalize="none"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
            <button type="submit" className="button prominent" disabled={password.length < 6 || isWorking}>
              {isWorking ? '…' : list.has_password ? 'Change password' : 'Set password'}
            </button>
          </form>
        ) : (
          <>
            <button type="button" className="button prominent" disabled={!link} onClick={share}>
              {copied ? 'Copied!' : 'Share invite'}
            </button>
            <button type="button" className="link" onClick={() => setEditing(true)}>
              Change room password
            </button>
          </>
        )}
        {error && (
          <p className="footnote error" role="alert">
            {error}
          </p>
        )}
      </div>
    </Sheet>
  )
}
