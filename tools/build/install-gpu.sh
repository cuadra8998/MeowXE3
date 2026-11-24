#!/bin/bash
# install-gpu.sh [NMXGPU.kext | --restore]: puts a freshly built NMXGPU executable into the installed
# /Library/Extensions/MeowXE3.kext (its Info.plist and com.meowxe3 ids are kept), re-signs it ad hoc
# and waits until the auxiliary kernel collection holds that exact build. The kext it replaces is kept in
# /Library/NullMoth/gpu-backup and --restore puts it back the same way. Restart afterwards.
#   NULLMOTH_BUILD_ROOT=~/nmx ~/nmx/build/gpu-src/xkpi/build-guest.sh all ~/nmx/out  (patches/nmxgpu/setup-nmxgpu-wcl.sh first)
#   sudo bash tools/build/install-gpu.sh ~/nmx/out/NMXGPU.kext   (escape hatch: the OpenCore entry "start once without driver")
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0 $*"; exit 1; }
E=/Library/Extensions; A=$E/MeowXE3.kext; K=$E/MeowXE3Accel.kext; G=$E/MeowXE3AGDC.kext; BK=/Library/NullMoth/gpu-backup
[ -d $A ] && [ -d $K ] || { echo "MeowXE3 is not installed (no $A or $K): run the MeowXE3 installer first"; exit 1; }
if [ "${1:-}" = --restore ]; then
  [ -d $BK/MeowXE3.kext ] || { echo "no backup in $BK"; exit 1; }
  rm -rf $A && cp -R $BK/MeowXE3.kext $E/ || { echo "restore copy failed"; exit 1; }
  echo "restored the GPU driver from $BK"
else
  NEW=${1:?usage: sudo bash $0 path/to/NMXGPU.kext  (or --restore)}/Contents/MacOS/NMXGPU
  [ -f "$NEW" ] || { echo "no $NEW"; exit 1; }
  # same kernel imports as the installed one, or stop (FINDINGS: diff nm -u before installing)
  if ! diff <(nm -u $A/Contents/MacOS/MeowXE3 | sort) <(nm -u "$NEW" | sort) >/dev/null; then
    echo "the new GPU driver imports different kernel symbols:"; diff <(nm -u $A/Contents/MacOS/MeowXE3 | sort) <(nm -u "$NEW" | sort)
    echo "not installed (check them, then set MEOWXE3_ALLOW_IMPORTS=1)"; [ "${MEOWXE3_ALLOW_IMPORTS:-0}" = 1 ] || exit 1
  fi
  mkdir -p $BK
  [ -d $BK/MeowXE3.kext ] || { cp -R $A $BK/ && echo "kept the installed GPU driver in $BK"; }
  cp "$NEW" $A/Contents/MacOS/MeowXE3 || { echo "copy failed"; exit 1; }
fi
rm -rf $A/Contents/_CodeSignature
codesign -f -s - $A 2>&1 | grep -v "replacing existing signature"
chown -R root:wheel $A && chmod -R 755 $A && codesign -v $A || exit 1
WANT=$(dwarfdump --uuid $A/Contents/MacOS/MeowXE3 | awk '{print $2}')
echo "GPU driver build $WANT; rebuilding the auxiliary kernel collection"
kmutil load -p $A -p $K -p $G 2>&1 | tail -3
for i in $(seq 1 90); do
  HAVE=$(kmutil inspect -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --show-kext-uuids 2>/dev/null |
        awk '$1 == "com.meowxe3.MeowXE3" {gsub(/[()]/, "", $NF); print $NF}')
  if [ "$HAVE" = "$WANT" ]; then echo "GPU-INSTALLED: the collection holds $HAVE; restart"; exit 0; fi
  sleep 2
done
echo "the collection holds GPU driver '${HAVE:-none}', not $WANT: do NOT restart yet; send this output"
exit 1
