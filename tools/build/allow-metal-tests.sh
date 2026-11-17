#!/bin/bash
# allow-metal-tests.sh: lets the three Metal test programs use the GPU (the plugin's allow list); nothing else.
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
printf '%s\n' "# NMXGPU bring-up: the test programs and System Information (Metal family line)" system_profiler "System Information" nmx-metal-test nmx-metal-render nmx-metal-window \
  > /Library/GPUBundles/nvmtl-allow.txt && cat /Library/GPUBundles/nvmtl-allow.txt && echo ALLOW-UPDATED
