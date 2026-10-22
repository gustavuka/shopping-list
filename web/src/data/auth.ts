import { AuthError, type Session } from '@supabase/supabase-js'
import { db } from './db'
import { authStorageKey, supabase } from './supabase'

export interface AuthState {
  userId?: string
  /** undefined for guests. */
  email?: string
}

/**
 * Who this browser is: a guest (anonymous Supabase user) or an email + password account
 * (ADR 0007, 0008). Port of `Data/Remote/AuthService.swift`. The session is read synchronously
 * from localStorage, so a returning user renders their list without waiting for the network.
 */
class AuthService {
  private state: AuthState = readStoredSession()
  private listeners = new Set<() => void>()

  constructor() {
    supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_OUT') this.update({})
      else if (session) this.apply(session)
      else if (event === 'INITIAL_SESSION') this.update({})
    })
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  getState = (): AuthState => this.state

  /** Creates this browser's guest user. `name` becomes the profile's display name. */
  async signInAsGuest(name: string, captchaToken?: string): Promise<void> {
    const { data, error } = await supabase.auth.signInAnonymously({
      options: { data: { display_name: name.trim() }, captchaToken },
    })
    if (error) throw error
    if (data.session) this.apply(data.session)
  }

  /** Creates an email + password account. No confirmation email is sent (confirmations are off). */
  async createAccount(email: string, password: string, name: string, captchaToken?: string): Promise<void> {
    const { data, error } = await supabase.auth.signUp({
      email: normalize(email),
      password,
      options: { data: { display_name: name.trim() }, captchaToken },
    })
    if (error) throw error
    if (!data.session) throw new Error("This account needs email confirmation, which isn't supported yet.")
    this.apply(data.session)
  }

  async signIn(email: string, password: string, captchaToken?: string): Promise<void> {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: normalize(email),
      password,
      options: { captchaToken },
    })
    if (error) throw error
    this.apply(data.session)
  }

  /** Turns this guest into an account. Same user id: rooms, items and name are kept. */
  async upgradeGuest(email: string, password: string): Promise<void> {
    const { data, error } = await supabase.auth.updateUser({ email: normalize(email), password })
    if (error) throw error
    if (data.user.is_anonymous || !data.user.email) {
      throw new Error("This account needs email confirmation, which isn't supported yet.")
    }
    this.update({ ...this.state, email: data.user.email })
  }

  /** Forgets this browser's user and its local data. Rooms stay; rejoin with code + password. */
  async signOut(): Promise<void> {
    // scope 'local': usually offline-tolerant, and never signs the account out on other devices.
    const { error } = await supabase.auth.signOut({ scope: 'local' })
    if (error) console.error('Sign out failed:', error)
    this.update({}) // unmounts the session first, so its sync engine stops before the wipe
    await db.wipe()
  }

  private apply(session: Session): void {
    this.update({ userId: session.user.id, email: session.user.is_anonymous ? undefined : session.user.email })
  }

  private update(next: AuthState): void {
    if (next.userId === this.state.userId && next.email === this.state.email) return
    this.state = next
    this.listeners.forEach((l) => l())
  }
}

function readStoredSession(): AuthState {
  try {
    const session = JSON.parse(localStorage.getItem(authStorageKey) ?? 'null') as Session | null
    if (!session?.user) return {}
    return { userId: session.user.id, email: session.user.is_anonymous ? undefined : session.user.email }
  } catch {
    return {}
  }
}

function normalize(email: string): string {
  return email.trim().toLowerCase()
}

/** A user-facing message for a failed account action. */
export function authMessage(error: unknown): string {
  if (!(error instanceof AuthError)) {
    return error instanceof Error && error.message.includes('confirmation')
      ? error.message
      : 'Something went wrong. Check your connection and try again.'
  }
  switch (error.code) {
    case 'invalid_credentials':
      return 'Wrong email or password.'
    case 'email_exists':
    case 'user_already_exists':
      return "There's already an account with this email. Sign in instead."
    case 'weak_password':
      return 'Use a password with at least 6 characters.'
    case 'captcha_failed':
      return "Couldn't confirm you're not a bot. Try again."
    case 'validation_failed':
    case 'email_address_invalid':
      return 'Check the email address and try again.'
    default:
      return 'Something went wrong. Check your connection and try again.'
  }
}

export const auth = new AuthService()
