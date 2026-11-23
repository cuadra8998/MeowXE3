#!/bin/bash
# make-release.sh VERSION PACKAGE_DIR SAFE_EFI: builds dist/MeowXE3-VERSION.zip for a GitHub release.
#   PACKAGE_DIR  the built MeowXE3 folder (MeowXE3.kext, GPUBundles, firmware, OpenCore, install-meowxe3.sh)
#   SAFE_EFI     NullMothSafe.efi (NullMoth's app/efi-safe), the "start once without driver" picker tool
# MEOWXE3_TARGET=15 makes the Sequoia release (MeowXE3-VERSION-sequoia.zip); payload/TARGET tells the installer which
# macOS the payload was built for.
# The zip holds: Install MeowXE3.command, README.md, LICENSE notes, payload/ (everything the installer copies).
set -euo pipefail
V=${1:?version}; PKG=${2:?package dir}; SAFE=${3:?NullMothSafe.efi}
TARGET=${MEOWXE3_TARGET:-26}; case $TARGET in 26) N=MeowXE3-$V;; 15) N=MeowXE3-$V-sequoia;; *) echo "MEOWXE3_TARGET must be 15 or 26"; exit 1;; esac
REPO=$(cd "$(dirname "$0")/../.." && pwd); OUT=$REPO/dist/$N; P=$OUT/payload
rm -rf "$OUT" "$OUT.zip"; mkdir -p "$P/tools"
for x in MeowXE3.kext GPUBundles firmware OpenCore install-meowxe3.sh; do ditto "$PKG/$x" "$P/$x"; done
cp "$SAFE" "$P/OpenCore/NullMothSafe.efi"
cp "$REPO/tools/oc-patch.sh" "$REPO/tools/allow-app.sh" "$P/tools/"
echo "$V" > "$P/VERSION"; echo "$TARGET" > "$P/TARGET"
cp "$REPO/Install MeowXE3.command" "$REPO/README.md" "$REPO/NOTICE.md" "$OUT/"
cp "$PKG/MeowXE3.kext/Contents/Resources/LICENSE-NullMoth.md" "$OUT/"
find "$OUT" -name .DS_Store -delete
chmod +x "$OUT/Install MeowXE3.command" "$P/install-meowxe3.sh" "$P/tools/"*.sh
codesign -v "$P/MeowXE3.kext" && codesign -v "$P/GPUBundles/NVMTLDriver.bundle"
(cd "$REPO/dist" && ditto -c -k --keepParent "$N" "$N.zip")
ls -lh "$OUT.zip"; shasum -a 256 "$OUT.zip"
