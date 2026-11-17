#!/bin/bash
# install-audio.sh [remove]: MeowXE3Audio.kext (NullMoth's NMXAudio, FreeBSD HD Audio on the xnu layer, plus MeowXE3's
# Wildcat Lake / Panther Lake support: 04:01-class match and PIO codec commands) into /Library/Extensions.
# Boot guard: a boot that panics or hangs while audio attaches makes the next boot skip it. -nvoff (the OpenCore entry
# "start once without driver") turns it off too.
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
E=/Library/Extensions; K=$E/MeowXE3Audio.kext; SRC=${NMX:-$HOME/nmx}/MeowXE3/MeowXE3Audio.kext
if [ "${1:-}" = remove ]; then
  rm -rf $K && kmutil install --update-all >/dev/null 2>&1; nvram -d nullmoth-audio-attaching 2>/dev/null
  echo "AUDIO-REMOVED: restart"; exit 0
fi
[ -f $SRC/Contents/MacOS/MeowXE3Audio ] || { echo "no $SRC"; exit 1; }
rm -rf $K && cp -R $SRC $E/ && chown -R root:wheel $K && chmod -R 755 $K && codesign -v $K || exit 1
nvram -d nullmoth-audio-attaching 2>/dev/null
kmutil load -p $K 2>&1 | tail -2
WANT=$(dwarfdump --uuid $K/Contents/MacOS/MeowXE3Audio | awk '{print $2}')
echo "waiting for the auxiliary collection to hold MeowXE3Audio $WANT (up to 3 minutes)..."
for i in $(seq 1 90); do
  HAVE=$(kmutil inspect -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc --show-kext-uuids 2>/dev/null | awk '$1 == "com.meowxe3.MeowXE3Audio" {gsub(/[()]/, "", $NF); print $NF}')
  [ "$HAVE" = "$WANT" ] && { echo "AUDIO-INSTALLED: restart"; exit 0; }
  sleep 2
done
echo "the collection did not pick it up yet (have '$HAVE'); do NOT restart, send this output"; exit 1
