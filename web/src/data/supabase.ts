import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_KEY as string | undefined

if (!url || !key) {
  throw new Error('Missing VITE_SUPABASE_URL / VITE_SUPABASE_KEY — copy web/.env.example to web/.env.local.')
}

/** Where supabase-js keeps the session; read synchronously at launch (see auth.ts). */
export const authStorageKey = 'shopping-list-auth'

export const supabase = createClient(url, key, {
  auth: { storageKey: authStorageKey, persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
})
