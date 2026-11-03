#!/bin/sh
# Builds core/snowflake/libs/vwflake.aar from the same Go wrapper the iPhone uses (../ios/snowflake/vwflake, the
# Tor Project's Snowflake v2 proxy) with gomobile. Needs Go and the Android NDK (ANDROID_NDK_HOME).
# -s -w strips debug info (~32 MB a CPU type otherwise). Native code is linked for 16 KB pages (Play requires it on Android 15+). -checklinkname=0: Pion's Android network
# helper (github.com/wlynxg/anet) links to Go internals that Go 1.23+ blocks by default; Android-only.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/../ios/snowflake/vwflake"
export GOPATH="$ROOT/.build/go" GOMODCACHE="$ROOT/.build/go/mod" PATH="$PATH:$ROOT/.build/go/bin"
cd "$SRC"
go install golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind
gomobile init
mkdir -p "$ROOT/core/snowflake/libs"
gomobile bind -target android -androidapi 28 -javapkg org.trailbound.flake \
  -ldflags='-s -w -checklinkname=0 -extldflags=-Wl,-z,max-page-size=16384' \
  -o "$ROOT/core/snowflake/libs/vwflake.aar" .
echo "== built $ROOT/core/snowflake/libs/vwflake.aar"
