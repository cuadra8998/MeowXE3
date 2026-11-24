#!/bin/bash
# install-accel.sh [NMXAccel.kext | --restore]: puts a freshly built accelerator's executable into the installed
# /Library/Extensions/MeowXE3Accel.kext (its Info.plist, com.meowxe3 ids and Zink GL name are kept), re-signs it ad hoc
# and waits until the auxiliary kernel collection holds that exact build. The kext it replaces is kept in
# /Library/NullMoth/accel-backup and --restore puts it back the same way. Restart afterwards.
#   MEOWXE3_TARGET=15 bash tools/build/build-nmxaccel.sh ~/nmx/src/nmxaccel-out-15-test
#   sudo bash tools/build/install-accel.sh ~/nmx/src/nmxaccel-out-15-test/NMXAccel.kext
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0 $*"; exit 1; }
E=/Library/Extensions; A=$E/MeowXE3Accel.kext; K=$E/MeowXE3.kext; G=$E/MeowXE3AGDC.kext; BK=/Library/NullMoth/accel-backup
[ -d $A ] && [ -d $K ] || { echo "MeowXE3 is not installed (no $A): run the MeowXE3 installer first"; exit 1; }
if [ "${1:-}" = --restore ]; then
  [ -d $BK/MeowXE3Accel.kext ] || { echo "no backup in $BK"; exit 1; }
  rm -rf $A && cp -R $BK/MeowXE3Accel.kext $E/ || { echo "restore copy failed"; exit 1; }
  echo "restored the accelerator from $BK"
else
  NEW=${1:?usage: sudo bash $0 path/to/NMXAccel.kext  (or --restore)}/Contents/MacOS/NMXAccel
  [ -f "$NEW" ] || { echo "no $NEW"; exit 1; }
  # same kernel imports as the installed one, or stop (FINDINGS: diff nm -u before installing)
  if ! diff <(nm -u $A/Contents/MacOS/MeowXE3Accel | sort) <(nm -u "$NEW" | sort) >/dev/null; then
    echo "the new accelerator imports different kernel symbols:"; diff <(nm -u $A/Contents/MacOS/MeowXE3Accel | sort) <(nm -u "$NEW" | sort)
    echo "not installed (check them, then set MEOWXE3_ALLOW_IMPORTS=1)"; [ "${MEOWXE3_ALLOW_IMPORTS:-0}" = 1 ] || exit 1
  fi
  mkdir -p $BK
  [ -d $BK/MeowXE3Accel.kext ] || { cp -R $A $BK/ && echo "kept the installed accelerator in $BK"; }
  cp "$NEW" $A/Contents/MacOS/MeowXE3Accel || { echo "copy failed"; exit 1; }
fi
rm -rf $A/Contents/_CodeSignature
codesign -f -s - $A 2>&1 | grep -v "replacing existing signature"
chown -R root:wheel $A && chmod -R 755 $A && codesign -v $A || exit 1
WANT=$(dwarfdump --uuid $A/Contents/MacOS/MeowXE3Accel | awk '{print $2}')
echo "accelerator build $WANT; rebuilding the auxiliary kernel collection"
kmutil load -p $K -p $A -p $G 2>&1 | tail -3
for i in $(seq 1 90); do
  HAVE=$(kmutil inspect -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --show-kext-uuids 2>/dev/null |
        awk '$1 == "com.meowxe3.MeowXE3.Accel" {gsub(/[()]/, "", $NF); print $NF}')
  if [ "$HAVE" = "$WANT" ]; then echo "ACCEL-INSTALLED: the collection holds $HAVE; restart"; exit 0; fi
  sleep 2
done
echo "the collection holds accelerator '${HAVE:-none}', not $WANT: do NOT restart yet; send this output"
exit 1
