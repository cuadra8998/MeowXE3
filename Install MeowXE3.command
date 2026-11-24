#!/bin/bash
# ============================================================================================================
#  MeowXE3 installer - Intel Xe3 (Wildcat Lake) graphics acceleration for macOS Tahoe / Sequoia on OpenCore
#  Double-click it (right-click > Open the first time), or:  sudo bash "Install MeowXE3.command"
#  Options: --dry-run   check everything and show the OpenCore changes on a copy; change nothing
#           --fast      skip the eye candy
# ============================================================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PAY=$HERE/payload
VERSION=$(cat "$PAY/VERSION" 2>/dev/null || echo "?")
TARGET=$(cat "$PAY/TARGET" 2>/dev/null || echo 26)   # macOS major the payload was built for (no file: older Tahoe releases)
case $TARGET in 15) OSNAME="Sequoia";; *) OSNAME="Tahoe";; esac
DRY=0; FAST=${MEOWXE3_FAST:-0}
for a in "$@"; do case $a in --dry-run) DRY=1;; --fast) FAST=1;; esac; done
LOG=/Users/Shared/MeowXE3-install.log
G=7C436110-AB2A-4BBB-A880-FE41995C9F82
SUPPORTED="fd80"                         # tested: Wildcat Lake 8086:FD80 (ASUS Vivobook X1504MA)
# Wildcat Lake FD81 and Panther Lake are in the driver (Linux INTEL_WCL_IDS / INTEL_PTL_IDS) but untested
XE3_OTHER="fd81 b080 b081 b082 b083 b084 b085 b086 b087 b08f b090 b091 b092 b0a0 b0a1 b0a2 b0b0"   # in the driver, never run on real hardware

