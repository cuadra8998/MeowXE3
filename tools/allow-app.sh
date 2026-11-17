#!/bin/bash
# allow-app.sh NAME...: adds programs (their executable names, e.g. Chess) to the Metal allow list, keeping the rest.
# allow-app.sh -r NAME...: takes them off again.
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0 NAME..."; exit 1; }
L=/Library/GPUBundles/nvmtl-allow.txt
if [ "${1:-}" = -r ]; then shift; for n in "$@"; do grep -vxF "$n" "$L" > "$L.tmp" && mv "$L.tmp" "$L"; done
else for n in "$@"; do grep -qxF "$n" "$L" || echo "$n" >> "$L"; done; fi
chmod 644 "$L"; cat "$L"; echo ALLOW-UPDATED
