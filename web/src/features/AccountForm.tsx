import { useState, type FormEvent } from 'react'
import { auth, authMessage } from '../data/auth'
import { useCaptcha } from '../ui/Captcha'
import { haptic } from '../ui/haptics'

/** create: new account; signIn: existing account; upgrade: save this guest as an account (same user id). */
export type AccountMode = 'create' | 'signIn' | 'upgrade'

const titles: Record<AccountMode, string> = {
  create: 'Create account',
  signIn: 'Sign in',
  upgrade: 'Save as account',
}

/** Email + password form (ADR 0008). No email is ever sent; there's no password reset yet. */
export function AccountForm({
  mode,
  suggestedName = '',
  onCancel,
  onDone,
}: {
  mode: AccountMode
  suggestedName?: string
  onCancel: () => void
  onDone?: () => void
}) {
  const [name, setName] = useState(suggestedName)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [isWorking, setWorking] = useState(false)
  const [error, setError] = useState<string>()
  const needsName = mode === 'create'
  // Creating an account and signing in are captcha-protected; upgrading an already signed-in guest isn't.
  const captcha = useCaptcha()
  const needsCaptcha = mode !== 'upgrade'
  const canSubmit =
    email.includes('@') && password.length >= 6 && (!needsName || name.trim()) && (!needsCaptcha || captcha.ready) && !isWorking

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!canSubmit) return
    setWorking(true)
    setError(undefined)
    try {
      if (mode === 'create') await auth.createAccount(email, password, name, captcha.token)
      else if (mode === 'signIn') await auth.signIn(email, password, captcha.token)
      else await auth.upgradeGuest(email, password)
      haptic('success')
      onDone?.()
    } catch (e) {
      if (needsCaptcha) captcha.reset()
      setError(authMessage(e))
      haptic('error')
      setWorking(false)
    }
  }

  return (
    <form className="welcome-form" onSubmit={submit}>
      <h2>{titles[mode]}</h2>
      {needsName && (
        <input
          className="field glass"
          placeholder="Your name"
          maxLength={50}
          autoComplete="given-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
      )}
      <input
        className="field glass"
        type="email"
        placeholder="Email"
        autoComplete="email"
        autoCapitalize="none"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
      />
      <input
        className="field glass"
        type="password"
        placeholder="Password (6+ characters)"
        autoComplete={mode === 'signIn' ? 'current-password' : 'new-password'}
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      {needsCaptcha && captcha.widget}
      {mode === 'upgrade' && <p className="footnote secondary">Your name and lists stay exactly as they are.</p>}
      <button type="submit" className="button prominent" disabled={!canSubmit}>
        {isWorking ? '…' : titles[mode]}
      </button>
      <button type="button" className="button" onClick={onCancel} disabled={isWorking}>
        Cancel
      </button>
      {error && (
        <p className="footnote error" role="alert">
          {error}
        </p>
      )}
    </form>
  )
}
