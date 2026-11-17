#!/bin/bash
# sleep-test.sh: one logged S3 sleep test for MeowXE3. Run with sudo, after saving your work.
#   sudo bash ~/nmx/sleep-test.sh           set up, start a log stream, then sleep in 10 s
#   sudo bash ~/nmx/sleep-test.sh restore   put the power settings back to what they were before the test
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
SAVE=/Users/Shared/meow-sleep-pmset-before.txt
OUT=/Users/Shared/meow-sleep-stream.log

if [ "${1:-}" = restore ]; then
  [ -f $SAVE ] || { echo "no saved settings ($SAVE)"; exit 1; }
  # pmset -g custom lists both power sources; the keys this test changed get their old values back
  for src in AC Battery; do
    flag=$([ $src = AC ] && echo -c || echo -b)
    block=$(awk -v s="$src Power:" '$0 ~ "^"s {f=1; next} /Power:$/ {f=0} f' $SAVE)
    for k in hibernatemode standby powernap proximitywake tcpkeepalive; do
      v=$(printf '%s\n' "$block" | awk -v k=$k '$1 == k {print $2}')
      [ -n "$v" ] && pmset $flag $k $v
    done
  done
  pmset -g | grep -E "hibernatemode|standby |powernap|proximitywake|tcpkeepalive"; echo RESTORED; exit 0
fi

[ -f $SAVE ] || pmset -g custom > $SAVE
echo "== power settings for plain S3 (old ones saved in $SAVE)"
pmset -a hibernatemode 0 standby 0 powernap 0 proximitywake 0 tcpkeepalive 0
pmset -g | grep -E "hibernatemode|standby |powernap|proximitywake|tcpkeepalive"

echo "== log recorders on"
bash ${NMX:-$HOME/nmx}/MeowXE3/install-meowxe3.sh debug-on   # off again: install-meowxe3.sh debug-off

echo "== log stream to $OUT (kernel, power management, WindowServer)"
pkill -f "log stream.*meow-sleep" 2>/dev/null
nohup /usr/bin/log stream --style compact --level info --predicate \
  'process == "kernel" OR process == "powerd" OR process == "WindowServer" OR sender == "MeowXE3" OR sender == "MeowXE3Accel"' \
  > $OUT 2>&1 < /dev/null &
sleep 2
{ echo "=== sleep test $(date '+%F %T'), uptime: $(uptime)"; } >> /Users/Shared/meow-sleep-marks.txt
echo "pmset log before: $(pmset -g log | grep -cE ' Sleep  ') sleep entries"
echo "SLEEPING IN 10 SECONDS. Wait about 20 s after the screen goes dark, then press a key or tap the power button."
sleep 10
sync
pmset sleepnow
