#!/bin/bash
# allow-sysinfo.sh: adds System Information (system_profiler, "System Information") to the Metal allow list now,
# keeping every line already there, so its Graphics pane can ask the GPU for its Metal family.
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
L=/Library/GPUBundles/nvmtl-allow.txt
for n in system_profiler "System Information"; do grep -qxF "$n" "$L" || echo "$n" >> "$L"; done
cat "$L"; echo SYSINFO-ALLOWED
