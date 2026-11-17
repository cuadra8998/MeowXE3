#!/bin/bash
# camera-panic-test.sh: records what happens while Photo Booth runs, so a kernel panic keeps the last lines.
#   sudo bash ~/nmx/camera-panic-test.sh         start recording (then open Photo Booth and leave it running)
#   sudo bash ~/nmx/camera-panic-test.sh stop    stop recording, recorders off
# Output: /Users/Shared/meow-camera.log (synced after every line), plus the driver recorder's /Users/Shared/nmx-accel.log
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
OUT=/Users/Shared/meow-camera.log
if [ "${1:-}" = stop ]; then
  pkill -f "log stream.*meow-camera" 2>/dev/null
  bash ${NMX:-$HOME/nmx}/MeowXE3/install-meowxe3.sh debug-off
  echo "CAMERA-TEST-STOPPED"; exit 0
fi
bash ${NMX:-$HOME/nmx}/MeowXE3/install-meowxe3.sh debug-on
pkill -f "log stream.*meow-camera" 2>/dev/null
[ -f $OUT ] && mv -f $OUT $OUT.prev
echo "=== camera test $(date '+%F %T')" > $OUT; sync
# kernel messages, the camera services, Photo Booth, and the GPU stack (the tag meow-camera names this stream)
nohup bash -c '/usr/bin/log stream --style compact --level info --predicate "process == \"kernel\" OR process == \"Photo Booth\" OR process CONTAINS \"Camera\" OR process CONTAINS \"camera\" OR process == \"UVCAssistant\" OR process == \"VDCAssistant\" OR process == \"WindowServer\" AND messageType >= 16" | while IFS= read -r l; do printf "%s\n" "$l" >> '"$OUT"'; sync; done # meow-camera' >/dev/null 2>&1 &
sleep 2
echo "RECORDING. Save your work, open Photo Booth and leave it running (up to ~15 minutes)."
echo "If the Mac panics and restarts, just tell Claude 'im back'."
