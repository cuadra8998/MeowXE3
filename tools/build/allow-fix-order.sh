#!/bin/bash
# allow-fix-order.sh: puts every exclusion line (-Name) of the Metal allow list before the other entries, because the
# plugin stops at the first match and "*" would otherwise win.
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
L=/Library/GPUBundles/nvmtl-allow.txt
{ grep '^#' "$L"; grep '^-' "$L"; grep -v '^#' "$L" | grep -v '^-'; } > "$L.tmp" && mv "$L.tmp" "$L" && chmod 644 "$L"
cat "$L"; echo ALLOW-ORDER-FIXED
