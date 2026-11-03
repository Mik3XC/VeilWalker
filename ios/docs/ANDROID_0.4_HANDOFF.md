# VeilWalker for Android 0.4.0: handoff

You're bringing the Android app (0.3.0, versionCode 3, **live on Google Play production**) up to date with what the
iPhone build gained during the port: a new home layout, a second look (Glass), Runners Wake Mode, a Snowflake page, a
**working Snowflake proxy**, and two correctness fixes. Ship it as **0.4.0 (versionCode 4)**.

Read the iPhone code as the spec for every item: it lives in this repo's `ios-port` branch under `VeilWalker/`
(SwiftUI, file names given per item). The Android code is `app/`, `core/*` in the monorepo (`StepCounterPro`).

Owner: 3XCypher / Premise-i3 (premiselayer@gmail.com). Prepared 2026-11-03.

## 0. Ground rules (same as the iOS handoff)

- **Production is live with real users' signed ledgers.** No backend changes are needed for anything here; don't
  make any. Nothing in this release changes the request signing, the sync payload, the ledger or the identity path.
- No Room migration that rewrites or drops user data. New columns only, with defaults.
- Never log or paste a recovery phrase, key or token. Never commit signing material (upload key, keystore).
- Don't upload to Play, change Play Console declarations or press **Send for review** without the owner's OK.
- Steps shown stay TRUE counts. Snowflake earns status (frost) only, never points.

## 1. What changes, at a glance

| # | Change | Priority | Android files | iPhone reference |
|---|---|---|---|---|
| 1 | Walk distance capped at 2 m per step | **Must (bug)** | `core/steps/.../WalkService.kt` | `WalkController.swift` |
| 2 | Real Snowflake proxy (replace the stub) | **Must** | `core/snowflake/*` | `snowflake/vwflake/vwflake.go`, `SnowflakeHost.swift` |
| 3 | Home: new layout (panes, two bars, 3×2 grid, 3XC watermark, easter-egg links) | Must | `ui/HomeScreen.kt` | `HomeView.swift` |
| 4 | Shorter Tor and walk wording | Must | `ui/HomeScreen.kt` | `TorStatus.swift`, `Walks.swift` |
| 5 | Two looks: Terminal and Glass (logo tap + account toggle) | Must | `ui/Theme.kt` (+ new `ui/Looks.kt`) | `Theme.swift`, `AccountView.swift` |
| 6 | Snowflake page with the wall-breaker animation | Must | new `ui/SnowflakeScreen.kt` | `SnowflakeView.swift` |
| 7 | Runners Wake Mode | Must | new `ui/WakeScreen.kt` | `WakeView.swift` |
| 8 | Haptics on every tap | Should | `ui/VeilButton.kt`, tiles | `Theme.swift` (`Haptics`) |
| 9 | Credits: Pion WebRTC, Go | Must (licences) | `ui/CreditsScreen.kt` | `CreditsView.swift` |
| 10 | Auto-walk retry after an abandoned confirm | Check | `core/steps/.../WalkService.kt` | `WalkController.swift` |

**Not ported, on purpose:**
- The pinned `< back` bar: it exists because iPhone has no system back. Android keeps system/predictive back.
- iOS-only plumbing: retro walks from Core Motion history, the Live Activity, `BGAppRefreshTask`, the `waking` Tor state.

## 2. Must-fix bugs

### 2.1 Distance capped at 2 m per step (item 1)

GPS drift can inflate a walk's distance far beyond what the steps allow. On iPhone a 132-step walk recorded 2,059 m and
unlocked a false **One K** badge. Android has the same code path: `WalkService.kt` stores `distanceM = gps.totalDistanceM`.

Fix (mirror `WalkController.swift`, `maxMetresPerStep = 2.0`):

```kotlin
private const val MAX_METRES_PER_STEP = 2.0   // a running stride is ~1.5 m; anything past 2 m a step is GPS drift
...
distanceM = minOf(gps.totalDistanceM, (w.steps + steps) * MAX_METRES_PER_STEP),
```

Apply it everywhere a walk's distance is saved or shown (the window loop and walk end). Add a unit test: 132 steps
with 2,059 m of GPS gives 264 m. Badges already awarded stay: removing a user's badge is the owner's call, not part
of this release.

