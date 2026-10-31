#!/bin/zsh
# Builds VWTor.xcframework (iOS device, iOS simulator, macOS for `swift test`) from this crate.
# Output: VeilWalkerCore/Frameworks/VWTor.xcframework (a SwiftPM binary target). Re-run after changing src/lib.rs or include/.
set -euo pipefail

CRATE_DIR=${0:A:h}
ROOT=${CRATE_DIR:h:h}
OUT=$ROOT/VeilWalkerCore/Frameworks/VWTor.xcframework
export CARGO_TARGET_DIR=$ROOT/.build/rust
export IPHONEOS_DEPLOYMENT_TARGET=18.0
export MACOSX_DEPLOYMENT_TARGET=15.0

cd $CRATE_DIR
for target in aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin; do
    echo "== $target"
    cargo build --release --locked --target $target
done

rm -rf $OUT
mkdir -p ${OUT:h}
args=()
for target in aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin; do
    args+=(-library $CARGO_TARGET_DIR/$target/release/libvw_tor.a -headers $CRATE_DIR/include)
done
xcodebuild -create-xcframework $args -output $OUT
echo "== built $OUT"