# --- look -----------------------------------------------------------------------------------------------------
GRN=$'\033[0;32m'; BGRN=$'\033[1;92m'; DIM=$'\033[2;32m'; RED=$'\033[1;91m'; YEL=$'\033[1;93m'; RST=$'\033[0m'; BLK=$'\033[40m'
pace() { [ "$FAST" = 1 ] || sleep "$1"; }
type_out() { # slow typewriter line
  local s=$1 i
  if [ "$FAST" = 1 ]; then printf '%s\n' "$s"; return; fi
  for ((i=0; i<${#s}; i++)); do printf '%s' "${s:$i:1}"; sleep 0.008; done; printf '\n'; }
say()  { printf '%s%s%s\n' "$GRN" "$*" "$RST"; echo "$*" >> "$LOG"; }
ok()   { printf '%s  [ %sOK%s%s ]  %s%s\n' "$GRN" "$BGRN" "$RST" "$GRN" "$*" "$RST"; echo "  [OK] $*" >> "$LOG"; }
warn() { printf '%s  [ !! ]  %s%s\n' "$YEL" "$*" "$RST"; echo "  [!!] $*" >> "$LOG"; }
bad()  { printf '%s  [FAIL]  %s%s\n' "$RED" "$*" "$RST"; echo "  [FAIL] $*" >> "$LOG"; }
hr()   { printf '%s%s%s\n' "$DIM" "------------------------------------------------------------------------------" "$RST"; }
bar()  { # label seconds
  local i n=40; printf '%s  %-28s [' "$GRN" "$1"
  for ((i=0; i<n; i++)); do printf '#'; pace "$(echo "scale=3; $2/$n" | bc)"; done; printf ']%s\n' "$RST"; }
ask()  { # question -> 0 for yes
  local r; printf '%s  >> %s [y/N] %s' "$BGRN" "$1" "$RST"; read -r r; echo ">> $1 $r" >> "$LOG"; [[ "$r" =~ ^[yY] ]]; }
die()  { bad "$*"; say ""; say "  nothing more was changed. log: $LOG"; finish 1; }
finish() { [ -n "${MNT_BY_US:-}" ] && diskutil unmount "$ESP" >/dev/null 2>&1; printf '%s' "$RST"; exit "${1:-0}"; }
trap 'printf "%s\n" "$RST"; finish 130' INT

banner() {
  printf '%s\033[2J\033[H' "$BLK"
  printf '%s' "$BGRN"
  cat <<'EOF'

   ███╗   ███╗███████╗ ██████╗ ██╗    ██╗██╗  ██╗███████╗██████╗
   ████╗ ████║██╔════╝██╔═══██╗██║    ██║╚██╗██╔╝██╔════╝╚════██╗
   ██╔████╔██║█████╗  ██║   ██║██║ █╗ ██║ ╚███╔╝ █████╗   █████╔╝
   ██║╚██╔╝██║██╔══╝  ██║   ██║██║███╗██║ ██╔██╗ ██╔══╝   ╚═══██╗
   ██║ ╚═╝ ██║███████╗╚██████╔╝╚███╔███╔╝██╔╝ ██╗███████╗██████╔╝
   ╚═╝     ╚═╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚═════╝
EOF
  printf '%s' "$GRN"
  cat <<EOF
        /\\_/\\      Intel Xe3 graphics acceleration for macOS $OSNAME
       ( o.o )     Metal  *  Vulkan  *  OpenGL (Zink)  *  GPU compositing
        > ^ <      version $VERSION            :: ALPHA - use at your own risk ::
EOF
  hr
}

matrix() { # a second of falling hex, for the vibe
  [ "$FAST" = 1 ] && return
  local i j line
  for ((i=0; i<14; i++)); do
    line=""; for ((j=0; j<9; j++)); do printf -v w '%04x%04x ' $RANDOM $RANDOM; line+=$w; done
    printf '%s  %s%s\n' "$DIM" "$line" "$RST"; sleep 0.04
  done
}

# --- root -----------------------------------------------------------------------------------------------------
if [ "$(id -u)" != 0 ]; then
  printf '%sMeowXE3 needs administrator rights. Type your Mac password (nothing shows while you type).%s\n' "$GRN" "$RST"
  exec sudo MEOWXE3_FAST="$FAST" bash "$0" "$@"
fi
: > "$LOG" 2>/dev/null || LOG=/tmp/MeowXE3-install.log
echo "MeowXE3 installer $VERSION $(date)" >> "$LOG"
REAL_USER=${SUDO_USER:-$(id -un)}; REAL_HOME=$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}'); REAL_HOME=${REAL_HOME:-/Users/Shared}

# --- checks ---------------------------------------------------------------------------------------------------
gpu_id() { system_profiler SPDisplaysDataType 2>/dev/null | awk -F'0x' '/Device ID/ {print tolower($2); exit}'; }
gpu_vendor() { system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 -o 'Vendor: .*'; }

check_system() { # sets CHECK_FAILED / CHECK_WARN
  CHECK_FAILED=0; CHECK_WARN=0
  say "  :: scanning system ::"; pace 0.3
  local mv; mv=$(sw_vers -productVersion)
  local major=${mv%%.*} minor; minor=${mv#*.}; minor=${minor%%.*}; [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
  if [ "$major" = "$TARGET" ]; then
    if [ "$TARGET" = 15 ] && [ "$minor" -lt 5 ]; then
      bad "macOS $mv - the Sequoia build needs 15.5 or newer (OpenGL/Zink is built for 15.5); update macOS first"; CHECK_FAILED=1
    else ok "macOS $mv ($OSNAME)"; fi
  elif [ "$major" = 15 ] || [ "$major" = 26 ]; then
    bad "macOS $mv, but this download is the $OSNAME (macOS $TARGET) build - get the $( [ "$major" = 15 ] && echo "-sequoia" || echo "Tahoe") zip from Releases"
    say "         (the GPU accelerator kext differs between Sequoia and Tahoe; the wrong one leaves a black or frozen desktop)"; CHECK_FAILED=1
  else bad "macOS $mv - MeowXE3 supports Sequoia 15.5+ and Tahoe 26.x only"; CHECK_FAILED=1; fi
  if [ "$(uname -m)" = x86_64 ]; then ok "Intel Mac kernel (x86_64)"; else bad "this is not an x86_64 Mac"; CHECK_FAILED=1; fi
  local id; id=$(gpu_id)
  if [[ " $SUPPORTED " == *" $id "* ]]; then ok "GPU 8086:$(echo "$id" | tr a-f A-F) Wildcat Lake Xe3 (tested)"
  elif [[ " $XE3_OTHER " == *" $id "* ]]; then warn "GPU 8086:$(echo "$id" | tr a-f A-F) is Xe3 and in the driver, but UNTESTED (only FD80 is known to work) - please report how it goes"; CHECK_WARN=1
  else bad "GPU '${id:-none}' ($(gpu_vendor)) - MeowXE3 drives Intel Xe3 only"; CHECK_FAILED=1; fi
  if nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version >/dev/null 2>&1; then
    ok "booted by OpenCore $(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | awk '{print $2}')"
  else bad "not booted by OpenCore"; CHECK_FAILED=1; fi
  # what the driver needs but this installer never changes
  local sip; sip=$(csrutil status 2>/dev/null)
  if echo "$sip" | grep -qiE 'Kext Signing: disabled|status: disabled'; then ok "SIP allows third-party kexts"
  else warn "SIP: kext signing looks ENABLED - MeowXE3's kexts are ad-hoc signed and will not load"
       say "         set csr-active-config in your OpenCore config yourself (e.g. 030A0000 or 430A0000); see README"; CHECK_WARN=1; fi
  local ba; ba=$(nvram boot-args 2>/dev/null | cut -f2-)
  if echo " $ba " | grep -qE ' amfi_get_out_of_my_way=(0x)?1 | amfi=0x80 '; then ok "AMFI boot-args present (the Metal driver bundle is not Apple-signed)"
  else warn "AMFI: no amfi_get_out_of_my_way=0x1 / amfi=0x80 in boot-args - apps cannot load the Metal driver"
       say "         add them to boot-args yourself if you accept the security trade-off; see README"; CHECK_WARN=1; fi
  [ -f "$PAY/MeowXE3.kext/Contents/MacOS/MeowXE3" ] && ok "payload $VERSION found" || { bad "payload/ folder missing next to the installer"; CHECK_FAILED=1; }
}

# --- OpenCore EFI ---------------------------------------------------------------------------------------------
find_esp() { # sets ESP and OC
  ESP=""; OC=""; MNT_BY_US=""
  local uuid dev mp
  uuid=$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:boot-path 2>/dev/null | grep -oE 'GPT,[0-9A-Fa-f-]{36}' | cut -d, -f2)
  local cands=""
  [ -n "$uuid" ] && dev=$(diskutil info "$uuid" 2>/dev/null | awk -F': *' '/Device Identifier/ {print $2}') && cands=$dev
  cands="$cands $(diskutil list | awk '/ EFI / {print $NF}')"
  for dev in $cands; do
    mp=$(diskutil info "$dev" 2>/dev/null | awk -F': *' '/Mount Point/ {print $2}')
    if [ -z "$mp" ]; then diskutil mount "$dev" >/dev/null 2>&1 || continue; mp=$(diskutil info "$dev" | awk -F': *' '/Mount Point/ {print $2}'); MNT_BY_US=1; fi
    if [ -f "$mp/EFI/OC/config.plist" ]; then ESP=$dev; OC=$mp/EFI/OC; return 0; fi
    [ -n "$MNT_BY_US" ] && diskutil unmount "$dev" >/dev/null 2>&1; MNT_BY_US=""
  done
  return 1
}

backup_efi() {
  BK=$REAL_HOME/MeowXE3-EFI-backup-$(date +%Y%m%d-%H%M%S)
  ditto "$(dirname "$OC")" "$BK/EFI" && chown -R "$REAL_USER" "$BK" && ok "EFI backed up to $BK" || die "EFI backup failed"
}

do_opencore() {
  say ""; say "  :: OpenCore ::"
  find_esp || die "no EFI partition with EFI/OC/config.plist found"
  ok "OpenCore config: $OC/config.plist ($ESP)"
  bash "$PAY/tools/oc-patch.sh" check "$OC" | sed "s/^/$GRN/; s/\$/$RST/"
  if [ "$DRY" = 1 ]; then
    local T; T=$(mktemp -d /tmp/meowxe3-dry.XXXXXX); mkdir -p "$T/Kexts" "$T/Tools"; cp "$OC/config.plist" "$T/"
    say ""; say "  dry run - these changes would be made (on a copy):"
    bash "$PAY/tools/oc-patch.sh" apply "$T" "$PAY" | sed "s/^/$GRN/; s/\$/$RST/"; rm -rf "$T"; return 0
  fi
  ask "patch this OpenCore config (a full EFI backup is made first)?" || { warn "OpenCore left alone"; return 1; }
  backup_efi
  bash "$PAY/tools/oc-patch.sh" apply "$OC" "$PAY" 2>&1 | tee -a "$LOG" | sed "s/^/$GRN/; s/\$/$RST/"
  [ "${PIPESTATUS[0]}" = 0 ] || die "OpenCore patch failed - restore from $BK if needed"
  ok "OpenCore patched"
}

# --- driver ---------------------------------------------------------------------------------------------------
do_driver() {
  say ""; say "  :: driver, Metal, Vulkan, OpenGL ::"
  if [ "$DRY" = 1 ]; then say "  dry run - would run payload/install-meowxe3.sh"; return 0; fi
  xattr -dr com.apple.quarantine "$PAY" 2>/dev/null
  bar "unpacking payload" 1.2
  bash "$PAY/install-meowxe3.sh" 2>&1 | tee -a "$LOG" | sed "s/^/$DIM  >> /; s/\$/$RST/"
  [ "${PIPESTATUS[0]}" = 0 ] && ok "driver installed" || die "driver install did not finish - do NOT restart; send $LOG"
  # helpers in a fixed place
  mkdir -p /Library/GPUBundles/MeowXE3 && cp "$PAY/tools/"*.sh /Library/GPUBundles/MeowXE3/ && chmod 755 /Library/GPUBundles/MeowXE3/*.sh
}

do_uninstall() {
  say ""; say "  :: uninstall ::"
  if [ "$DRY" = 1 ]; then say "  dry run - would remove the OpenCore entries (oc-patch.sh remove), the kexts, /Library/GPUBundles parts and firmware"; return; fi
  ask "remove MeowXE3 (driver, Metal bundles, firmware) and its OpenCore entries?" || return
  if find_esp; then backup_efi; bash "$PAY/tools/oc-patch.sh" remove "$OC" 2>&1 | tee -a "$LOG" | sed "s/^/$GRN/; s/\$/$RST/"; ok "OpenCore entries removed"
  else warn "OpenCore config not found - remove nmxintel=1 from boot-args yourself"; fi
  rm -rf /Library/Extensions/MeowXE3.kext /Library/Extensions/MeowXE3Accel.kext /Library/Extensions/MeowXE3AGDC.kext
  rm -rf /Library/GPUBundles/NVMTLDriver.bundle /Library/GPUBundles/nvmtl /Library/GPUBundles/NVKZinkGLDriver.bundle \
         /Library/GPUBundles/nvmtl-allow.txt /Library/GPUBundles/nvmtl-backup /Library/GPUBundles/MeowXE3 /Library/NullMoth
  nvram -d nullmoth-fbflags 2>/dev/null
  bar "rebuilding kext collection" 1
  kmutil install --update-all >/dev/null 2>&1 || true
  ok "MeowXE3 removed - restart"
}

summary_end() {
  hr
  if [ "$DRY" = 1 ]; then type_out "${BGRN}  >>> DRY RUN COMPLETE - nothing was changed. run again without --dry-run to install. <<<${RST}"; hr; return; fi
  type_out "${BGRN}  >>> MEOWXE3 IS IN. <<<${RST}"
  say "  1. If macOS asks, allow MeowXE3 in System Settings > Privacy & Security."
  say "  2. Restart."
  say "  3. Escape hatch: OpenCore picker > 'MeowXE3: start once without driver', then pick macOS."
  say "     (Off for good: run this installer again > Uninstall, or remove nmxintel=1 from boot-args.)"
  say "  Minecraft/Java on Vulkan: see README. EFI backup: ${BK:-none}. Log: $LOG"
  hr
}

# --- main -----------------------------------------------------------------------------------------------------
banner; matrix
type_out "${GRN}  > initializing meow subsystem....... purr${RST}"; pace 0.2
type_out "${GRN}  > loading Xe3 pixel pipes............ ok${RST}"; pace 0.2
[ "$DRY" = 1 ] && warn "DRY RUN - nothing will be changed"
hr; check_system; hr
if [ "$CHECK_FAILED" = 1 ]; then die "this Mac cannot run MeowXE3"; fi
if [ "$CHECK_WARN" = 1 ]; then ask "there are warnings above. continue anyway?" || finish 1; fi

say ""
say "   [1] install everything   (driver + Metal/Vulkan/OpenGL + OpenCore changes)"
say "   [2] driver only          (you edit OpenCore yourself)"
say "   [3] OpenCore only"
say "   [4] uninstall"
say "   [q] quit"
printf '%s  >> choice: %s' "$BGRN" "$RST"; read -r CH; echo ">> choice $CH" >> "$LOG"
case $CH in
  1) do_opencore; do_driver; summary_end ;;
  2) do_driver; summary_end; say "  remember: boot-args nmxintel=1 and NVRAM nullmoth-fbflags=1833 turn it on" ;;
  3) do_opencore ;;
  4) do_uninstall ;;
  *) say "  bye. =^.^=" ;;
esac
finish 0
