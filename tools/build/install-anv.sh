#!/bin/bash
# install-anv.sh [restore]: puts the ANV built from Mesa bffd91947ef + NullMoth's mesa-macos.patch + ericek111's 8 Mesa
# patches (+ our 0009) in place of NullMoth 2.0.2's prebuilt libvulkan_intel.dylib, which stays as .prebuilt.
set -e
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
D=/Library/GPUBundles/nvmtl
if [ "${1:-}" = restore ]; then cp $D/libvulkan_intel.dylib.prebuilt $D/libvulkan_intel.dylib; echo "prebuilt ANV restored"; exit 0; fi
[ -f $D/libvulkan_intel.dylib.prebuilt ] || cp $D/libvulkan_intel.dylib $D/libvulkan_intel.dylib.prebuilt
install -m 755 -o root -g wheel ${NMX:-$HOME/nmx}/src/mesa-build/src/intel/vulkan/libvulkan_intel.dylib $D/libvulkan_intel.dylib
install_name_tool -id $D/libvulkan_intel.dylib $D/libvulkan_intel.dylib
codesign -f -s - $D/libvulkan_intel.dylib
ls -l $D/libvulkan_intel.dylib*
echo ANV-INSTALLED
