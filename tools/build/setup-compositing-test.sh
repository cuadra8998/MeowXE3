#!/bin/bash
# setup-compositing-test.sh: everything for the first GPU-compositing test boot, in order, with one sudo:
#   1. the log recorder (/Users/Shared/nmx-accel.log) and the startup capture
#   2. NMXAccel (ericek's display patches + 0048) and NMXAGDC into the Auxiliary KC; WindowServer on the allow list
#   3. NMXGPU, armed for one boot with nullmoth-fbflags 1833 = 0x400 panel flips | 0x200 accelerated head | 0x100 watchers off |
#      0x20 IOGraphics power | 0x8 keep the boot framebuffer | 0x1 not the console, and NMXAccel starting at once
#      (nullmoth-accel-delay 0: it must arm the head before WindowServer opens it)
# Undo the kexts: sudo bash ~/nmx/install-compositing.sh restore
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
[ -d /Library/Extensions/MeowXE3.kext ] && { echo "MeowXE3 is installed: this old test script would load a second copy of the driver. Use ~/nmx/MeowXE3/install-meowxe3.sh"; exit 1; }
echo "== 1/3 log recorder"; bash ${NMX:-$HOME/nmx}/capture/install-capture.sh || exit 1
echo "== 2/3 NMXAccel + NMXAGDC"; bash ${NMX:-$HOME/nmx}/install-compositing.sh || exit 1
FLAGS="${1:-1833}"  # 1833 = 809 + 0x400 panel flips (0099/0100: MMIO commits, no DSB; no tearing). 809 = copy, no flips
echo "== 3/3 NMXGPU, armed with fbflags $FLAGS"; bash ${NMX:-$HOME/nmx}/install-and-arm.sh "$FLAGS" 0 || exit 1
echo "boot-args now (OpenCore sets them at boot): $(nvram boot-args 2>/dev/null | cut -f2-)"
echo "COMPOSITING-TEST-ARMED: restart now"
