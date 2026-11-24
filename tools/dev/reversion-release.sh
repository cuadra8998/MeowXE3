#!/bin/bash
# reversion-release.sh RELEASE_DIR VERSION [OUT_DIR]
#   Re-issues an unzipped release (Tahoe or -sequoia) under a new version without rebuilding any binary, for releases
#   where only the installer, docs or packaging changed.
#   RELEASE_DIR  an unzipped release folder (has payload/ and "Install MeowXE3.command"); payload/TARGET picks the name
#   VERSION      the new version, e.g. 1.0.13
#   OUT_DIR      default: dist/  -> OUT_DIR/MeowXE3-VERSION[-sequoia](.zip)
#
# What it changes:
#   1. payload/VERSION, and CFBundleVersion + CFBundleShortVersionString of MeowXE3.kext and its two plug-ins
#      (kmutil only rebuilds the auxiliary kernel collection when a version or binary changes).
#   2. Installer, README.md, NOTICE.md and payload scripts from this repo; payload/TARGET (26 when missing).
#   Then re-signs the kexts ad hoc and zips. Executables are untouched apart from the new ad hoc signature.
#   Run on a Mac (codesign, PlistBuddy, ditto). Installs nothing.
set -euo pipefail
REL=$(cd "${1:?release dir}" && pwd); V=${2:?new version}
REPO=$(cd "$(dirname "$0")/../.." && pwd); OUTD=${3:-$REPO/dist}; PB=/usr/libexec/PlistBuddy
TARGET=$(cat "$REL/payload/TARGET" 2>/dev/null || echo 26)
case $TARGET in 26) N=MeowXE3-$V;; 15) N=MeowXE3-$V-sequoia;; *) echo "payload/TARGET must be 15 or 26"; exit 1;; esac
OUT=$OUTD/$N; P=$OUT/payload; K=$P/MeowXE3.kext
OLD=$(cat "$REL/payload/VERSION")
[ "$OLD" != "$V" ] || { echo "STOP: the release is already $V"; exit 1; }

rm -rf "$OUT" "$OUT.zip"; mkdir -p "$OUTD"; ditto "$REL" "$OUT"; find "$OUT" -name .DS_Store -delete
# executables before, to prove nothing but the signature changed
sums() { find "$K" "$P/GPUBundles" -type f -path '*/MacOS/*' -print0 | sort -z |
  while IFS= read -r -d '' f; do printf '%s %s\n' "$(dwarfdump --uuid "$f" 2>/dev/null | awk '{print $2}' | tr '\n' ,)" "${f#$P/}"; done; }
BEFORE=$(sums)

echo "== $OLD -> $V (macOS $TARGET)"
echo "$V" > "$P/VERSION"; echo "$TARGET" > "$P/TARGET"
for k in "$K" "$K"/Contents/PlugIns/*.kext; do
  $PB -c "Set :CFBundleVersion $V" -c "Set :CFBundleShortVersionString $V" "$k/Contents/Info.plist"
done

echo "== installer, docs and scripts from the repo"
cp "$REPO/Install MeowXE3.command" "$REPO/README.md" "$REPO/NOTICE.md" "$OUT/"
cp "$REPO/tools/install-meowxe3.sh" "$P/install-meowxe3.sh"
cp "$REPO/tools/oc-patch.sh" "$REPO/tools/allow-app.sh" "$P/tools/"
chmod +x "$OUT/Install MeowXE3.command" "$P/install-meowxe3.sh" "$P/tools/"*.sh

echo "== re-sign (ad hoc)"
find "$K" -name _CodeSignature -type d -prune -exec rm -rf {} +
for k in "$K"/Contents/PlugIns/*.kext "$K"; do codesign -f -s - "$k" 2>&1 | grep -v "replacing existing" || true; done
codesign -v --deep "$K" && codesign -v "$P/GPUBundles/NVMTLDriver.bundle"

echo "== check"
[ "$(sums)" = "$BEFORE" ] || { echo "STOP: an executable's UUID changed"; diff <(echo "$BEFORE") <(sums); exit 1; }
for k in "$K" "$K"/Contents/PlugIns/*.kext; do
  printf '  %-14s %s\n' "$($PB -c 'Print :CFBundleExecutable' "$k/Contents/Info.plist")" "$($PB -c 'Print :CFBundleVersion' "$k/Contents/Info.plist")"
done
bash -n "$OUT/Install MeowXE3.command"

(cd "$OUTD" && ditto -c -k --keepParent "$N" "$N.zip")
ls -lh "$OUT.zip"; shasum -a 256 "$OUT.zip"
