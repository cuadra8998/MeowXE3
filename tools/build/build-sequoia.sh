#!/bin/bash
# build-sequoia.sh VERSION SAFE_EFI: the macOS 15 Sequoia release, built on the Tahoe dev machine from the same tree.
#
# Only one binary differs from the Tahoe release: the accelerator (MeowXE3Accel), built without NM_TAHOE, exactly as
# NullMoth's accel_build_all.sh makes its macOS 15 NVAccel. Everything else is already built for macOS 15:
#   NMXGPU (xkpi cc*.sh)            -mmacosx-version-min=15.0, link-checked upstream against 15.8.1's kernel collections
#   Mesa ANV / libdrm / audio       15.0       Zink + CGL bridge   15.5      MeowXE3Boot / NMXAccel   15.0 (this branch)
# This script refuses to package anything whose minimum macOS is newer than 15.5, so a binary built with the default
# (macOS 26) deployment target is caught here instead of failing to load on Sequoia.
#
# Needs: the Tahoe package already built in ~/nmx/MeowXE3 (tools/dev/repack.sh), the NullMoth tree in ~/nmx/src/nvmd.
# Writes: ~/nmx/src/nmxaccel-nmxgpu-15/NMXAccel.kext, ~/nmx/MeowXE3-sequoia/, dist/MeowXE3-VERSION-sequoia.zip
# Does not install or change anything on this Mac.
set -euo pipefail
V=${1:?usage: build-sequoia.sh VERSION SAFE_EFI   (VERSION: bump it, e.g. 1.0.13)}; SAFE=${2:?NullMothSafe.efi}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
NMX=${NMX:-$HOME/nmx}; TAHOE_PKG=$NMX/MeowXE3; PKG=$NMX/MeowXE3-sequoia; ACC=$NMX/src/nmxaccel-nmxgpu-15
MAXMIN=15.5

[ -d "$TAHOE_PKG/GPUBundles" ] || { echo "no Tahoe package in $TAHOE_PKG: build it first (tools/dev/repack.sh)"; exit 1; }

echo "== 1/4 MeowXE3Accel for macOS 15 (no NM_TAHOE)"
MEOWXE3_TARGET=15 bash "$REPO/tools/build/build-nmxaccel.sh" "$ACC"
# The accelerator talks to NMXGPU through a shared VRAM/flip ABI: build both accelerators from the same tree as NMXGPU,
# or the desktop stays black (NullMoth issue #51). Warn when the Tahoe accelerator is older than the source.
SRCNEW=$(find "$NMX/src/nvmd/kexts/NVRM/accel" -newer "$NMX/src/nmxaccel-nmxgpu/NMXAccel.kext/Contents/MacOS/NMXAccel" -name '*.[ch]*' 2>/dev/null | head -1 || true)
[ -z "$SRCNEW" ] || echo "  note: accel source changed after the Tahoe accelerator was built ($SRCNEW); rebuild that one too"

echo "== 2/4 package folder $PKG (copy of the Tahoe package, accelerator swapped)"
rm -rf "$PKG"; ditto "$TAHOE_PKG" "$PKG"
cp "$REPO/tools/dev/repack.sh" "$PKG/repack.sh"
MEOWXE3_ACCEL=$ACC bash "$PKG/repack.sh" "$V"

echo "== 3/4 every binary must load on macOS $MAXMIN"
# minimum macOS of a Mach-O: LC_BUILD_VERSION minos, or LC_VERSION_MIN_MACOSX version
minos() { otool -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION/{b=1} /LC_VERSION_MIN_MACOSX/{m=1} b&&/minos/{print $2; exit} m&&/ version/{print $2; exit}' || true; }
newer() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }
BAD=0; N=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  m=$(minos "$f"); N=$((N+1))
  if [ -z "$m" ]; then echo "  ?? no minimum version: ${f#$PKG/}"
  elif newer "$m" "$MAXMIN"; then echo "  TOO NEW ($m): ${f#$PKG/}"; BAD=1; fi
done < <(find "$PKG/MeowXE3.kext" "$PKG/GPUBundles" -type f -print0)
[ "$BAD" = 0 ] || { echo "STOP: rebuild the files above with -mmacosx-version-min=15.0 (see docs/SEQUOIA.md)"; exit 1; }
echo "  $N Mach-O files, all load on macOS $MAXMIN or older"
# the accelerator must be the macOS 15 build: the Tahoe one carries Tahoe's forwarded vtable slots
cmp -s "$ACC/NMXAccel.kext/Contents/MacOS/NMXAccel" "$NMX/src/nmxaccel-nmxgpu/NMXAccel.kext/Contents/MacOS/NMXAccel" &&
  { echo "STOP: the macOS 15 accelerator is identical to the Tahoe one; NM_TAHOE was not dropped"; exit 1; }

echo "== 4/4 release zip"
MEOWXE3_TARGET=15 bash "$REPO/tools/dev/make-release.sh" "$V" "$PKG" "$SAFE"
echo "SEQUOIA BUILD $V DONE: dist/MeowXE3-$V-sequoia.zip (test on a spare Sequoia volume first; docs/SEQUOIA.md)"
