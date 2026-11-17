#!/bin/bash
# install-meowxe3.sh: installs MeowXE3 (NullMoth NMXGPU + NMXAccel + NMXAGDC for the Wildcat Lake Xe3 iGPU, renamed and
# packaged as one kext) and the Metal pieces it needs, replacing the separate com.nullmoth kexts.
#
#   sudo bash install-meowxe3.sh            install / update
#   sudo bash install-meowxe3.sh debug-on   turn the boot log recorders back on (for a boot that needs debugging)
#   sudo bash install-meowxe3.sh debug-off  turn them off again
#
# What turns the driver on is the OpenCore config, not this script: boot-args nmxintel=1 and NVRAM nullmoth-fbflags 1833.
# To start once without it: OpenCore picker > "NMXGPU: start once without driver", then pick macOS (no restart between).
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
E=/Library/Extensions; GB=/Library/GPUBundles; FW=/Library/NullMoth/firmware; K=$E/MeowXE3.kext
# The plug-ins inside MeowXE3.kext are installed as their own kexts next to it: kernelmanagerd does not register the
# personalities of plug-ins nested in a third-party kext in the auxiliary collection (first MeowXE3 boot: Accel and AGDC
# were in the collection but never matched).
PLUGS="MeowXE3Accel MeowXE3AGDC"
OFF=/Users/Shared/meowxe3-replaced

if [ "${1:-}" = debug-on ]; then
  for j in accellog capture; do
    [ -f $OFF/com.nullmoth.$j.plist ] && mv $OFF/com.nullmoth.$j.plist /Library/LaunchDaemons/ &&
      launchctl bootstrap system /Library/LaunchDaemons/com.nullmoth.$j.plist 2>/dev/null; done
  echo "recorders on (they start with the next boot); for the full trace also add nmxtrace=3 nmxdrmdebug=0x6 to boot-args"
  exit 0
fi

if [ "${1:-}" = debug-off ]; then
  mkdir -p $OFF
  for j in accellog capture; do
    P=/Library/LaunchDaemons/com.nullmoth.$j.plist
    [ -f $P ] && { launchctl bootout system $P 2>/dev/null; mv $P $OFF/; echo "  $j recorder off"; }
  done
  pkill -f "log stream.*meow-sleep" 2>/dev/null
  echo "recorders off"; exit 0
fi

[ -f "$HERE/MeowXE3.kext/Contents/MacOS/MeowXE3" ] || { echo "MeowXE3.kext missing next to this script"; exit 1; }
mkdir -p $OFF

echo "== 1/6 old NullMoth kexts out of /Library/Extensions (kept in $OFF)"
for k in NMXGPU NMXAccel NMXAGDC; do
  [ -d $E/$k.kext ] && { rm -rf $OFF/$k.kext; mv $E/$k.kext $OFF/; echo "  moved $k.kext"; }
done

echo "== 2/6 MeowXE3.kext"
rm -rf $K && cp -R "$HERE/MeowXE3.kext" $E/ || { echo "copy failed"; exit 1; }
for p in $PLUGS; do rm -rf $E/$p.kext && mv $K/Contents/PlugIns/$p.kext $E/ || { echo "plug-in $p failed"; exit 1; }; done
rmdir $K/Contents/PlugIns 2>/dev/null
codesign -f -s - $K 2>&1 | grep -v "replacing existing signature"   # its seal listed the plug-ins
for k in $K $(for p in $PLUGS; do echo $E/$p.kext; done); do chown -R root:wheel $k && chmod -R 755 $k; codesign -v $k || exit 1; done
echo "  $K, $E/MeowXE3Accel.kext, $E/MeowXE3AGDC.kext"

echo "== 3/6 GPU firmware ($FW)"
mkdir -p $FW && cp -R "$HERE/firmware/." $FW/ && chown -R root:wheel /Library/NullMoth && ls -R $FW | grep bin

