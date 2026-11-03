# trailbound-net (embedded Arti)

Builds `libtrailbound_net.so` for the Android app. Kotlin side: `core/net/.../arti/ArtiNative.kt`.

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
# ANDROID_NDK_HOME should point at %LOCALAPPDATA%\Android\Sdk\ndk\<version>
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 --platform 28 -o ../../app/src/main/jniLibs build --release
```

Notes
- Week-1 spike: confirm onion-service client connections work on a real device (S26 Edge first).
- The SOCKS listener only binds 127.0.0.1. Other apps on the device could still use it, so a per-session auth token is a TODO.
- Arti's state dir lives in app `filesDir`, so warm starts reuse guards and the directory cache.
