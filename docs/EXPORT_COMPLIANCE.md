# Encryption export compliance (App Store)

**Status:** the owner approved step 1 on 31 Oct 2026: `ITSAppUsesNonExemptEncryption = YES` is in Info.plist.
Steps 2–5 (App Store Connect answers, the BIS/NSA report, France, counsel review) are still to do. Not legal advice:
this lists what the iOS build actually does with cryptography and the recommended path.

## What the app does with cryptography

| Where | What | Purpose | Implementation |
|---|---|---|---|
| Tor (always on by default) | TLS 1.2/1.3 (AES-GCM, ChaCha20-Poly1305, X25519), Tor circuit crypto (ntor handshake with X25519, AES-128-CTR, SHA-1/SHA-256/SHA3), onion-service keys (Ed25519) | **Confidentiality** of all API traffic and the weather lookup | Arti 0.47 + rustls + ring, compiled into the app (not Apple's OS crypto) |
| Weather over a Tor exit | TLS to api.weather.gov | Confidentiality | rustls + ring, webpki-roots |
| Tor turned off by the user | HTTPS | Confidentiality | Apple URLSession (OS-provided) |
| Account | BIP39 seed (PBKDF2-HMAC-SHA512), SLIP-0010 key derivation (HMAC-SHA512), Ed25519 signatures on every request | Authentication | CommonCrypto, CryptoKit (OS-provided) |
| Ledger | SHA-256 hash chain, Ed25519 server signatures checked on the phone | Integrity, authentication | CryptoKit |

All algorithms are standard and published; there is no proprietary or non-standard cryptography. The Tor, rustls and
ring source code is publicly available (MIT / Apache-2.0 / ISC). The VeilWalker app itself is not open source.

## Why the simple "exempt" answer doesn't fit

Apple's exemptions cover encryption used only for authentication, or only through Apple's own OS frameworks. Tor
encrypts the content of communications with its own (non-Apple) implementation, which puts the app outside those
exemptions. So the honest answer to "does your app use non-exempt encryption" is **yes**.

## Recommended path

1. ~~Set `ITSAppUsesNonExemptEncryption = YES` in Info.plist.~~ Done.
2. In App Store Connect, answer that the app uses **standard** encryption algorithms, not proprietary ones, in addition
   to Apple's. That classifies it as mass-market software (ECCN **5D992.c**, License Exception ENC §740.17(b)(1)).
3. File the **annual self-classification report** with BIS and the NSA ENC Encryption Request Coordinator. It's a
   short spreadsheet, due by **1 February** for the previous calendar year's first exports.
4. **France:** Apple asks for an ANSSI encryption declaration for apps with non-exempt encryption sold in France.
   The handoff says US first, so leave France out of the first release's territories until that's filed.
5. Have export counsel glance at steps 2–4 before the first submission. It's a well-trodden path (most Tor/VPN
   apps take it), but it's your declaration, not mine.

## Facts to have ready

- Encryption purpose: privacy of communications (anonymity network) and authentication.
- Key lengths: 128- and 256-bit symmetric, X25519 / Ed25519.
- Distribution: free, App Store, consumer.
- Source: Arti at gitlab.torproject.org/tpo/core/arti; rustls; ring.
