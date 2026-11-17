#!/bin/bash
# repack.sh VERSION: rebuilds MeowXE3.kext (with its two plug-ins) in this folder from the current build outputs:
#   NMXGPU   ~/nmx/out/NMXGPU.kext
#   NMXAccel ~/nmx/src/nmxaccel-nmxgpu/NMXAccel.kext
#   NMXAGDC  ~/nmx/src/nmxagdc-out/NMXAGDC.kext
# Renames them (com.meowxe3.*), sets VERSION on all three (kmutil only rebuilds the auxiliary collection when a version
# or binary changes), keeps the license files, re-signs ad hoc. Then: sudo bash install-meowxe3.sh
set -euo pipefail
V=${1:?usage: repack.sh VERSION (e.g. 1.0.2)}
HERE=$(cd "$(dirname "$0")" && pwd); K=$HERE/MeowXE3.kext; PB=/usr/libexec/PlistBuddy
TMP=$(mktemp -d); cp -R "$K/Contents/Resources" "$TMP/Resources"
rm -rf "$K"; ditto "$HOME/nmx/out/NMXGPU.kext" "$K"; mkdir -p "$K/Contents/PlugIns"
ditto "$HOME/nmx/src/nmxaccel-nmxgpu/NMXAccel.kext" "$K/Contents/PlugIns/MeowXE3Accel.kext"
ditto "$HOME/nmx/src/nmxagdc-out/NMXAGDC.kext" "$K/Contents/PlugIns/MeowXE3AGDC.kext"
rm -rf "$K/Contents/Resources"; cp -R "$TMP/Resources" "$K/Contents/Resources"; rm -rf "$TMP"
ren() { # kext oldexe newexe newid
  local k=$1 pl=$1/Contents/Info.plist
  mv "$k/Contents/MacOS/$2" "$k/Contents/MacOS/$3"
  $PB -c "Set :CFBundleExecutable $3" -c "Set :CFBundleIdentifier $4" "$pl"
  python3 -I - "$pl" "$4" "$3" "$V" <<'EOF'
import plistlib,sys
p,bid,name,v=sys.argv[1:5]; d=plistlib.load(open(p,'rb'))
for per in d.get('IOKitPersonalities',{}).values():
    if 'CFBundleIdentifier' in per: per['CFBundleIdentifier']=bid
d['CFBundleName']=name; d['CFBundleVersion']=v; d['CFBundleShortVersionString']=v; d.pop('CFBundleGetInfoString',None)
plistlib.dump(d,open(p,'wb'))
EOF
}
ren "$K" NMXGPU MeowXE3 com.meowxe3.MeowXE3
ren "$K/Contents/PlugIns/MeowXE3Accel.kext" NMXAccel MeowXE3Accel com.meowxe3.MeowXE3.Accel
ren "$K/Contents/PlugIns/MeowXE3AGDC.kext" NMXAGDC MeowXE3AGDC com.meowxe3.MeowXE3.AGDC
# OpenGL through Zink: the accelerator names the Zink GL plug-in (/Library/GPUBundles/NVKZinkGLDriver.bundle); NMXAccel
# only sets Apple's GL-on-Metal renderer when the property is absent. MEOWXE3_APPLE_GL=1 keeps Apple's renderer.
if [ "${MEOWXE3_APPLE_GL:-0}" != 1 ]; then
  python3 -I - "$K/Contents/PlugIns/MeowXE3Accel.kext/Contents/Info.plist" <<'EOF'
import plistlib,sys
p=sys.argv[1]; d=plistlib.load(open(p,'rb'))
for per in d.get('IOKitPersonalities',{}).values():
    if per.get('IOClass') == 'NMXAccel': per['IOGLBundleName'] = 'NVKZinkGLDriver'
plistlib.dump(d,open(p,'wb'))
EOF
fi
find "$K" -name _CodeSignature -type d -prune -exec rm -rf {} +
for k in "$K"/Contents/PlugIns/*.kext "$K"; do codesign -f -s - "$k" 2>&1 | grep -v "replacing existing" || true; done
codesign -v --deep "$K"
for k in "$K" "$K"/Contents/PlugIns/*.kext; do
  printf '%-14s %s %s\n' "$($PB -c 'Print :CFBundleExecutable' "$k/Contents/Info.plist")" \
    "$($PB -c 'Print :CFBundleVersion' "$k/Contents/Info.plist")" \
    "$(dwarfdump --uuid "$k/Contents/MacOS/"* | awk '{print $2}')"
done
echo "REPACKED $V: sudo bash $HERE/install-meowxe3.sh"
