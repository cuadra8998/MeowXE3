#!/bin/bash
# install-plugin.sh [NVMTLDriver | --restore]: puts a freshly built Metal plugin executable into the installed
# /Library/GPUBundles/NVMTLDriver.bundle and re-signs the bundle ad hoc. The executable it replaces is kept in
# /Library/NullMoth/plugin-backup and --restore puts it back. No restart: apps get the new plugin when they are next
# opened, WindowServer at the next login (log out and back in). Then run the Metal tests in tools/tests.
#   cd ~/nmx/src/nvmd/plugin && xcrun clang ... -o ~/nmx/src/nvmtl-out/NVMTLDriver NVMTLDevice.m ...  (docs/CONTINUING.md)
#   sudo bash tools/build/install-plugin.sh ~/nmx/src/nvmtl-out/NVMTLDriver
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0 $*"; exit 1; }
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS/NVMTLDriver; BK=/Library/NullMoth/plugin-backup
[ -f $X ] || { echo "MeowXE3's Metal plugin is not installed (no $X)"; exit 1; }
if [ "${1:-}" = --restore ]; then
  [ -f $BK/NVMTLDriver ] || { echo "no backup in $BK"; exit 1; }
  cp $BK/NVMTLDriver $X || { echo "restore copy failed"; exit 1; }
  echo "restored the plugin from $BK"
else
  NEW=${1:?usage: sudo bash $0 path/to/NVMTLDriver  (or --restore)}
  [ -f "$NEW" ] && file -b "$NEW" | grep -q "Mach-O.*bundle" || { echo "$NEW is not a Mach-O bundle"; exit 1; }
  M=$(vtool -show-build "$NEW" 2>/dev/null | awk '/minos/{print $2; exit}')
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] || [ "${M%%.*}" -le 15 ] || { echo "built for macOS $M: rebuild with -mmacosx-version-min=15.0"; exit 1; }
  mkdir -p $BK
  [ -f $BK/NVMTLDriver ] || { cp $X $BK/ && echo "kept the installed plugin in $BK"; }
  cp "$NEW" $X || { echo "copy failed"; exit 1; }
fi
codesign -f -s - $B 2>&1 | grep -v "replacing existing signature"
chown -R root:wheel $B && chmod -R go-w $B && codesign -v $B || exit 1
echo "PLUGIN-INSTALLED: $(shasum -a 256 $X | cut -c1-16)…  log out and back in for WindowServer to use it"
