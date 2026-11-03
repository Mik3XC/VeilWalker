# VeilWalker for iOS: handoff

You're building the iOS version of **VeilWalker**, a privacy-first pedometer that already ships on Android (0.3.0, in Google Play review as of 2026-10-30). Goal: **1:1 with Android** in look, rules and economy, using the **same backend, same accounts and same recovery phrase**. Where iOS forces a different mechanism, keep the user-visible behaviour identical and note the difference here.

Read the Android code as the spec. This repo (`StepCounterPro`) is the monorepo: put the iOS app in `ios/`. Do **not** change the backend or the Android app without the owner's say-so; the server is live with real users' signed ledgers.

## 1. Product in one paragraph

A walking app that counts steps without watching you. No email, name or password: your account is a **24-word recovery phrase**. Steps are counted on the phone; only signed **daily totals** leave it, over **Tor by default** (embedded Arti, no clearnet fallback). Points are minted and signed by the server and kept in a hash-chained ledger on the phone. Status, not cash: permanent handles, clans, 91 badges, outlaw ranks, journey cards, hidden mountain cards. Terminal-style ASCII UI, dark, monospace, violet and green, one-screen home with thin `> label` text buttons (never filled button chrome).

Owner: 3XCypher / Premise-i3 (contact premiselayer@gmail.com). The owner is a systems engineer (Rust/Tor) who wants decisive, opinionated help.

## 2. Locked decisions (don't re-litigate)

- **Privacy:** on-device processing; raw motion and GPS never leave the phone and are purged after 30 days; no ads, no analytics SDKs, no trackers; no IP logging server-side.
- **Tor on by default, no clearnet fallback.** If Tor is on but not connected, requests fail and retry later. Clearnet HTTPS only when the user turns Tor off.
- **Steps shown are TRUE counts.** The owner benchmarks against Sweatcoin and The Conqueror. Multipliers affect **points only**, never displayed steps or km.
- **Economy:** points never expire; **no daily cap** (free or paid); 1,000 steps at 1.0x = 1 point. Multipliers: passive 0.5, walk (sensor only) 0.85, walk with GPS 1.0, walk over Tor ("onion") 1.25. Server recomputes and is the source of truth.
- **Hands-free walks, no "End walk" button:** 27 s of continuous steps starts a walk; 47 s still = paused; 3 min still = "red light" notice; 4.5 min still = walk ends.
- **Snowflake** (Tor volunteer proxy): earns status (frost) only, never points; only while walking; data caps (prompt at 50 MB, 500 MB/day). Not working on Android yet ("flake soon"). **Do not build it on iOS v1** (see §8).
- **Handles** are permanent: 5+ chars, no renames. Clans shown as `[TAG] HashCat`.
- **Weather is opt-in** (off by default).
- US first. Same bundle identity as Android where possible: **`com.premisei3.veilwalker`**.

## 3. Backend contract (unchanged, shared with Android)

- Clearnet: `https://feisty-presence-production-b8ec.up.railway.app`
- Onion: `http://6y62fbzjvat43ep2wukogoszr2wtzc2lkzf2bp22wuixkw4lgwxl6cid.onion` (plain HTTP inside Tor)
- Pinned server ledger public key (Ed25519, hex): `fd0adaa84eb11df889b66391dd6c8982dcebd5a12a876aa2031d8de043d0171f`

### Request signing (every call; no cookies, no tokens)
Headers: `x-tb-key` (hex Ed25519 public key), `x-tb-ts` (ms since epoch), `x-tb-nonce` (16 random bytes, hex), `x-tb-sig` (hex signature).
Signed message (UTF-8, `\n`-joined): `METHOD\nPATH\nhex(sha256(body))\nTS\nNONCE`. PATH excludes the query string (check `backend/src/auth.rs`). Clock skew limit is 5 min; nonces are single-use. Empty body = sha256 of zero bytes.

