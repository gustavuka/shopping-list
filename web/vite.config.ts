/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig, type Plugin } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    productionChecks(),
    VitePWA({
      // Not 'autoUpdate': that reloads the page the moment a deploy lands. main.tsx applies updates
      // when the app is backgrounded instead.
      registerType: 'prompt',
      includeAssets: ['icons/apple-touch-icon.png'],
      manifest: {
        name: 'Shopping List',
        short_name: 'Shopping',
        description: 'One shared shopping list for two phones, always in sync.',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        background_color: '#f2f2f7',
        theme_color: '#2fb45a',
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // App shell only. Supabase requests always go to the network; offline data lives in IndexedDB.
        globPatterns: ['**/*.{js,css,html,png,svg,webmanifest}'],
        navigateFallback: '/index.html',
      },
    }),
  ],
  // supabase-js is most of the bundle; see the web budget in docs/performance.md.
  build: { chunkSizeWarningLimit: 650 },
  server: { host: true },
  test: { environment: 'node' },
})

/**
 * Build-only: refuses to build without the Supabase settings (they're inlined at build time, so a
 * missing one would ship a blank page) or with a secret key, and writes `_headers` (Cloudflare
 * Pages / Netlify) with a CSP scoped to this build's Supabase project.
 */
function productionChecks(): Plugin {
  let env: Record<string, string> = {}
  return {
    name: 'production-checks',
    apply: 'build',
    configResolved(config) {
      env = config.env
      const url = env.VITE_SUPABASE_URL
      const key = env.VITE_SUPABASE_KEY
      if (!url || !key) {
        throw new Error('VITE_SUPABASE_URL and VITE_SUPABASE_KEY must be set (web/.env.local or the host’s build env).')
      }
      if (key.startsWith('sb_secret_') || jwtRole(key) === 'service_role') {
        throw new Error('VITE_SUPABASE_KEY is a secret key. Use the publishable (anon) key; it ships to every browser.')
      }
    },
    generateBundle() {
      const api = new URL(env.VITE_SUPABASE_URL!)
      const socket = `${api.protocol === 'https:' ? 'wss:' : 'ws:'}//${api.host}`
      const turnstile = env.VITE_TURNSTILE_SITE_KEY ? ' https://challenges.cloudflare.com' : ''
      const csp = [
        "default-src 'self'",
        `script-src 'self'${turnstile}`,
        `frame-src${turnstile || " 'none'"}`,
        `connect-src 'self' ${api.origin} ${socket}`,
        "img-src 'self' data:",
        "style-src 'self' 'unsafe-inline'",
        "worker-src 'self'",
        "manifest-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
      ].join('; ')
      const headers = [
        '/*',
        `  Content-Security-Policy: ${csp}`,
        '  X-Content-Type-Options: nosniff',
        '  Referrer-Policy: strict-origin-when-cross-origin',
        '  Permissions-Policy: camera=(), microphone=(), geolocation=()',
        // The service worker decides when a deploy reaches users, so it must never be cached.
        '/sw.js',
        '  Cache-Control: no-cache',
        '/assets/*',
        '  Cache-Control: public, max-age=31536000, immutable',
      ]
      this.emitFile({ type: 'asset', fileName: '_headers', source: `${headers.join('\n')}\n` })
    },
  }
}

/** The `role` claim of a legacy JWT API key, if it is one. */
function jwtRole(key: string): string | undefined {
  try {
    return (JSON.parse(atob(key.split('.')[1] ?? '')) as { role?: string }).role
  } catch {
    return undefined
  }
}
