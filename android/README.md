# VeilWalker

*Walk the world. Leave no trace.* A privacy-first walking adventure app for Android (iOS later).
Passive all-day steps, Onion Walks over Tor for boosted points, Snowflake Walks that help people reach Tor,
and "Walk for Freedom" routes honoring the people who fought for it.

## Layout

```
app/                 Compose UI, Hilt app, manifest (FGS types, permissions, no cloud backup)
core/data/           Room: step intervals, walks, raw traces (30-day purge), daily summaries, ledger mirror
core/steps/          StepCounterReader (reboot-safe), PassiveStepWorker (no FGS), WalkService (the only FGS)
core/anticheat/      WalkVerifier (cadence/accel/gyro), GpsSmoother (±10 m, dead zones), DailyAnomaly
core/ledger/         PointsPolicy (the economy), LedgerRepository (hash-chain verification)
core/net/            TorManager + ArtiNative JNI (embedded Arti, local SOCKS5 → OkHttp)
core/snowflake/      SnowflakeController (50/150 MB per walk, 500 MB/day caps), engine stub for gomobile AAR
rust/trailbound-net/ Arti JNI cdylib, built with cargo-ndk
backend/             Railway: Rust/Axum + Postgres + tor onion service in one container
```

## Production

- API: https://feisty-presence-production-b8ec.up.railway.app (`/health`)
- Onion: http://6y62fbzjvat43ep2wukogoszr2wtzc2lkzf2bp22wuixkw4lgwxl6cid.onion
- Railway: agile-radiance / feisty-presence / production, plus Postgres, with the `feisty-presence-volume` volume at `/data`
- **Back up `/data/tor/hs/`**. If those keys are lost, the onion address changes and shipped apps can't reach it.

## Build

```bash
./gradlew assembleDebug testDebugUnitTest
```
Toolchain: AGP 9.4.1 (built-in Kotlin), Gradle 9.8.2, Kotlin 2.4.21, Android Studio JBR (JDK 25), compileSdk 37 / targetSdk 36 / minSdk 28.

## Getting started

1. Open the folder in **Android Studio**, or build from the command line as shown above.
2. Run on the **Galaxy S26 Edge** first, then an Android 9 emulator (API 28) as the low-end floor.
3. Tor: build `rust/trailbound-net` (see its README). Without it, the app runs and Tor Mode shows as unavailable.
4. Snowflake: build the AAR (see `core/snowflake/README.md`). Without it, a Snowflake Walk behaves like an Active Walk.
5. Backend: `backend/` deploys to Railway (Dockerfile + `railway.toml`). Copy the printed `ONION:` address into `TorManager.ONION_BASE_URL`.

## Locked product decisions

| Area | Decision |
|---|---|
| Name | **VeilWalker** (renamed from Trailbound; package stays `org.trailbound.app` for now). Run a trademark search before the store listing |
| Privacy | On-device processing, keypair identity (BIP39), no data selling, HTTPS + no IP logs by default, **Tor encouraged**, Arti embedded from day one |
| Walks | **Hands-free**: activity recognition wakes the app, 27 s of continuous steps confirms a walk; 47 s still = paused, 3 min = red-light notice (continue/end), 4.5 min = ends. No end button. Auto-started walks are sensor-only until the app is opened (Android blocks background GPS start). |
| Tor | **On by default**; while on, the app never falls back to clearnet (syncs wait until Tor connects). |
| Clans | 2–4 char tag before the handle, e.g. `[ROX] HashCat`; one clan per account, open join, 50 max. |
| Offline | Steps are counted and stored on the phone; totals sync when back online (server accepts the last 7 days). |
| Walk modes | Passive (0.5×) · Active (0.85× sensor-only / 1.0× GPS) · **Onion Walk 1.25×**, verified server-side by the onion listener · Snowflake Walk (status only) |
| Daily cap | None, free or paid: every verified step counts (60k/day held for review) |
| Points | 1 pt = 1,000 steps, **never expire**, no cash value, non-transferable between users |
| Snowflake | Only while walking; ask at 50 MB → up to 150 MB per walk; 500 MB/day; **never points**, only emblem frost tiers + badges |
| Accounts | Transfer across phones / Android → iOS with the 24-word seed + E2E-encrypted backup blob |
| Routes | Walk for Freedom: Underground Railroad, Ada Lovelace, Alan Turing, Snowden, Che Guevara, and more, all at launch, told as honest history |
| Charity | 5% of Focus revenue to the Tor Project / EFF |
| Backend | Railway (no Pi): project **agile-radiance** / service **feisty-presence** / env **production** |
| Market | US first. minSdk 28 / targetSdk 36 |

## Risk register (P0 = act now → P5 = watch)

