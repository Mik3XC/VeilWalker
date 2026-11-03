# Play Console checklist: VeilWalker (Premise-i3, app 4975673617183940599)

## Done (2026-10-28)
- [x] App created: "VeilWalker: Private Step Walks", com.premisei3.veilwalker, free; policy + US export declarations accepted
- [x] Production release draft: version 1 (0.1.0), AAB uploaded (all ABIs), release notes, Play App Signing on
- [x] Privacy policy URL: https://sites.google.com/view/veilwalker-app/privacy
- [x] Ads: no ads · App access: no restricted parts · Advertising ID: not used
- [x] Government apps: no · Financial features: none · Health apps: Activity and fitness
- [x] Target audience: 13–15, 16–17, 18+
- [x] Content rating (IARC): ESRB Everyone, PEGI 3, USK all ages, ClassInd all ages, IARC 3+

- [x] Data safety: User IDs (required; app functionality + account management), Fitness info (required; app functionality),
      Other user-generated content (optional; app functionality); collected, not shared, not ephemeral; encrypted in transit;
      key-based account; delete URL set
- [x] Default store listing: short + full description, icon, feature graphic, 6 phone screenshots
- [x] Store settings: Health & Fitness; contact premiselayer@gmail.com; website = Google Site
- [x] Production countries: United States (+7 territories)

## 0.4.0 (versionCode 4) release, prepared 2026-11-03

Built from branch `android-0.4.0`; bundle at `dist/VeilWalker-0.4.0.aab` (32 MB, upload key CN=3XCypher; each phone
downloads only its own CPU type). 64-bit native libraries checked for 16 KB pages. 0.3.0 is live in production.

- [ ] **Snowflake hosting walk** on a real phone (15–30 min, Wake Mode → Host): shared counter rises once the broker
      matches a client, frost minutes accrue, `adb logcat | grep -i country` is empty
- [ ] **Privacy page** (Google Site, Snowflake section): replace the paragraph with the new text in
      `docs/legal/privacy-policy.md` (Wake Mode, IP visible to the broker and the people helped, only a byte total kept)
- [ ] Upload `dist/VeilWalker-0.4.0.aab` to a new production release (owner; over the 10 MB browser limit)
- [ ] Foreground services: no new types. specialUse (Snowflake during walks) now really runs; the existing description
      and video still apply. If Play asks again, open the form **from the release** (…?releaseId=…&trackId=…)
- [ ] Data safety: no change (Snowflake relays others' encrypted traffic; only a byte total is kept on the phone)
- [ ] Debug symbols warning: stays. Arti and the Go library ship stripped (unstripped Go is ~30 MB more a CPU type);
      not a review blocker
- [ ] Release notes (en-US):

      New look: a home screen built around big tiles, plus a Glass look (tap the logo).
      Runners Wake Mode keeps the screen on for arm-band runs.
      Snowflake is live: host a Tor Snowflake on your walks to help people past censorship and frost your badges.
      Walk distance can no longer run ahead of your steps.

- [ ] **Staged rollout 20%**, watch Android vitals (crashes/ANRs; the Go runtime is new native code) for 48 h, then 100%
- [ ] **Send for review: owner only**

## Remaining
- [ ] **Foreground service permissions** (app-content/foreground-services): list was still empty after upload (Google
      processing the bundle). When it appears, declare and describe:
      - health: "Counts steps and reads motion sensors during a walk the user is on; shown in an ongoing notification"
      - location: "Measures distance and verifies outdoor walks during an active walk; GPS stays on the device"
      - specialUse: "Optional Tor Snowflake volunteer proxy, only during a user's walk, user opt-in, data-capped"
      Video (unlisted, Premise-i3 channel): **https://www.youtube.com/watch?v=kxZ1JlSFsSY**
      (local copy dist/VeilWalker-fgs-demo.mp4; other notifications blurred). 2026-10-29: 0.3.0 (versionCode 3) replaced 0.1.0 in the production draft; the list still shows only a loading bar. DONE 2026-10-29: the list only loads when opened from the release (foreground-services?releaseId=1&trackId=...). Declared health = step counter/exercise tracker, location = other background location updates, specialUse = Other (Snowflake), all with the video.
- [x] Health declaration: the release-scoped form has a 'Health data permissions' step (ACTIVITY_RECOGNITION description) that the general page never showed; filled and saved 2026-10-29
- [ ] Release review error "You must complete the health declaration": Health apps form is saved (Activity and fitness);
      re-check after the FGS declaration, it may be the same blocker
- [ ] Optional warning: upload native debug symbols (app/build/outputs/native-debug-symbols)
- [ ] Publishing overview → **Send for review**

## Old notes
- [ ] **Data safety** (done, kept for reference):
  - Collects data: Yes · Encrypted in transit: Yes
  - Account creation: Other — "Anonymous key-based account: 24-word recovery phrase + device key on the phone; no email, phone or password; optional public handle"
  - Delete account URL: https://sites.google.com/view/veilwalker-app/delete-account · partial deletion: No
  - Data types: **Personal info → User IDs**, **Health and fitness → Fitness info**, **App activity → Other user-generated content**
  - For each: Collected (not shared), not processed ephemerally, required, purposes: App functionality (+ Account management for User IDs)
  - Location: **Approximate location** (since the weather feature, 2026-10-29): collected + shared with the US National Weather Service, processed ephemerally, **optional (users can choose; weather is opt-in)**, purpose App functionality for both collected and shared. Precise location stays NOT declared (GPS never leaves the phone)
- [ ] **Store listing** (Grow → Store presence → Main store listing): name, short + full description from `listing.md`;
      icon `docs/brand/icon_512.png`, feature graphic `docs/store/feature-graphic.png`, phone screenshots `docs/store/screenshots/01–06.png`
- [ ] **Store settings**: category Health & Fitness, tags, contact email premiselayer@gmail.com
- [ ] **Countries/regions** for production (US first)
- [ ] **Foreground service permissions** declaration (appears after AAB upload): health (step/motion during walks),
      location (walk GPS), specialUse (Snowflake) — needs a short **video** showing a walk + Snowflake toggle
- [ ] Publishing overview → **Send for review**

## Later
- Content rating must be redone when gift-card redemptions launch (Q7 becomes Yes)
- Legal review of policies, export classification (mass-market encryption, EAR 740.17 / 5D992)
