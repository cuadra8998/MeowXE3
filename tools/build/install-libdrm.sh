#!/bin/bash
# install-libdrm.sh: puts the libdrm built with ericek111's 5 Darwin patches (b97cbde + NullMoth's libdrm-macos.patch)
# in place of NullMoth 2.0.2's prebuilt copy under the Metal plugin; the prebuilt one is kept as libdrm.2.dylib.prebuilt.
set -e
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
D=/Library/GPUBundles/nvmtl
[ -f $D/libdrm.2.dylib.prebuilt ] || cp $D/libdrm.2.dylib $D/libdrm.2.dylib.prebuilt
install -m 755 -o root -g wheel ${NMX:-$HOME/nmx}/src/libdrm/build/libdrm.2.dylib $D/libdrm.2.dylib
codesign -f -s - $D/libdrm.2.dylib 2>/dev/null || true
ls -l $D/libdrm.2.dylib*
echo LIBDRM-INSTALLED