| P | Status | Risk | Mitigation in this repo / plan |
|---|---|---|---|
| **P0** 🔴 | Open | **`specialUse` FGS rejection for Snowflake** (shipping in v1.0) | Specific `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` text in the manifest; record a demo video for Play Console; Snowflake is isolated in `core/snowflake` so it can be pulled quickly if review demands it (TODO: remote kill-switch flag) |
| **P0** 🔴 | Open | **Washington My Health My Data Act** (step data = consumer health data, private right of action) | TODO: separate opt-in health consent screen + Consumer Health Data Privacy Policy before launch |
| **P1** 🔴 | Mitigated | Proxyware policy (paying for bandwidth) | Snowflake earns no points, enforced in `PointsPolicy` (no Snowflake source exists) and in the backend |
| **P1** 🔴 | Mitigated | Health FGS crash on API 34+ without permission | `WalkService.startInForeground` checks `ACTIVITY_RECOGNITION` first |
| **P1** 🟠 | Mitigated | Background location review | Never requested; location FGS type + while-in-use only |
| **P1** 🟠 | Open | "Earn money" store-listing scrutiny | Copy: "walking adventures, collect points, redeem perks"; never "cash"; state "no cash value" |
| **P2** 🟠 | Mitigated | Cheating (uncapped paid tier later) | On-device verdict, GPS veto, 60k hold-for-review on the server, onion boost provable on the server, one summary per day |
| **P2** 🟠 | Open | Account deletion requirement | `DELETE /v1/account` exists; TODO: in-app button + web deletion page |
| **P2** 🟠 | Open | Data Safety form accuracy | Answer from this README: not sold, encrypted in transit, deletion available, processed on device |
| **P3** 🟡 | Open | Snowden right of publicity; Che Guevara backlash; Underground Railroad sensitivity | No likenesses for living people; "history told honestly" framing; historian review; family lawyers sign off on route copy |
| **P3** 🟡 | Open | "No IP logs" accuracy (Railway's edge sees IPs) | Privacy policy discloses transient processing by the host; Tor Mode is the full fix |
| **P3** 🟡 | Open | Arti onion client maturity / cold start | 45 s timeout → clearnet fallback; state dir persisted for warm starts; week-1 device spike |
| **P4** 🟢 | Mitigated | Reboot counter reset | `BOOT_COUNT` + lower-value detection in `StepCounterReader` |
| **P4** 🟢 | Mitigated | Doze / Samsung sleeping apps | Hardware counter accumulates; worker catches up. TODO: onboarding deep link "Set battery to Unrestricted" |
| **P4** 🟢 | Mitigated | GPS ±10 m, rural areas, dead zones | `GpsSmoother`: accuracy gate 25 m, Kalman, 30 s speed window; no fix = sensor-only 0.85×, never a penalty |
| **P4** 🟢 | Mitigated | Google backup leaking data | `allowBackup=false` + extraction rules exclude everything |
| **P5** 🟢 | Watch | No-expiry points liability | Track outstanding points; limited, budget-funded catalog stock |
| **P5** 🟢 | Watch | APK size (Rust + Go) | AAB ABI splits; Snowflake could become a dynamic feature module |
| **P5** 🟢 | Watch | Seed loss = account loss | TODO: forced "type word #7" backup check at onboarding |
| **P5** 🟢 | Watch | COPPA | TODO: 13+ age gate; medals shipping 18+ |

## 8-week build order

1. **Week 1:** Arti spike on the S26 Edge; step counter + passive worker running on Android 9 and 16.
2. **Week 2:** WalkService + anti-cheat tuned on real walks.
3. **Week 3:** Keypair/BIP39 identity, signed requests, Railway deploy, sync + ledger.
4. **Week 4:** Route engine + first Walk for Freedom route + postcards.
5. **Week 5:** Achievement engine (JSON rules, ~220 at launch) + emblem frames + streaks.
6. **Week 6:** Snowflake AAR + caps + frost emblems; E2E backup/restore.
7. **Week 7:** Onboarding (consents, permissions in context, Tor encouragement, battery guide), redemption catalog v0.
8. **Week 8:** Play Console: Data Safety, Health Connect declaration, `specialUse` video, closed testing track.

## Identity, sync and the ledger

- **Account = 24-word BIP39 phrase.** Key derivation: SLIP-0010 Ed25519 at `m/44'/9077'/0'/0'` (same words → same key on iOS later).
  The phrase's entropy is stored encrypted under a non-exportable Android Keystore AES key; the screen is `FLAG_SECURE` while it's shown.
- **Every request is signed** (`x-tb-key/ts/nonce/sig`, see `backend/src/auth.rs`). No passwords, tokens or cookies.
- **Sync** (`core/ledger/SyncRepository`): hourly and after each walk, the phone sends each recent day's totals by trust tier.
  The server mints only the *difference* from what that day already earned, so the same day can sync many times.
  Onion-rate steps are only honoured on requests that arrive through the onion service.
- **Every phone keeps its own verified copy of its ledger** (hash-chained, server-signed, ~90 KB/user/year).
  If the server database is lost, these chains are enough to rebuild every balance; nobody can forge the server signature.
- **Back up the server signing key offline.** Without it, new signatures can't be checked against old ones. The app pins its public key
  `fd0adaa84eb11df889b66391dd6c8982dcebd5a12a876aa2031d8de043d0171f` (`LedgerRepository.SERVER_PUBLIC_KEY`).

## Naming notes

Kept on purpose after the rename: the package/applicationId `org.trailbound.app`, the Room file `trailbound.db`
(renaming it would drop existing history), the `trailbound-net` crate and its JNI symbols, the Railway service,
and the comment in `backend/migrations/0001_init.sql` (sqlx rejects edits to applied migrations).

## Not built yet (scaffold TODOs)

Server endpoint to rebuild balances from phones' signed chains, forced "type word #7" phrase backup check, route engine, achievement engine,
Health Connect fallback reader, onboarding/consent screens, the Snowflake AAR, E2E-encrypted history backup upload.