### 2.2 Auto-walk retry (item 10: check, then fix if it applies)

On iPhone, a confirm that timed out (no 27 s of continuous steps within the minute) never retried while the person kept
walking. Android's `confirmThenWalk()` → `abandon()` stops the service, and Activity Recognition only sends a new
`ENTER` transition after a change of activity, so the same gap is likely. Test: start walking with stops at 20 s and
25 s, then walk steadily for 2 minutes. If no walk starts, keep the step listener alive for one more confirm cycle
after `abandon()` when steps are still arriving (as `WalkController.swift` does), rather than stopping the service.

## 3. Snowflake: make it real (item 2)

Android 0.3.0 ships the controller, caps, notifications and FGS declaration, but `SnowflakeEngine` is a stub
(`isAvailable = false`, home shows `[-] flake soon`). The iPhone build now runs the Tor Project's proxy, verified on a
real phone (frost minutes accrued from the live engine). Reuse the same Go wrapper.

### 3.1 Build the AAR from the same wrapper

`snowflake/vwflake/` is a small Go package over Snowflake v2.15.3 (`proxy/lib`). It exposes `Start(capacity, Traffic)`,
`Stop()`, `Running()`, `LastError()`, and a `Traffic.Relayed(bytes)` callback. It:

- sets `ProxyType = "iptproxy"` (the mobile type the broker already knows),
- sets `RelayDomainNamePattern = "snowflake.torproject.net$"` (forward only to the Tor Project's relays; without it the
  proxy fails with `invalid relay domain name pattern`),
- reports only bytes: Snowflake's stats are in KB, so it multiplies by 1000; **countries and connection events are
  dropped** and must never reach the app.

Add `snowflake/build-aar.sh` next to `build-xcframework.sh`:

```sh
gomobile bind -target android -androidapi 28 -javapkg org.trailbound.flake \
  -o "$ROOT/core/snowflake/libs/vwflake.aar" .
```

Needs the Android NDK (`ANDROID_NDK_HOME`). Keep the AAR out of git like the xcframework (`.gitignore`), or commit it
deliberately; either way the build script is the source of truth.

**16 KB pages:** Play requires native libraries aligned for 16 KB pages on Android 15+. Check the AAR's `libgojni.so`
with `zipalign -c -P 16 -v 4` on the final APK (or `check_elf_alignment.sh`). If it fails, add
`-ldflags='-extldflags=-Wl,-z,max-page-size=16384'` to the bind.

### 3.2 Wire `SnowflakeEngine` to it

The controller polls a cumulative `bytesRelayed()` and calls `pause()`/`resume()`; the wrapper pushes deltas and has
only start/stop. Adapt in the engine, not the controller:

```kotlin
@Singleton
class SnowflakeEngine @Inject constructor() {
    val isAvailable = true
    private val relayed = AtomicLong(0)
    private var capacity = 2
    private val traffic = object : Traffic { override fun relayed(bytes: Long) { relayed.addAndGet(bytes) } }

    fun start(capacity: Int) { this.capacity = capacity; Vwflake.start(capacity.toLong(), traffic) }
    fun pause() = Vwflake.stop()          // the 50 MB prompt: stop; current clients drop
    fun resume() = Vwflake.start(capacity.toLong(), traffic)
    fun stop() = Vwflake.stop()
    fun bytesRelayed(): Long = relayed.get()
    val lastError: String? get() = Vwflake.lastError().ifEmpty { null }
}
```

In the controller's monitor loop, stop and surface `lastError` the way `SnowflakeStats.start` does on iPhone.

### 3.3 Stats: one number

- Add a **lifetime** total (`prefs "bytes_total"`) alongside the daily total; that's the one number shown anywhere
  ("shared through snowflake"). Keep no peer, address, country or session log.
- **Caps:** Android uses MiB (`50L * 1024 * 1024`), iPhone uses decimal MB (`50_000_000`). The UI says "MB" and formats
  with 1e6, so switch Android to decimal (50 / 150 / 500 MB) to match. Format as iPhone's `SnowflakeStats.format`:
  `0 B`, `512 KB`, `41.2 MB`, `1.30 GB`.
- Frost minutes keep coming from `SnowflakeEvent.Progress` into the walk session, as today.

