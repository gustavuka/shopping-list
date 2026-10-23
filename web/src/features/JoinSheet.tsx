import { useState, type FormEvent } from 'react'
import { JoinError } from '../data/remote'
import { haptic } from '../ui/haptics'
import { Sheet } from '../ui/Sheet'
import { useSession } from './session'

/** Join a room with its code + password (ADR 0007). Port of `JoinListView.swift`. */
export function JoinSheet({
  initialCode,
  onJoined,
  onClose,
}: {
  initialCode?: string
  onJoined: (listId: string) => void
  onClose: () => void
}) {
  const { sync } = useSession()
  const [code, setCode] = useState(initialCode ?? '')
  const [password, setPassword] = useState('')
  const [isWorking, setWorking] = useState(false)
  const [error, setError] = useState<string>()
  // 4, not 6: rooms created before the 6-character minimum keep their passwords.
  const canSubmit = code.trim().length === 6 && password.length >= 4 && !isWorking

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!canSubmit) return
    setWorking(true)
    setError(undefined)
    try {
      const listId = await sync.join(code, password)
      haptic('success')
      onJoined(listId)
    } catch (e) {
      setError(
        !(e instanceof JoinError)
          ? "Couldn't join. Check your connection and try again."
          : e.reason === 'throttled'
            ? 'Too many tries. Wait a few minutes and try again.'
            : 'Wrong code or password.',
      )
      haptic('error')
      setWorking(false)
    }
  }

  return (
    <Sheet title="Join a list" onClose={onClose}>
      <form className="form" onSubmit={submit}>
        <input
          className="field room-code-field"
          placeholder="ABC234"
          aria-label="List code"
          autoCapitalize="characters"
          autoComplete="off"
          maxLength={6}
          autoFocus={!initialCode}
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
        />
        <input
          className="field"
          placeholder="List password"
          aria-label="List password"
          autoCapitalize="none"
          autoComplete="off"
          autoFocus={!!initialCode}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        <button type="submit" className="button prominent" disabled={!canSubmit}>
          {isWorking ? '…' : 'Join'}
        </button>
        {error && (
          <p className="footnote error" role="alert">
            {error}
          </p>
        )}
      </form>
    </Sheet>
  )
}
