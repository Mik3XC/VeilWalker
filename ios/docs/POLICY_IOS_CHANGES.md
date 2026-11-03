# Policy pages: changes for the iPhone app

The privacy, consumer-health-data and terms pages at sites.google.com/view/veilwalker-app were written for Android.
Before App Store review they should describe both apps. Suggested edits; the owner updates the pages.

## Fix wording that's Android-only

- "Physical activity detected by Android (walking or not)" → "Physical activity detected by your phone's motion
  sensors (Android Activity Recognition, or Apple's Core Motion on iPhone): walking or not."
- Anywhere "Android" or "Google Play" stands for "the app" → "the VeilWalker app (Android and iPhone)".
- Account deletion: say it's in the app on both platforms (iPhone: @ account → Delete account, type DELETE).

## Add what the iPhone app does differently

- **Step counts** come from Apple's Core Motion pedometer, which keeps about 7 days of history on the phone.
  VeilWalker does **not** use Apple Health (HealthKit).
- **Walks from motion history:** when the app opens, it reads Core Motion's on-device activity history (last 7 days)
  to record walks taken while it was closed. That history never leaves the phone.
- **Location:** "While Using" during walks (distance and anti-cheat). Optional "Always", only if you turn on
  hands-free walks, so the phone can notice a walk while the app is closed. GPS points stay on the phone.
- **Weather (opt-in):** location rounded to about 11 km, sent directly to the US National Weather Service, over Tor
  when Tor is on. Only the temperature is kept. Not Apple WeatherKit.
- **Live Activity:** the walk shown on the lock screen holds only step count, timer and tier; no location.
- **Background refresh:** the app may sync daily totals in the background over Tor.
- **Photos:** add-only access, used only when you save a brag card.
- **Keychain:** the recovery key is stored in the iPhone Keychain, on this device only, never iCloud-synced.

## App Store privacy label (from the handoff, for reference)

User ID (app functionality, account management); Fitness (daily step totals, app functionality); Other user content
(handle, clan); Coarse location (opt-in weather, shared with the US National Weather Service, not linked to identity,
not tracking). No tracking, so no App Tracking Transparency prompt.