### 3.4 Where it hosts on Android

Android can do what iPhone can't: **host during every walk** in the background (the existing `hostOnWalks` opt-in,
`WalkMode.SNOWFLAKE`, `specialUse` FGS, already declared in Play with the demo video). Keep that. Wake Mode (§6) is an
extra place to switch it on, not the only one.

## 4. Home screen (items 3, 4)

Rebuild `HomeScreen.kt` from `HomeView.swift`, top to bottom, one screen, no scroll:

1. **Header:** logo (tap = switch look, with haptic) · `VeilWalker` · weather. Violet rule under it, with a soft glow.
2. **Identity row:** the avatar in **its own pane** (92 dp wide, avatar centred, tap → account), and beside it a pane
   with `[TAG] handle`, lifetime steps (headline, violet, glow, animated count), and
   `lifetime steps · N pts · 0.0 km today` (one line, scales down).
3. **Walk | Tor bar:** one outlined pane, two cells split by a thin violet rule. Left: the walk line (tap = start a walk
   now). Right: the Tor line (tap = toggle Tor, glows green when the onion check is ok). The Tor cell never truncates;
   the walk text gives way.
4. **Snowflake | Wake bar:** one pane outlined in ice blue (`#8FD3FF` at 35%). Left: `(*) snowflake` when on,
   `[ ] snowflake` when off (ice, glowing), then `> learn` in violet; tap opens the Snowflake page. Right:
   `(o) wake mode` in green; tap opens Wake Mode.
5. Route card (compact; sketch about 110 dp tall), then `[#] next: …`.
6. Spacer, then the **3×2 tile grid**, down where thumbs reach. Each tile is an outlined pane (violet at 45%) with a
   glowing glyph over its name: `= journeys`, `& social`, `~ stats` / `+ badges N/M`, `^ brag`, `@ account`.
7. **3XC watermark:** the 3XC ASCII art at 10% violet, *behind* the grid, offset about 96 dp up so it peeks into the
   empty space above the tiles. Not clickable.
8. **Easter-egg links:** tiny `about · credits` in muted, bottom right. They replace the clickable 3XC footer and
   `> credits`.

Wording (item 4):

| Was (Android 0.3.0) | Now |
|---|---|
| `walk: auto · 27 s of steps starts it` | `walk: auto · 27 s of steps needed` |
| `(%) tor on · connecting…` | `(%) tor · connecting…` |
| `(%) tor on · onion checking…` | `(%) tor · checking…` |
| `(%) tor on · onion ok` | `(%) tor · onion ok` |
| `(%) tor on · onion retrying` | `(%) tor · retrying` |
| `(%) tor on · waiting` | `(%) tor · waiting` |
| `[x] tor off` | unchanged |

## 5. Two looks: Terminal and Glass (item 5)

