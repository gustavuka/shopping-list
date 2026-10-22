import { useState, type FormEvent } from 'react'
import { auth } from '../data/auth'
import { useCaptcha } from '../ui/Captcha'
import { haptic } from '../ui/haptics'
import { AccountForm, type AccountMode } from './AccountForm'

/**
 * First launch. Fastest path: a name → guest user → new list or join a room (ADR 0007).
 * Or create an account / sign in with email + password (ADR 0008). Mirrors `WelcomeView.swift`.
 */
export function Welcome({ joinCode, onWantsJoin }: { joinCode?: string; onWantsJoin: () => void }) {
  const [name, setName] = useState('')
  const [isWorking, setWorking] = useState(false)
  const [error, setError] = useState<string>()
  const [accountMode, setAccountMode] = useState<AccountMode>()
  const captcha = useCaptcha()
  const trimmed = name.trim()

  async function start(joining: boolean, event?: FormEvent) {
    event?.preventDefault()
    if (!trimmed || isWorking || !captcha.ready) return
    setWorking(true)
    setError(undefined)
    if (joining) onWantsJoin()
    try {
      await auth.signInAsGuest(trimmed, captcha.token)
    } catch {
      captcha.reset()
      setError("Couldn't get started. The first launch needs an internet connection — check it and try again.")
      haptic('error')
      setWorking(false)
    }
  }

  return (
    <main className="welcome">
      <div className="welcome-hero">
        <img src="/icons/icon-192.png" alt="" width={104} height={104} className="welcome-icon" />
        <h1>Shopping List</h1>
        <p className="secondary">One list, two phones, always in sync.</p>
      </div>

      {accountMode ? (
        <AccountForm mode={accountMode} suggestedName={trimmed} onCancel={() => setAccountMode(undefined)} />
      ) : (
        <form className="welcome-form" onSubmit={(e) => start(false, e)}>
          <input
            className="field glass"
            placeholder="Your name"
            maxLength={50}
            autoComplete="given-name"
            autoFocus
            enterKeyHint="go"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <p className="footnote secondary">
            Your partner sees it, like “{trimmed || 'Ana'} got Milk”.
          </p>
          {captcha.widget}
          <button type="submit" className="button prominent" disabled={!trimmed || isWorking || !captcha.ready}>
            {isWorking ? '…' : 'Start a new list'}
          </button>
          <button
            type="button"
            className="button"
            disabled={!trimmed || isWorking || !captcha.ready}
            onClick={() => start(true)}
          >
            {joinCode ? `Join room ${joinCode}` : 'Join a room'}
          </button>

          <div className="welcome-links">
            <button type="button" className="link" disabled={isWorking} onClick={() => setAccountMode('create')}>
              Create account
            </button>
            <span className="tertiary">·</span>
            <button type="button" className="link" disabled={isWorking} onClick={() => setAccountMode('signIn')}>
              Sign in
            </button>
          </div>
          <p className="footnote secondary">No account needed — you can create one later in Settings.</p>
          {error && (
            <p className="footnote error" role="alert">
              {error}
            </p>
          )}
        </form>
      )}
    </main>
  )
}
