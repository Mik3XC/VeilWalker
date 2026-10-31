#!/bin/sh
# Builds VeilWalkerCore/Frameworks/VWFlake.xcframework (iOS device, iOS simulator, macOS) from the Tor Project's
# Snowflake source with gomobile. Needs Go (brew install go). Everything downloads and builds under .build/go.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GOPATH="$ROOT/.build/go" GOMODCACHE="$ROOT/.build/go/mod" PATH="$PATH:$ROOT/.build/go/bin"
cd "$ROOT/snowflake/vwflake"
go install golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind
gomobile init
rm -rf "$ROOT/VeilWalkerCore/Frameworks/VWFlake.xcframework"
gomobile bind -target ios,iossimulator,macos -iosversion 18.0 -o "$ROOT/VeilWalkerCore/Frameworks/VWFlake.xcframework" .
echo "== built $ROOT/VeilWalkerCore/Frameworks/VWFlake.xcframework"