`Look` = `terminal` (default, today's look) or `glass`, stored in prefs (`"look"`). Switched by tapping the home logo
or `~ look: terminal (tap to switch)` on the account screen, with the line
`// terminal is the classic flat look. glass is frosted panels over a drifting ASCII aurora. Tap the logo on the home screen to switch too.`
Expose it as a `CompositionLocal` so every screen reads it.

- **Backdrop** (behind every screen):
  - Terminal: flat `#07070A` plus faint scanlines (a 1 px line every 3 px, white at 5%).
  - Glass: a static ASCII field (` .:-=+*#%@`, 14 dp cells, violet at 11%, value from
    `sin(c*0.35)+cos(r*0.28)+sin((c+r)*0.15)`) and three blurred blobs (violet 420 dp, green 300 dp, `#4B3BD6` 380 dp, 45%
    opacity) drifting over 14 s, reversing.
  - **Performance (learned the hard way on iPhone):** draw the field once into a bitmap and move layers with
    `graphicsLayer { translationX/Y }`. A per-frame `Canvas` redraw ate 85% CPU and starved taps. Turn the drift off
    when animations are disabled (`Settings.Global.ANIMATOR_DURATION_SCALE == 0`).
- **Panels** (`Modifier.veilPanel(outlined, outline, padding)`):
  - Terminal: outlined panes get `#101016` fill and a 1 dp outline; plain content gets nothing.
  - Glass: 22 dp rounded, frosted (backdrop blur on API 31+; the [Haze](https://github.com/chrisbanes/haze) library,
    Apache-2.0, is the simplest route), violet tint at 6%, hairline white at 8% (or the given outline at 70%). Below
    API 31, a translucent `#101016` at 70% instead of blur.
- **Glow:** a soft shadow in the text's colour on key numbers and signals (lifetime steps, Tor ok, the logo). In
  Compose, `TextStyle(shadow = Shadow(color.copy(alpha = .55f), blurRadius = …))`.
- Credits stays in the Terminal style in both looks.

## 6. Snowflake page (item 6)

New `SnowflakeScreen.kt` from `SnowflakeView.swift`. Same sections and copy, adapted for Android:

- Status pane, outlined in ice: **`(*) ON ANDROID: HOSTS DURING YOUR WALKS`** with the opt-in switch right there (a
  big button, as in Wake Mode: `[ ] HOST A SNOWFLAKE` / `(*) HOSTING ON WALKS`) and `Shared so far: 41.2 MB`.
- **Wall breaker:** port `WallBreaker.frame(t)` 1:1 (a pure function: 9 × 34 characters, 12 s cycle, one string
  redrawn 8 times a second). The user's packets bounce off the wall, snowflakes light up behind it, the wall cracks,
  traffic slips through to Tor. Static frame (t = 10) when animations are off.
- Sections: *what is snowflake*, *why the wall can't keep up*, *is it safe to run one*, *snowflake in veilwalker*
  (frost tiers and caps, plus `Frost now: … · N min hosted`).
- Replace the iPhone-only *why only in wake mode* section with one line: "On iPhone, Snowflake hosts only in wake
  mode; Apple doesn't allow a proxy in the background."
- `* run a snowflake in your browser` → snowflake.torproject.org, and the line "made by the Tor Project, not by
  VeilWalker".

## 7. Runners Wake Mode (item 7)

For a phone in an arm band: an always-on run screen. New `WakeScreen.kt` from `WakeView.swift`, opened from the home
bar as a full-screen route.

- **Screen stays on** while it's open (`Modifier.keepScreenOn()` or `FLAG_KEEP_SCREEN_ON` on the window); system bars
  hidden (`WindowInsetsControllerCompat`, transient on swipe).
- Opening it **starts a walk** if none is running (the existing manual start, with GPS).
- **Exit is a 1-second hold** on `hold to exit` (`keep holding…` while pressed). System back is consumed
  (`BackHandler`) so a sweaty arm can't end it; TalkBack gets a custom action to exit.
- Layout over the art: `WAKE MODE` (green) and the Tor line; a huge walk clock (64 sp, violet, glow) with the walk line
  under it; one row of three stats (`steps`, `km`, `shared` in ice); the host button; spacer; hold to exit.
- **Art backdrop:** two images from the owner, anchored to the bottom (`ContentScale.Crop`, `Alignment.BottomCenter`):
  Terminal look → `WakeTerminal.png`, Glass look → `WakeGlass.png`. Source:
  `VeilWalker/Assets.xcassets/WakeTerminal.imageset/` and `WakeGlass.imageset/` (853 × 1844). Convert to WebP into
  `res/drawable-nodpi/` (`wake_terminal.webp`, `wake_glass.webp`). Panes over the art are see-through: black at 45%
  with a 1 dp outline in Terminal, glass in Glass.
- **Host button** (big, the first version was a thin line people missed):
  - Off: `[ ] HOST A SNOWFLAKE`, sub-line `help people past censorship while you walk`.
  - On and running: `(*) HOSTING A SNOWFLAKE` in green, with the status line under it.
  - First tap ever shows the explanation dialog (stored as `snowflakeHostExplained`), adapted from iPhone: relays
    already-encrypted Tor traffic for people in censored countries; they can see the phone's IP, not what you do; uses
    data, capped at 500 MB a day; only the amount shared is kept. Buttons `Host` / `Not now`.
  - Turning it on sets `hostOnWalks`. If the current walk isn't a Snowflake walk, start hosting on it now: add
    `ACTION_SNOWFLAKE_START` to `WalkService` (next to `ACTION_SNOWFLAKE_EXTEND`/`_STOP`). Turning it off stops it.
  - The 50 MB prompt in Wake Mode is an in-app dialog (`Keep going to 150 MB` / `Stop hosting`) as well as the existing
    notification.
- Status lines (from `SnowflakeStats.statusLine`): `(*) hosting · only traffic shared is kept`,
  `[?] 50 MB shared this run`, `[-] session cap reached · see you next run`,
  `[-] 500 MB shared today: resting until tomorrow`, `[x] snowflake stopped: <error>`.

## 8. Small items

- **Haptics (item 8):** a light tick on every tappable (tiles, `VeilButton`, bars, logo):
  `LocalView.current.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)`.
- **Credits (item 9):** under THE TOR PROJECT add `Pion WebRTC · MIT` and `Go · BSD-3-Clause` (both are inside the
  Snowflake AAR). If Haze is used, add `Haze · Apache-2.0` under ANDROID & KOTLIN.
- **About:** reached from the easter-egg link now; keep the 3XC art on the About screen itself.

## 9. Testing before release

- Unit: distance cap; the Tor and walk lines; `WallBreaker` frames at t = 0, 4, 10 (exact strings); byte formatting;
  caps at 50/150/500 MB decimal.
- Snowflake on a real phone, on Wi-Fi and on mobile data: host for 15–30 minutes on a walk; frost minutes accrue;
  bytes shared rises once the broker matches a client (0 for the first minutes is normal). Confirm no country or peer
  data is logged (`adb logcat | grep -i country` is empty).
- Wake Mode: the screen stays on for 10+ minutes; back does nothing; a 1 s hold exits; hosting starts and stops with
  the button.
- Both looks on a low-end device (API 28) and a recent one: scrolling and taps stay smooth; no frame drops from the
  backdrop.
- A restore from the 24-word phrase on a phone that ran 0.3.0: ledger, handle, clan and badges intact (nothing here
  should touch them; prove it).
- Upgrade test: install 0.3.0 from Play, then the 0.4.0 build over it; walks, points and prefs survive.

## 10. Play Store release checklist

- [ ] `versionCode = 4`, `versionName = "0.4.0"` in `app/build.gradle.kts`.
- [ ] AAB built and signed with the upload key; **16 KB alignment** check passes; upload native debug symbols
      (`app/build/outputs/native-debug-symbols`), which also clears the old warning.
- [ ] **Foreground services:** no new types. `specialUse` (Snowflake during walks) is already declared with the demo
      video, and now does what it says. Wake Mode only keeps the screen on (no permission). Re-check that the existing
      description still matches; if Play asks again, the video still applies.
- [ ] **Data safety:** no change. Snowflake relays other people's encrypted traffic; VeilWalker collects nothing from
      it and keeps only a byte total on the phone. Re-read the form to confirm before submitting.
- [ ] **Store listing:** the description already mentions Snowflake. Optional: new screenshots of the home grid, the
      Glass look and Wake Mode (`docs/store/screenshots/`).
- [ ] **Privacy policy page:** the Snowflake section says "only during walks". Add "or while Wake Mode is open" and
      that the Tor Project's broker and the people helped can see the phone's IP address (standard for any snowflake).
      The owner updates the Google Site; see also `docs/POLICY_IOS_CHANGES.md` for the iPhone wording, to do both at
      once.
- [ ] **Export:** Snowflake adds WebRTC/DTLS (mass-market encryption, already covered by the US export declaration;
      `docs/EXPORT_COMPLIANCE.md` has the row).
- [ ] Release notes (en-US, under 500 characters), suggested:

      New look: a home screen built around big tiles, plus a Glass look (tap the logo).
      Runners Wake Mode keeps the screen on for arm-band runs.
      Snowflake is live: host a Tor Snowflake on your walks to help people past censorship and frost your badges.
      Walk distance can no longer run ahead of your steps.

- [ ] **Staged rollout:** production is live, so roll out to 20% first, watch crashes/ANRs in Android vitals for 48 h
      (the Go runtime is new native code), then 100%.
- [ ] **Send for review: owner only.**

## 11. Done means

All Must items in §1 shipped, §9 passed on a real phone, the owner has signed off on the build, and 0.4.0 is in
staged rollout on Play.
