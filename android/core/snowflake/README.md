# Snowflake proxy AAR

Build the Tor Project's Snowflake proxy for Android with gomobile, then drop it in `libs/`.

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
git clone https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake.git
cd snowflake
# Small Go wrapper package exposing Start/Pause/Resume/Stop/BytesRelayed is recommended
# (Orbot's IPtProxy project is a good reference for this).
gomobile bind -target=android -androidapi 28 -o snowflake.aar ./mobile
```

Then uncomment `implementation(files("libs/snowflake.aar"))` in `build.gradle.kts` and fill in `SnowflakeEngine`.

Caps (enforced in `SnowflakeController`): ask at 50 MB, stop at 150 MB per walk, and 500 MB per day.
