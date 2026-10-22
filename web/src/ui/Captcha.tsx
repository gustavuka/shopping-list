import { useEffect, useRef, useState, type ReactNode } from 'react'

const siteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined

/**
 * Whether sign-ups and sign-ins need a Cloudflare Turnstile token (ADR 0007, 0009). Set
 * `VITE_TURNSTILE_SITE_KEY` only once captcha protection is on in the Supabase project.
 */
export const captchaRequired = !!siteKey

interface Turnstile {
  render(element: HTMLElement, options: Record<string, unknown>): string
  remove(widgetId: string): void
}

declare global {
  interface Window {
    turnstile?: Turnstile
  }
}

let loading: Promise<Turnstile> | undefined

/** Loaded on first use, so the list screen never pays for it. */
function loadTurnstile(): Promise<Turnstile> {
  loading ??= new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
    script.async = true
    script.onload = () => (window.turnstile ? resolve(window.turnstile) : reject(new Error('Turnstile missing')))
    script.onerror = () => {
      loading = undefined
      script.remove()
      reject(new Error('Turnstile failed to load'))
    }
    document.head.append(script)
  })
  return loading
}

/**
 * A captcha token for the next auth request. Tokens are single-use: call `reset()` after a
 * failed attempt. `ready` is always true when no captcha is configured.
 */
export function useCaptcha(): { token?: string; ready: boolean; widget: ReactNode; reset: () => void } {
  const [token, setToken] = useState<string>()
  const [generation, setGeneration] = useState(0)
  return {
    token,
    ready: !captchaRequired || token !== undefined,
    widget: captchaRequired ? <TurnstileWidget key={generation} onToken={setToken} /> : null,
    reset: () => {
      setToken(undefined)
      setGeneration((g) => g + 1)
    },
  }
}

/** Invisible unless Cloudflare asks for an interaction. Remounted (via `key`) to get a fresh token. */
function TurnstileWidget({ onToken }: { onToken: (token: string | undefined) => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const onTokenRef = useRef(onToken)
  onTokenRef.current = onToken

  useEffect(() => {
    let cancelled = false
    let widgetId: string | undefined
    let turnstile: Turnstile | undefined
    loadTurnstile()
      .then((t) => {
        if (cancelled || !ref.current) return
        turnstile = t
        widgetId = t.render(ref.current, {
          sitekey: siteKey,
          appearance: 'interaction-only',
          theme: 'auto',
          callback: (value: string) => onTokenRef.current(value),
          'expired-callback': () => onTokenRef.current(undefined),
          'error-callback': () => onTokenRef.current(undefined),
        })
      })
      .catch((error: unknown) => console.error(error))
    return () => {
      cancelled = true
      if (turnstile && widgetId) turnstile.remove(widgetId)
    }
  }, [])

  return <div ref={ref} className="captcha" />
}