### Endpoints (`core/net/.../ApiClient.kt` is the client reference; `backend/src/*.rs` the truth)
| Method & path | Body → response |
|---|---|
| POST `/v1/register` | empty |
| POST `/v1/sync` | `{day, steps_passive, steps_sensor, steps_gps, steps_onion, verdict, summary_sig}` → `{minted_milli, held_for_review, seq}` |
| GET `/v1/ledger?after=N` | signed entries; verify each against the pinned key and the hash chain |
| GET `/v1/me` | `{username, clan, avatar}` |
| POST `/v1/username` | `{username}`; errors taken / already_claimed / invalid_* / reserved |
| POST `/v1/clan`, `/v1/clan/join`, `/v1/clan/leave` | `{tag}` → `{clan}` |
| POST `/v1/profile` | `{avatar}` (0–3) |
| POST `/v1/invites` | `{kind: "friend"|"clan"}` → `{code}` (`VW-XXXX-XXXX`) |
| POST `/v1/invites/accept` | `{code}` → `{friend, joined_clan}` |
| GET `/v1/friends`, POST `/v1/friends/remove`, GET `/v1/squad` | people = `{id, handle, clan, avatar, week_steps}` |
| GET `/v1/history` | daily totals by tier, for restore |
| DELETE `/v1/account` | Apple requires in-app deletion too |

### Sync rules
- One summary per day, re-sent as the day grows; totals may only grow (server returns 409 otherwise). The server mints only the difference.
- `summary_sig` = device signature over the canonical string `day|passive|sensor|gps|onion|verdict` (see `DayTotals.canonical()` in `SyncRepository.kt`). Match Kotlin's float formatting of `verdict` exactly, or just sign the same string the server stores.
- **Onion credit is proven server-side:** `steps_onion` only counts if the request arrives over the onion service (the server sees it on its loopback listener). Over clearnet, new onion steps are re-filed as GPS.
- Days over 60,000 steps are held for review.
- Ledger entry hash: `sha256(prev ‖ seq(be i64) ‖ kind ‖ amount(be i64) ‖ reason ‖ ref_id ‖ ts_ms(be i64))` (see `backend/src/ledger.rs` `entry_hash`). Append-only on the phone, enforced with SQLite triggers.

## 4. Identity: must be byte-identical to Android

