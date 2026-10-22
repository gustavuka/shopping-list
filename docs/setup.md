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

`Config/Secrets.xcconfig` (gitignored, included by `Config/Base.xcconfig`):

```
SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_KEY = sb_publishable_...   # the publishable (anon) key — never the secret key
```

(`/$()/` is the xcconfig trick to keep `//` from being parsed as a comment.) The values are exposed through `Info.plist` keys (`SupabaseURL`, `SupabaseKey`) and read once at startup into `AppConfig`.

Locally, sign-in emails don't leave your machine: open Mailpit at http://127.0.0.1:54324 to read the 6-digit code. The local email template lives in `supabase/templates/otp.html` (wired up in `supabase/config.toml`).

## Supabase cloud project (free tier)

1. Create a project at supabase.com (free plan: 500 MB DB, Realtime and Auth included — far more than two users need).
2. Link and push the schema:
   ```sh
   supabase link --project-ref <ref>
   supabase db push
   ```
3. **Auth → Providers → Email:** enabled. Turn **off** "Confirm email" link flow in favor of OTP.
4. **Auth → Email Templates → Magic Link:** include the code, e.g. `Your code is {{ .Token }}`, so emails contain a 6-digit code instead of only a link.
5. The built-in email sender is rate-limited (a few emails per hour) — fine for two people. If it becomes a problem, configure custom SMTP (e.g. Resend free tier).
6. Put the project URL and publishable key in `Secrets.xcconfig` (use a separate `Secrets.Release.xcconfig` if you want local vs. cloud configs).

**Pausing:** free projects pause after ~7 days without activity. Weekly shopping usually prevents it; if it pauses, restore from the dashboard (data is kept). An optional GitHub Actions cron that pings the REST API every few days keeps it awake.

## Installing on your phones

### Now: free Apple ID ("Personal Team")

- In `project.yml`, set `DEVELOPMENT_TEAM` to your personal team ID and a unique bundle ID (e.g. `com.<yourname>.shoppinglist`).
- Plug each iPhone into the Mac (or pair over Wi-Fi), enable **Developer Mode** on the phone (Settings → Privacy & Security), select it in Xcode, Run.
- On first launch: Settings → General → VPN & Device Management → trust your developer certificate.
- **Limits:** apps signed with a free account **expire after 7 days** and must be re-installed from Xcode; max 3 sideloaded apps per device. No push notifications, no iCloud, no Sign in with Apple.

### Later: paid Apple Developer Program ($99/yr)

- Distribute via **TestFlight** (builds last 90 days, updates arrive over the air — no cable for your wife's phone).
- Unlocks Sign in with Apple, push notifications, widgets with app groups, etc. Write an ADR when adopting any of these.

## Useful commands

```sh
supabase status                      # local URLs and keys
supabase migration new add_x         # new migration
supabase db diff -f <name>           # generate migration from local dashboard changes
supabase gen types --lang swift      # (optional) reference types; we hand-write DTOs
supabase test db                     # pgTAP tests
```
