# Setup

## Prerequisites

- macOS with **Xcode 26** (from the App Store), then `sudo xcode-select -s /Applications/Xcode.app`.
- [Homebrew](https://brew.sh), then:
  ```sh
  brew install xcodegen supabase/tap/supabase
  ```
- **Docker Desktop** (or OrbStack) — required by `supabase start` for the local stack.
- A free **Apple ID** signed into Xcode (Settings → Accounts).

## First run

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # then fill in values
supabase start            # prints local API URL + anon key
supabase db reset         # applies migrations + seed
xcodegen generate
open ShoppingList.xcodeproj
```

`Config/Secrets.xcconfig` (gitignored, included by `Config/Base.xcconfig`) picks the backend **per platform**: phones use the cloud project, simulators the local stack.

```
SUPABASE_URL[sdk=iphoneos*] = https:/$()/<project-ref>.supabase.co
SUPABASE_KEY[sdk=iphoneos*] = sb_publishable_...          # cloud: `supabase projects api-keys`
SUPABASE_URL[sdk=iphonesimulator*] = http:/$()/127.0.0.1:54321
SUPABASE_KEY[sdk=iphonesimulator*] = sb_publishable_...   # local: `supabase status`
```

Publishable keys only — never the secret/service-role key. (`/$()/` is the xcconfig trick to keep `//` from being parsed as a comment.) The values reach `Info.plist` (`SupabaseURL`, `SupabaseKey`) and are read once at startup into `AppConfig`. To point a simulator at the cloud, copy the `iphoneos` lines over the `iphonesimulator` ones.

Users are guests (`enable_anonymous_sign_ins = true`) or email + password accounts with **confirmations off** (`[auth.email] enable_confirmations = false`), so no email is ever sent ([ADR 0007](decisions/0007-guest-users-and-room-passwords.md), [0008](decisions/0008-optional-email-accounts.md)). Keep both settings in sync with the cloud via `supabase config push`.

## Supabase cloud project

The project exists: **`shopping-list`** (ref `esnlhkkaxwjfbcxnfihg`, region São Paulo `sa-east-1`, org "Personal", free plan). Its database password is in `supabase/.env` (gitignored); the app never needs it.

```sh
supabase link --project-ref esnlhkkaxwjfbcxnfihg   # once per machine (password from supabase/.env)
set -a; . supabase/.env; set +a
supabase db push -p "$SUPABASE_DB_PASSWORD"         # apply new migrations to the cloud
supabase config diff                                # review before pushing auth settings
supabase config push                                # answer y for auth; n for storage (local-only settings)
```

Notes:
- **Don't add `[auth.email.template.*]` back to `config.toml`** while on the free plan with Supabase's built-in email sender: the cloud rejects the whole auth push.
- Anonymous sign-ins are rate-limited to 30/hour per IP (`[auth.rate_limit] anonymous_users`). Captcha is off for now; see *Captcha* under the web app below.
- Migrations enable `pg_cron` and schedule the daily cleanup (`purge_tombstones`); check it under Integrations → Cron after the first push.

**Pausing:** free projects pause after ~7 days without activity. Weekly shopping usually prevents it; if it pauses, restore from the dashboard (data is kept). An optional GitHub Actions cron that pings the REST API every few days keeps it awake.

## Installing on your phones

### Now: free Apple ID ("Personal Team")

- In `project.yml`, set `DEVELOPMENT_TEAM` to your personal team ID and a unique bundle ID (e.g. `com.<yourname>.shoppinglist`).
- Plug each iPhone into the Mac (or pair over Wi-Fi), enable **Developer Mode** on the phone (Settings → Privacy & Security), select it in Xcode, Run.
- On first launch: Settings → General → VPN & Device Management → trust your developer certificate.
- **Limits:** apps signed with a free account **expire after 7 days** and must be re-installed from Xcode; max 3 sideloaded apps per device. No push notifications, no iCloud, no Sign in with Apple.

### Later: paid Apple Developer Program ($99/yr)

- Distribute via **TestFlight** (builds last 90 days, updates arrive over the air — no cable for your wife's phone).
- Unlocks Sign in with Apple (account upgrade for guests), push notifications, widgets with app groups, etc. Write an ADR when adopting any of these.

## Web app (PWA)

The same app as a web page, for phones without the native build ([ADR 0009](decisions/0009-web-pwa-client.md)). Needs Node 22+.

```sh
cd web
cp .env.example .env.local     # fill in VITE_SUPABASE_URL / VITE_SUPABASE_KEY (publishable key only)
npm install
npm run dev                    # http://localhost:5173, also on your LAN (see below)
npm test                       # unit tests (Vitest)
npm run build                  # static site in web/dist
```

- **On a phone during development:** `npm run dev` prints a Network URL. Plain `http://` on a LAN IP is not a secure context, so the service worker (offline, install) is off there; everything else works. Point `.env.local` at the cloud project (the phone can't reach `127.0.0.1`), or at your Mac's LAN IP for the local stack.
- **Hosting:** `web/dist` is a plain static site. Use **Cloudflare Pages** or **Netlify**: build command `npm run build`, root `web`, output `dist`, with `VITE_SUPABASE_URL` + `VITE_SUPABASE_KEY` (cloud project, publishable key) set as build variables. No SPA rewrites are needed (join links use `?join=CODE`).
  - The build **fails** if either variable is missing (they're inlined at build time; a missing one would ship a blank page) or if the key is a secret key.
  - The build writes `dist/_headers`, which both hosts apply: a CSP that only allows this build's Supabase project, `nosniff`, no framing, `sw.js` never cached, hashed assets cached forever. Other hosts (Vercel, GitHub Pages) ignore it; copy the headers into their config.
  - Deploy migrations first (`supabase db push`): this web build expects the `join_list` that returns `jsonb` ([ADR 0010](decisions/0010-public-web-hardening.md)).
  - Updates: a new deploy downloads in the background and applies when the app is backgrounded, or on next launch. It never reloads the app while it's open on screen.
- **Captcha (later):** the web client is ready for Cloudflare Turnstile but it's off, because the Supabase setting applies to every client and the iOS app doesn't send tokens yet. To turn it on: create a Turnstile widget for the site's domain (Invisible or Managed), add `[auth.captcha]` with `enabled = true`, `provider = "turnstile"`, `secret = "env(SUPABASE_AUTH_CAPTCHA_SECRET)"` to `config.toml` and `supabase config push`, then set `VITE_TURNSTILE_SITE_KEY` on the host and redeploy.
- **Install:** open the URL in Safari → Share → **Add to Home Screen**. It then opens full screen and works offline.

## Useful commands

```sh
supabase status                      # local URLs and keys
supabase migration new add_x         # new migration
supabase db diff -f <name>           # generate migration from local dashboard changes
supabase gen types --lang swift      # (optional) reference types; we hand-write DTOs
supabase test db                     # pgTAP tests
```