A phrase made on Android must restore on iPhone and vice versa.
- BIP39 **24 words**, English list, standard PBKDF2 seed, **empty passphrase**. Normalize input: trim, lowercase, single spaces.
- **SLIP-0010 Ed25519**, master key `HMAC-SHA512("ed25519 seed", seed)`, hardened path **`m/44'/9077'/0'/0'`** (9077 is our coin type; changing it changes every account).
- Port `core/identity/src/test/.../Slip10Test.kt` vectors into XCTest **before** anything else, and add a cross-platform test: a fixed phrase must yield the same public key hex as Android.
- Storage: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced to iCloud (`kSecAttrSynchronizable = false`). Show the phrase only on a privacy-protected screen (blur when inactive, the equivalent of Android's FLAG_SECURE).
- Libraries: CryptoKit `Curve25519.Signing` works for Ed25519 signing once you have the 32-byte private seed; BIP39 needs a small audited implementation or your own (wordlist + PBKDF2 via CommonCrypto).

## 5. Platform mapping

| Android | iOS |
|---|---|
| Kotlin, Compose, Hilt | Swift 6, SwiftUI, plain DI |
| Room (+ append-only triggers) | GRDB (SQLite) so the ledger triggers port 1:1. Not SwiftData. |
| WorkManager (hourly sync) | BGTaskScheduler (`BGAppRefreshTask`) + sync on foreground |
| `TYPE_STEP_COUNTER` + reboot handling | **CMPedometer**: queryable history (7 days) even when the app wasn't running, so no reboot handling and no midnight-split hack. Query per day/hour for exact buckets. |
| Step detector + Activity Recognition transitions | CMMotionActivityManager (live, plus 7-day history) and CMPedometer live updates |
| Foreground service + notification | Background location mode during live walks + a **Live Activity** (Dynamic Island) as the "walk in progress" notice |
| Fused location, Kalman smoother | CoreLocation (`allowsBackgroundLocationUpdates` during walks) + port `GpsSmoother` |
| Barometer `TYPE_PRESSURE` | **CMAltimeter** relative altitude (and CMPedometer `floorsAscended` as a sanity check) |
| Arti via JNI | Same Rust crate, C ABI via `cbindgen`, built as an XCFramework (§6) |
| FileProvider + share sheet | `ShareLink` / `UIActivityViewController` with a JPEG |
| Android Keystore wrapping the seed | Keychain (device-only) |

No HealthKit needed (CMPedometer doesn't require it), which keeps the App Store privacy review simpler. Don't add HealthKit unless the owner asks.

## 6. Tor on iOS: Arti, and the passive-Tor question

### Build
Reuse `rust/trailbound-net` (Arti 0.47, `static-sqlite`, rustls + ring, panics caught). Add an `ffi` module next to the JNI one exposing `vw_tor_start(state_dir) -> port`, `vw_tor_stop()`, `vw_tor_last_error()`. Targets `aarch64-apple-ios` and `aarch64-apple-ios-sim`; package as an XCFramework. Keep Arti's state and cache dir in Application Support (excluded from backup) so later starts bootstrap in seconds from a cached consensus.

### HTTP over Tor: do it in Rust, not URLSession
`URLSession` SOCKS support on iOS depends on the OS version and hostname handling (risk of resolving `.onion` locally, a DNS leak). Instead add a small Rust function, `vw_http(method, url, headers, body) -> (status, body)`, using `arti-client` + hyper, and call it from Swift. One code path, no proxy config, no leaks. Swift does signing and JSON; Rust does transport.

### Passive Tor: don't run Tor passively. Run it only when something needs it.
Android tries to keep Tor up all day, and it doesn't hold: Samsung freezes the app when locked, and our onion status kept falsely reading "unreachable". iOS is stricter: a suspended app has no network, so a resident Tor client simply isn't possible. Design for it instead of fighting it:

1. **Passive steps need no Tor at all.** CMPedometer records every step even while the app is dead. Those steps are banked locally and synced later. Nothing is lost by Tor being off.
2. **Tor runs in exactly three situations:**
   - **App in foreground:** start Arti on launch, show the same `(%) tor on · onion ok/checking…/retrying` line.
   - **During a live walk:** background location mode keeps the process alive, so Arti stays connected for the whole walk. That's what makes an **Onion Walk** (1.25x) possible on iOS. Same rule as Android: steps in a walk window count as onion only if Tor was connected for that window.
   - **Background sync:** a `BGAppRefreshTask` boots Arti from the cached state (aim for under 10 s), syncs unsent days, and stops. If it can't connect inside the budget, give up quietly and retry next time. **Never fall back to clearnet.**
3. **The server already enforces onion honestly** (onion steps only count when the sync arrives over onion), so a late sync over Tor is fine; there's nothing to fake on the client.
4. **UI honesty:** when the app opens after being suspended, show `tor waking…` rather than a stale "ok", and only show `onion ok` after a real successful onion request (Android's `markOnionOk()` behaviour).

Recommend the same model back to Android later ("Tor sleeps until it's needed"). It's more honest than an always-on status line.

### Hands-free walks under iOS rules
iOS won't let motion activity wake a suspended app, so build auto-walks in two tiers, and tell the owner which one users get:
- **Retroactive walks (every user, "When In Use" location):** on each foreground or background refresh, read CMMotionActivity + CMPedometer history and turn every walking stretch that matches the 27 s / 47 s / 4.5 min rules into a walk record. That gives badges, walk counts and the sensor tier. No GPS, no onion (Tor wasn't up).
- **Live walks (opt-in "Always" location):** use significant-change location monitoring to wake the app in the background. If CMMotionActivity says walking, start location updates + Arti + the Live Activity, which upgrades the walk to the GPS / onion tiers. Opening the app mid-walk also upgrades it live. No "End walk" button, and the same red-light notice at 3 min (local notification + Live Activity state).

## 7. Feature parity checklist (Android source in parentheses)

- **Home, one screen, no scroll** (`HomeScreen.kt`): logo + violet rule; weather corner (`[ ] weather` when off, else `52°F`, ice-blue `❄ 28°F` at 30°F or below); avatar + `[clan] handle`; lifetime TRUE steps; `lifetime steps · N pts · X km today`; walk status line; Tor line; `[-] flake soon`; compact route card; next-unlock line; links `= journeys  & social  ~ stats` / `+ badges  ^ brag  @ account`; 3XC footer + `> credits`.
- **Steps and km:** km = true steps × calibrated stride (GPS distance ÷ steps over walks over 100 m, needs 500+ GPS steps, clamped 0.5–1.0 m, default 0.75) (`RouteRepository`).
- **Stats** (`StatsScreen.kt`): day sparkline, week bars with a 10k marker, month sparkline, year/all bars, each with km; avg day, best day, lifetime km, 10k days, days walked.
- **Journeys** (`Journeys.kt`, `JourneyViews.kt`): 20 Walk for Freedom routes, one walkable (North Star I, with postcards), cards reveal one at a time, every card has a detail page with a fact timeline.
- **Outlaws on Foot** (`Outlaws.kt`): 15 cards unlocked by lifetime steps (9M → 25M, Al Capone as BOSS), rarity frames, quotes, progress bars.
- **Hidden Peaks** (`Peaks.kt`): 11 hidden cards. Climb counts only on freezing walks: **7 cm virtual climb per step**, plus real barometric climb capped at 0.25 m per step taken. K2 is the Demon card and awards the secret **Crowley Award**; Everest is the end.
- **Badges** (`core/achievements/src/main/assets/achievements.json`, 91): reuse this JSON file verbatim (copy it, or better, symlink both apps to one shared file). Ranks by badge count (Bronze 5, Silver 15, Gold 30, Platinum 50), outlaw rank ladder (Landlubber → Kingpin), frost tiers. Metrics in `Metrics.kt`.
- **Brag card** (`BragCard.kt`): 1080×1350 JPEG, no EXIF or location; avatar, handle, outlaw rank, today's steps + km, ASCII 10k bar, lifetime, date; share + save to Photos (add-only permission).
- **Social** (`SocialScreen.kt`): invites, friends, squad leaderboard.
- **Account** (`AccountScreen.kt`): handle claim, clan create/join/leave, avatar picker, weather switch + collection note, recovery phrase, sync, restore (rebuild history via `/v1/history`, avatar via `/v1/me`), delete account (type DELETE).
- **Consent screen** before any background work, linking `https://sites.google.com/view/veilwalker-app/{privacy,health-data,terms}`.
- **About / credits:** 3XC ASCII art, scrolling credits crawl (update the list for iOS: Swift, GRDB, Arti, etc.).
- **Anti-cheat** (`WalkVerifier.kt`, `GpsSmoother.kt`): penalize only cadence over 3.2 steps/s (minimum 8 steps per window), vehicle speed, mock location. On iOS, add CMMotionActivity `automotive` as a veto.
- **Weather** (`WeatherRepository.kt`): api.weather.gov, location rounded to 0.1° (~11 km), over Tor when on (wait if Tor isn't up), keep only the temperature, refresh at most every 30 min, opt-in. Don't use WeatherKit: it sends location to Apple.

Content (journeys, outlaws, peaks) currently lives in Kotlin. **First task worth doing:** export it to shared JSON (`shared/content/*.json`) that both apps load, so copy edits land once. Ask the owner before touching the Android side; or start by generating the JSON and only switch Android over later.

## 8. Deliberately out of v1

- **Snowflake hosting.** Android's engine is a stub too. On iOS, keeping a proxy alive in the background via location mode would misuse a background mode (App Store guideline 2.5.4). Show `[-] flake soon`.
- Paid tier ("Focus Walk"), crypto, gift cards.
- Dog Mode.

## 9. App Store notes

- **Privacy nutrition label**, mirroring Play's data safety form: User ID (app functionality, account management); Fitness (daily step totals; app functionality); Other user content (handle, clan); Coarse location (opt-in weather, shared with the US National Weather Service, not linked to identity, not tracking). No tracking, so no ATT prompt.
- **Location purpose strings:** When In Use (GPS distance and anti-cheat during walks, weather) and Always (optional: start walks automatically). Motion purpose string: steps and walk detection.
- **Encryption export compliance:** the app ships Tor and custom crypto, so `ITSAppUsesNonExemptEncryption` likely needs YES plus the open-source exemption paperwork. **Flag this to the owner; don't guess.**
- In-app account deletion: required, already designed.
- Organization developer account for Premise-i3 needs a D-U-N-S number; the owner handles enrollment, signing and App Store Connect. **Never enter credentials or click submit for review without the owner's explicit OK.**

## 10. Suggested build order

1. XCTest identity vectors (BIP39 + SLIP-0010) → same public key as Android.
2. Arti XCFramework + Rust `vw_http` → `GET /health` over the onion address from a test app.
3. Request signing + `/v1/register`, `/v1/me` against the live server (clearnet first, then onion).
4. CMPedometer day totals → `/v1/sync` → ledger pull + verification.
5. Home screen in the terminal style, then badges JSON, stats, journeys.
6. Live walks (location + Live Activity + Tor), then retroactive walks.
7. Account (handle, clan, restore, delete), social, brag card, weather, Hidden Peaks, outlaws.

## 11. Working rules

- The owner wants decisive recommendations, not surveys of options.
- Never paste or log the recovery phrase, keys or tokens; never commit signing material.
- Test on a real iPhone; the owner's test devices are a Galaxy S26 Edge (Android 17) and an iPhone.
- Keep these files in sync when behaviour changes: `docs/legal/privacy-policy.md` and the App Store privacy label.
