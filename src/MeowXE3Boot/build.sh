#!/bin/bash
# build.sh <out>: MeowXE3Boot.kext
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd); OUT=$1; K="$OUT/MeowXE3Boot.kext"; rm -rf "$K"; mkdir -p "$K/Contents/MacOS"
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
xcrun clang++ -arch x86_64 -mmacosx-version-min=15.0 -fapple-kext -mkernel -nostdinc -I"$KHDR" -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
  -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common -Wall -Wno-inconsistent-missing-override -Wno-deprecated-declarations -O2 \
  -c "$D/MeowXE3Boot.cpp" -o "$OUT/meowxe3boot.o" || exit 1
xcrun clang++ -arch x86_64 -mmacosx-version-min=15.0 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext "$OUT/meowxe3boot.o" \
  -o "$K/Contents/MacOS/MeowXE3Boot" || exit 1
cp "$D/Info.plist" "$K/Contents/Info.plist" && plutil -lint "$K/Contents/Info.plist" >/dev/null || exit 1
codesign -f -s - "$K" 2>/dev/null
echo "MeowXE3Boot $(stat -f %z "$K/Contents/MacOS/MeowXE3Boot") B"