echo "== 4/6 Metal driver ($GB)"
mkdir -p $GB
rm -rf $GB/NVMTLDriver.bundle $GB/nvmtl
cp -R "$HERE/GPUBundles/NVMTLDriver.bundle" "$HERE/GPUBundles/nvmtl" $GB/ && chown -R root:wheel $GB/NVMTLDriver.bundle $GB/nvmtl || { echo "Metal copy failed"; exit 1; }
# OpenGL through Zink (Mesa Zink on MeowXE3's Vulkan driver; the accelerator names this plug-in)
if [ -d "$HERE/GPUBundles/NVKZinkGLDriver.bundle" ]; then
  rm -rf $GB/NVKZinkGLDriver.bundle && cp -R "$HERE/GPUBundles/NVKZinkGLDriver.bundle" $GB/ && chown -R root:wheel $GB/NVKZinkGLDriver.bundle
  echo "  OpenGL: Zink plug-in installed (an app started with NVKZINK_DISABLE=1 keeps Apple's GL renderer)"
fi
L=$GB/nvmtl-allow.txt
[ -f $L ] || printf '%s\n' "# MeowXE3: programs that get the GPU through Metal (exact program names; add with allow-app.sh)" > $L
for n in WindowServer system_profiler "System Information" "*"; do grep -qxF "$n" $L || echo "$n" >> $L; done   # "*": every app (NullMoth's default; apps without Metal render on the CPU and stutter)
chmod 644 $L; echo "  allow list:"; sed 's/^/    /' $L

echo "== 5/6 everyday settings: one-shot test variables cleared, boot log recorders off"
for v in nullmoth-gpu-once nullmoth-accel-delay nullmoth-gpu-attaching nullmoth-gpu-trace nullmoth-gpu-hb; do nvram -d $v 2>/dev/null; done
nvram nullmoth-fbflags=1833
for j in accellog capture; do
  P=/Library/LaunchDaemons/com.nullmoth.$j.plist
  [ -f $P ] && { launchctl bootout system $P 2>/dev/null; mv $P $OFF/; echo "  $j recorder off"; }
done

echo "== 6/6 auxiliary kernel collection (approve MeowXE3 in System Settings > Privacy & Security if asked)"
kmutil load -p $K -p $E/MeowXE3Accel.kext -p $E/MeowXE3AGDC.kext 2>&1 | tail -3
WANT=$(dwarfdump --uuid $K/Contents/MacOS/MeowXE3 | awk '{print $2}')
echo "waiting for the collection to hold MeowXE3 $WANT and its plug-ins, without the old kexts (up to 3 minutes)..."
for i in $(seq 1 90); do
  INS=$(kmutil inspect -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --show-kext-uuids 2>/dev/null)
  HAVE=$(printf '%s\n' "$INS" | awk '$1 == "com.meowxe3.MeowXE3" {gsub(/[()]/, "", $NF); print $NF}')
  PLUG=$(printf '%s\n' "$INS" | grep -cE "com\.meowxe3\.MeowXE3\.(Accel|AGDC)[[:space:]].*/Library/Extensions/MeowXE3(Accel|AGDC)\.kext")
  OLD=$(printf '%s\n' "$INS" | grep -cE "com\.nullmoth\.NMX(GPU|Accel|AGDC)")
  if [ "$HAVE" = "$WANT" ] && [ "$PLUG" -ge 2 ] && [ "$OLD" = 0 ]; then
    echo "collection holds MeowXE3 $HAVE + Accel + AGDC; old com.nullmoth kexts gone"
    echo "MEOWXE3-INSTALLED: restart (OpenCore boot-args need nmxintel=1)"; exit 0
  fi
  sleep 2
done
echo "the collection did not settle: MeowXE3 '$HAVE' (want $WANT), plug-ins $PLUG, old kexts still in it: $OLD"
echo "do NOT restart yet; send this output"
exit 1
