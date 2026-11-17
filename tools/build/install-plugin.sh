#!/bin/bash
# install-plugin.sh [restore]: the Metal plugin (NVMTLDriver) built from NullMoth d96eaca + ericek111's plugin patches
# + MeowXE3 0054 (no soft VRAM gate on unified memory). The previous binary is kept OUTSIDE the bundle in
# /Library/GPUBundles/nvmtl-backup/ (inside it, it broke the bundle's signature). A new file is renamed into place, so
# running apps keep the copy they have mapped; each picks up the new one when it relaunches (WindowServer: next login).
set -e
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
B=/Library/GPUBundles/NVMTLDriver.bundle; M=$B/Contents/MacOS; K=/Library/GPUBundles/nvmtl-backup; mkdir -p $K
if [ "${1:-}" = restore ]; then S=$K/NVMTLDriver.prev; else S=${NMX:-$HOME/nmx}/src/nvmtl-out/NVMTLDriver; cp $M/NVMTLDriver $K/NVMTLDriver.prev; fi
rm -f $M/NVMTLDriver.prebuilt
cp $S $M/.plugin.new && chown root:wheel $M/.plugin.new && chmod 755 $M/.plugin.new && mv -f $M/.plugin.new $M/NVMTLDriver
codesign -f -s - $B 2>&1 | grep -v "replacing existing" || true
codesign -v $B && echo "signature ok"
echo PLUGIN-${1:-INSTALLED}
