#!/bin/bash
# install-translator.sh [restore]: puts the Metal->Vulkan translator built with ericek's GL fixes (0031/0032) into the
# installed Metal driver, keeping the previous one as libnvmtl_translate.dylib.prev OUTSIDE the bundle (in
# /Library/GPUBundles/nvmtl-backup/) so the bundle's signature stays valid. Apps pick it up when they relaunch.
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
B=/Library/GPUBundles/NVMTLDriver.bundle; M=$B/Contents/MacOS; K=/Library/GPUBundles/nvmtl-backup; mkdir -p $K
if [ "${1:-}" = restore ]; then
  [ -f $K/libnvmtl_translate.dylib.prev ] || { echo "no backup"; exit 1; }
  cp $K/libnvmtl_translate.dylib.prev $M/.xlate.new && mv -f $M/.xlate.new $M/libnvmtl_translate.dylib
else
  [ -f $K/libnvmtl_translate.dylib.prev ] || cp $M/libnvmtl_translate.dylib $K/libnvmtl_translate.dylib.prev
  # a new file renamed into place: processes that have the old one mapped keep it (cp would overwrite it under them)
  cp ${NMX:-$HOME/nmx}/src/xlate-out/libnvmtl_translate.dylib $M/.xlate.new && mv -f $M/.xlate.new $M/libnvmtl_translate.dylib
fi
chown root:wheel $M/libnvmtl_translate.dylib; chmod 755 $M/libnvmtl_translate.dylib
codesign -f -s - $B 2>&1 | grep -v "replacing existing" ; codesign -v $B && echo "bundle signature ok"
shasum -a256 $M/libnvmtl_translate.dylib | cut -c1-12; echo TRANSLATOR-${1:-INSTALLED}
