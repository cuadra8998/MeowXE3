#!/bin/bash
# sequoia-from-release.sh RELEASE_DIR NMXACCEL_KEXT [OUT_DIR]
#   Turns an unzipped Tahoe release (e.g. MeowXE3-1.0.12/) into a Sequoia release without rebuilding everything.
#   RELEASE_DIR    the unzipped Tahoe release folder (has payload/ and "Install MeowXE3.command")
#   NMXACCEL_KEXT  NMXAccel.kext built for macOS 15:  MEOWXE3_TARGET=15 bash tools/build/build-nmxaccel.sh
#   OUT_DIR        default: dist/  -> OUT_DIR/MeowXE3-<version>-sequoia(.zip)
#
# What it changes (checked against the 1.0.12 release):
#   1. MeowXE3Accel's executable -> the macOS 15 build (the Tahoe one has Tahoe's IOAccelerator vtable layout).
#      Its Info.plist (com.meowxe3 ids, Zink GL bundle name) is kept.
#   2. NVMTLDriver's minimum macOS 26.0 -> 15.0 with vtool. It was only built without -mmacosx-version-min: it imports
#      nothing Tahoe-only (no MTL4/residency/tensor symbols), and every other binary already allows 15.0-15.5.
#   3. The installer from this repo (knows payload/TARGET), and payload/TARGET = 15.
#   Then re-signs ad hoc and zips. Run on a Mac (vtool, codesign, PlistBuddy, ditto). Installs nothing.
set -euo pipefail
REL=$(cd "${1:?release dir}" && pwd); ACC=${2:?NMXAccel.kext built with MEOWXE3_TARGET=15}
REPO=$(cd "$(dirname "$0")/../.." && pwd); OUTD=${3:-$REPO/dist}
V=$(cat "$REL/payload/VERSION"); N=MeowXE3-$V-sequoia; OUT=$OUTD/$N; P=$OUT/payload
NEWBIN=$ACC/Contents/MacOS/NMXAccel
[ -f "$NEWBIN" ] || { echo "no $NEWBIN"; exit 1; }
OLDBIN=$REL/payload/MeowXE3.kext/Contents/PlugIns/MeowXE3Accel.kext/Contents/MacOS/MeowXE3Accel
cmp -s "$NEWBIN" "$OLDBIN" && { echo "STOP: that accelerator is the release's Tahoe build; rebuild with MEOWXE3_TARGET=15"; exit 1; }

rm -rf "$OUT" "$OUT.zip"; mkdir -p "$OUTD"; ditto "$REL" "$OUT"; find "$OUT" -name .DS_Store -delete
K=$P/MeowXE3.kext; A=$K/Contents/PlugIns/MeowXE3Accel.kext

echo "== accelerator: macOS 15 build"
cp "$NEWBIN" "$A/Contents/MacOS/MeowXE3Accel"

echo "== NVMTLDriver: minimum macOS 15.0"
M=$P/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
SDKV=$(vtool -show-build "$M" | awk '/sdk/{print $2; exit}')
vtool -set-build-version macos 15.0 "${SDKV:-26.5}" -replace -output "$M.new" "$M" && mv "$M.new" "$M"
vtool -show-build "$M" | grep -E 'minos|sdk'

echo "== installer + TARGET"
cp "$REPO/Install MeowXE3.command" "$OUT/"; chmod +x "$OUT/Install MeowXE3.command"
echo 15 > "$P/TARGET"

echo "== re-sign (ad hoc)"
codesign -f -s - "$P/GPUBundles/NVMTLDriver.bundle" 2>&1 | grep -v "replacing existing" || true
codesign -f -s - "$A" 2>&1 | grep -v "replacing existing" || true
codesign -f -s - "$K" 2>&1 | grep -v "replacing existing" || true
codesign -v "$P/GPUBundles/NVMTLDriver.bundle" && codesign -v --deep "$K"

echo "== everything must allow macOS 15.5 or older"
BAD=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q Mach-O || continue
  m=$(vtool -show-build "$f" 2>/dev/null | awk '/minos|version /{print $2; exit}' || true)
  [ -n "$m" ] || continue
  [ "$(printf '%s\n15.5\n' "$m" | sort -t. -k1,1n -k2,2n | tail -1)" = 15.5 ] || { echo "  TOO NEW ($m): ${f#$P/}"; BAD=1; }
done < <(find "$K" "$P/GPUBundles" -type f -print0)
[ "$BAD" = 0 ] || { echo "STOP"; exit 1; }

(cd "$OUTD" && ditto -c -k --keepParent "$N" "$N.zip")
ls -lh "$OUT.zip"; shasum -a 256 "$OUT.zip"
echo "done: test on a spare Sequoia 15.5+ volume (docs/SEQUOIA.md)"
