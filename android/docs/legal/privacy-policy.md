# VeilWalker Privacy Policy

*Effective: October 28, 2026 · DRAFT pending legal review*

VeilWalker ("we") is a walking app built to count your steps without watching you. This policy explains exactly what the app handles and why.

## The short version

- **No accounts in the usual sense.** No name, email, phone number or password. Your account is a 24-word recovery phrase that only you hold.
- **Your movement data stays on your phone.** Step counts, motion-sensor readings and GPS are processed on the device. Raw motion and GPS data never leave it and are deleted after 30 days.
- **We never sell, rent or share your data.** No ads, no trackers, no analytics SDKs.
- **Tor by default.** The app talks to our server over the Tor network unless you turn that off.

## What the app processes on your phone only

| Data | Why | Kept |
|---|---|---|
| Step counts from your phone's step sensor | Counting steps, routes, badges | On device |
| Accelerometer and gyroscope readings during walks | Telling real walking from fake movement (anti-cheat) | Deleted after 30 days |
| GPS location during walks | Verifying outdoor walks, measuring stride | Deleted after 30 days; never uploaded |
| Physical activity recognition (Android) | Starting walks automatically | Not stored |
| Barometer (air pressure) during walks | Measuring real hills you climb, for Hidden Peaks | Only the climb total is kept, on device |

## What leaves your phone

Only what's needed to issue points:

- **Daily step totals by type** (passive, walk, GPS-verified, over Tor) and an **anti-cheat score**, signed with your device key.
- Your **public key** (a random identifier generated on your phone), your chosen **handle**, optional **clan tag**, and **badge unlocks**.
- If you turn on backup: an **encrypted backup** that only your 24 words can decrypt. We can't read it.

We never receive your name, contacts, precise location, GPS traces, sensor readings or device identifiers.

## Weather

To show the outside temperature, the app sends your **approximate location** (your last known position rounded to about 11 km) directly to the US National Weather Service (api.weather.gov). It goes over Tor when Tor is on, so the Weather Service doesn't see your IP address either. We never receive this location, and the app keeps only the last temperature, not the location. Weather is **off by default**: it only runs if you turn it on (home screen or Account) and have granted location permission. Turn it off and nothing is sent, and the last reading is deleted.

## Network and IP addresses

With Tor on (the default), our server can't see your IP address. With Tor off, the app uses HTTPS. Our server software does not log IP addresses, but our hosting provider (Railway) may process connection data briefly to deliver traffic.

## Snowflake (optional)

If you turn on Snowflake hosting, your phone relays encrypted traffic for people reaching the Tor network from censored countries, only during walks and within data caps you control. Nothing about what is relayed is visible to you or to us. Hosting earns status badges only, never points or money.

## Points

Points have no cash value, can't be transferred between users and never expire. Each point record is signed by our server and stored on your phone, so you can verify your own balance.

## Your rights and choices

- **Withdraw consent / delete your account** at any time in the app: *@ account → Delete account*. This deletes your synced data from our server and all VeilWalker data on your phone. Your handle stays reserved so no one else can impersonate it. Signed point records may be retained in de-identified form (linked only to a public key no longer tied to you) for ledger integrity.
- **Access your data:** everything we hold is visible in the app or derivable from your recovery phrase. Contact us for a copy.
- **California (CCPA/CPRA), Washington (My Health My Data Act), Nevada, Connecticut and similar laws:** we don't sell or share personal information or consumer health data. See our [Consumer Health Data Policy](health-data).

## Children

VeilWalker isn't for children under 13. We don't knowingly collect data from them.

## Changes

If we change this policy materially, the app will ask for your consent again.

## Contact

premiselayer@gmail.com
