#!/bin/bash
# install-compositing.sh [restore]: the GPU-compositing test set beside NMXGPU: NMXAccel built from NullMoth 2.0.2 +
# ericek111's 12 NMXAccel patches + our 0048 (arms NMXGPU's NMXIntelGPUFB as head 0), and NMXAGDC (ericek's, from
# NullMoth's NVRMAGDC + our 0049), both into /Library/Extensions and the Auxiliary KC; the Metal plugin's allow list
# gets WindowServer and the test programs. restore: NullMoth 2.0.2's prebuilt NMXAccel back, NMXAGDC removed, the
# allow list back to the test programs only. Run with sudo.
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
[ -d /Library/Extensions/MeowXE3.kext ] && { echo "MeowXE3 is installed: this old test script would load a second copy of the driver. Use ~/nmx/MeowXE3/install-meowxe3.sh"; exit 1; }
E=/Library/Extensions; GB=/Library/GPUBundles
if [ "${1:-}" = restore ]; then
  rm -rf $E/NMXAccel.kext $E/NMXAGDC.kext
  ditto ${NMX:-$HOME/nmx}/downloads/nullmoth-2.0.2/stage/pkgroot/Library/NullMoth/kexts/26/NMXAccel.kext $E/NMXAccel.kext
  chown -R root:wheel $E/NMXAccel.kext && chmod -R 755 $E/NMXAccel.kext
  printf '%s\n' "# NMXGPU bring-up: only the test programs get the GPU for now" nmx-metal-test nmx-metal-render nmx-metal-window > $GB/nvmtl-allow.txt
  kmutil load -p $E/NMXAccel.kext 2>&1 | tail -2
  echo "COMPOSITING-RESTORED (prebuilt NMXAccel, no NMXAGDC)"; exit 0
fi
for k in NMXAccel NMXAGDC; do
  case $k in NMXAccel) S=${NMX:-$HOME/nmx}/src/nmxaccel-nmxgpu/NMXAccel.kext;; NMXAGDC) S=${NMX:-$HOME/nmx}/src/nmxagdc-out/NMXAGDC.kext;; esac
  [ -f "$S/Contents/MacOS/$k" ] || { echo "missing $S"; exit 1; }
  rm -rf $E/$k.kext && ditto "$S" $E/$k.kext && chown -R root:wheel $E/$k.kext && chmod -R 755 $E/$k.kext || { echo "copy $k failed"; exit 1; }
done
printf '%s\n' "# NMXGPU bring-up: WindowServer composites on the GPU (NMXAccel head 0); apps: only the test programs" \
  WindowServer system_profiler "System Information" nmx-metal-test nmx-metal-render nmx-metal-window > $GB/nvmtl-allow.txt
echo "loading NMXAccel and NMXAGDC into the Auxiliary KC (approve NMXAGDC in System Settings > Privacy & Security if asked)"
kmutil load -p $E/NMXAccel.kext 2>&1 | tail -2
kmutil load -p $E/NMXAGDC.kext 2>&1 | tail -2
WANT=$(dwarfdump --uuid $E/NMXAccel.kext/Contents/MacOS/NMXAccel | awk '{print $2}')
echo "waiting for the auxiliary kernel collection to hold NMXAccel $WANT and NMXAGDC (up to 2 minutes)..."
for i in $(seq 1 60); do
  INS=$(kmutil inspect -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --show-kext-uuids 2>/dev/null)
  HAVE=$(printf '%s\n' "$INS" | awk '/com.nullmoth.NMXAccel/ {gsub(/[()]/, "", $NF); print $NF}')
  AGDC=$(printf '%s\n' "$INS" | grep -c com.nullmoth.NMXAGDC)
  if [ "$HAVE" = "$WANT" ] && [ "$AGDC" -ge 1 ]; then
    cat $GB/nvmtl-allow.txt
    echo "collection holds NMXAccel $HAVE and NMXAGDC"
    echo COMPOSITING-INSTALLED; exit 0
  fi
  sleep 2
done
echo "the collection holds NMXAccel ${HAVE:-none} (want $WANT), NMXAGDC entries: ${AGDC:-0} - NOT ready: approve NMXAGDC in"
echo "System Settings > Privacy & Security if it asks, restart once, then run this again"
exit 1
