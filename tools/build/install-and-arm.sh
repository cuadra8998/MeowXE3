#!/bin/bash
# install-and-arm.sh: installs ~/nmx/out/NMXGPU.kext, waits until the Auxiliary Kernel Collection holds this exact
# build, and only then arms the one-shot test (nullmoth-gpu-once=1). Run with: sudo bash ~/nmx/install-and-arm.sh [fbflags [accel-delay-seconds]]
# The optional argument sets nvram nullmoth-fbflags (a number) for the test; without it the current value stays.
set -u
if [ "$(id -u)" != 0 ]; then echo "run it with sudo: sudo bash $0"; exit 1; fi
[ -d /Library/Extensions/MeowXE3.kext ] && { echo "MeowXE3 is installed: this old test script would load a second copy of the driver. Use ~/nmx/MeowXE3/install-meowxe3.sh"; exit 1; }
SRC=${NMX:-$HOME/nmx}/out/NMXGPU.kext
DST=/Library/Extensions/NMXGPU.kext
WANT=$(dwarfdump --uuid "$SRC/Contents/MacOS/NMXGPU" | awk '{print $2}')
echo "installing NMXGPU build $WANT"
rm -rf "$DST" && cp -R "$SRC" /Library/Extensions/ && chown -R root:wheel "$DST" || { echo "copy failed"; exit 1; }
kmutil load -p "$DST" 2>&1 | tail -2
echo "waiting for the auxiliary kernel collection to be rebuilt with it (up to 2 minutes)..."
for i in $(seq 1 60); do
    HAVE=$(kmutil inspect -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --show-kext-uuids 2>/dev/null |
        awk '/com.nullmoth.NMXGPU/ {gsub(/[()]/, "", $NF); print $NF}')
    if [ "$HAVE" = "$WANT" ]; then
        echo "collection holds $HAVE"
        nvram -d nullmoth-gpu-attaching 2>/dev/null
        nvram -d nullmoth-gpu-trace 2>/dev/null
        nvram -d nullmoth-gpu-hb 2>/dev/null
        if [ -n "${1:-}" ]; then nvram nullmoth-fbflags="$1"; fi
        # optional second argument: seconds before NMXGPU announces its claim (NMXAccel's start); 0 removes it
        if [ -n "${2:-}" ]; then if [ "$2" = 0 ]; then nvram -d nullmoth-accel-delay 2>/dev/null; else nvram nullmoth-accel-delay="$2"; fi; fi
        nvram nullmoth-gpu-once=1
        echo "nullmoth-fbflags: $(nvram nullmoth-fbflags 2>/dev/null | awk '{print $2}')  accel delay: $(nvram nullmoth-accel-delay 2>/dev/null | awk '{print $2}')"
        echo "NMX-TEST-ARMED: restart now for the test"
        exit 0
    fi
    sleep 2
done
echo "the collection still holds ${HAVE:-nothing} instead of $WANT: NOT armed. Do not restart for a test; tell Claude."
exit 1
