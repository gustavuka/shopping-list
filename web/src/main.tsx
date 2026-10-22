import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'
import { App } from './App'
import './styles.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

// Precaches the app shell so it opens instantly and offline. A new version is applied when the app
// goes to the background (or on next launch), so a deploy never reloads the page mid-use; the outbox
// is in IndexedDB, so nothing pending is lost. Foregrounding checks for one: iOS rarely does on its own.
let updateWaiting = false
const updateSW = registerSW({
  immediate: true,
  onNeedRefresh: () => (updateWaiting = true),
  onRegisteredSW: (_url, registration) => {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') void registration?.update()
    })
  },
})
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden' && updateWaiting) void updateSW(true)
})
