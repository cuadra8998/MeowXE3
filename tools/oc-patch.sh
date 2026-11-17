#!/bin/bash
# oc-patch.sh: the OpenCore part of MeowXE3, made with Apple's own PlistBuddy (no python needed).
#
#   oc-patch.sh apply  OC_DIR PAYLOAD_DIR   add MeowXE3Boot.kext, boot-arg nmxintel=1, NVRAM nullmoth-fbflags=1833,
#                                           and the "MeowXE3: start once without driver" boot picker entry
#   oc-patch.sh remove OC_DIR               take all of that out again
#   oc-patch.sh check  OC_DIR               say what is there now, change nothing
#
# OC_DIR is the EFI/OC folder (the one holding config.plist). The caller backs it up first. Every change is made on a
# copy, linted with plutil, and only then put in place. It never touches SIP (csr-active-config), AMFI boot-args,
# ACPI, SMBIOS or any other kext.
set -u
PB=/usr/libexec/PlistBuddy
G=7C436110-AB2A-4BBB-A880-FE41995C9F82
FLAGS=1833
MODE=${1:-}; OC=${2:-}; PAY=${3:-}
[ -n "$MODE" ] && [ -f "$OC/config.plist" ] || { echo "usage: oc-patch.sh apply|remove|check EFI/OC-folder [payload]"; exit 2; }
CFG=$OC/config.plist

pbq() { $PB -c "$1" "$2" 2>/dev/null; }                 # quiet PlistBuddy
count() { local n=0; while pbq "Print :$1:$n" "$2" >/dev/null; do n=$((n+1)); done; echo $n; }
find_kext() { # file bundle -> index or -1
  local n; n=$(count Kernel:Add "$1")
  for ((i=0; i<n; i++)); do [ "$(pbq "Print :Kernel:Add:$i:BundlePath" "$1")" = "$2" ] && { echo $i; return; }; done; echo -1; }
find_tool() {
  local n; n=$(count Misc:Tools "$1")
  for ((i=0; i<n; i++)); do [ "$(pbq "Print :Misc:Tools:$i:Path" "$1")" = "$2" ] && { echo $i; return; }; done; echo -1; }
in_delete() {
  local n; n=$(count "NVRAM:Delete:$G" "$1")
  for ((i=0; i<n; i++)); do [ "$(pbq "Print :NVRAM:Delete:$G:$i" "$1")" = "$2" ] && { echo $i; return; }; done; echo -1; }

summary() { # file
  local f=$1 ba
  ba=$(pbq "Print :NVRAM:Add:$G:boot-args" "$f")
  echo "    MeowXE3Boot.kext entry   : $([ "$(find_kext "$f" MeowXE3Boot.kext)" -ge 0 ] && echo yes || echo no)"
  echo "    boot-args nmxintel=1     : $(echo " $ba " | grep -q ' nmxintel=1 ' && echo yes || echo no)"
  echo "    NVRAM nullmoth-fbflags   : $(pbq "Print :NVRAM:Add:$G:nullmoth-fbflags" "$f" || echo none)"
  echo "    rewritten every boot     : $([ "$(in_delete "$f" nullmoth-fbflags)" -ge 0 ] && echo yes || echo no)"
  echo "    safe-start picker entry  : $([ "$(find_tool "$f" NullMothSafe.efi)" -ge 0 ] && echo yes || echo no)"
}

requirements() { # what the driver needs that this script will NOT set
  local f=$1 ba; ba=$(pbq "Print :NVRAM:Add:$G:boot-args" "$f")
  echo "  not changed by MeowXE3 (you decide):"
  echo "    SIP (csr-active-config)  : $(pbq "Print :NVRAM:Add:$G:csr-active-config" "$f" | xxd -p | head -c 8 || echo none)"
  echo "    AMFI boot-args           : $(echo " $ba " | grep -oE ' (amfi_get_out_of_my_way=[^ ]+|amfi=[^ ]+|ipc_control_port_options=[^ ]+)' | tr -d '\n' || true)"
  [ -d "$OC/Kexts/AMFIPass.kext" ] && echo "    AMFIPass.kext            : present"
  return 0
}

lint_and_swap() { # tmp
  plutil -lint "$1" >/dev/null || { echo "  !! the edited config does not lint - nothing written"; plutil -lint "$1"; rm -f "$1"; exit 1; }
  echo "  changes:"; diff <(plutil -p "$CFG") <(plutil -p "$1") | grep '^[<>]' | grep -vE '^[<>] +([0-9]+ => \{|\})$' | sed 's/^/    /'
  cat "$1" > "$CFG" && rm -f "$1"
  plutil -lint "$CFG" >/dev/null && echo "  config.plist lint OK"
}

case $MODE in
check)
  echo "  $CFG"; summary "$CFG"; requirements "$CFG" ;;

apply)
  [ -d "$PAY/OpenCore/MeowXE3Boot.kext" ] || { echo "MeowXE3Boot.kext missing in $PAY/OpenCore"; exit 1; }
  T=$(mktemp "$OC/.config-meowxe3.XXXXXX"); cp "$CFG" "$T"
  # 1. MeowXE3Boot.kext right after Lilu (it needs no Lilu, the position just keeps the list tidy)
  rm -rf "$OC/Kexts/MeowXE3Boot.kext" && cp -R "$PAY/OpenCore/MeowXE3Boot.kext" "$OC/Kexts/" || { echo "copy to Kexts failed"; exit 1; }
  if [ "$(find_kext "$T" MeowXE3Boot.kext)" -lt 0 ]; then
    L=$(find_kext "$T" Lilu.kext); [ "$L" -lt 0 ] && P=$(count Kernel:Add "$T") || P=$((L+1))
    $PB -c "Add :Kernel:Add:$P dict" \
        -c "Add :Kernel:Add:$P:Arch string x86_64" \
        -c "Add :Kernel:Add:$P:BundlePath string MeowXE3Boot.kext" \
        -c "Add :Kernel:Add:$P:Comment string MeowXE3Boot: no boot-display framebuffer when nmxintel=1 (it blocks sleep); skipped with -nvoff" \
        -c "Add :Kernel:Add:$P:Enabled bool true" \
        -c "Add :Kernel:Add:$P:ExecutablePath string Contents/MacOS/MeowXE3Boot" \
        -c "Add :Kernel:Add:$P:MaxKernel string" \
        -c "Add :Kernel:Add:$P:MinKernel string" \
        -c "Add :Kernel:Add:$P:PlistPath string Contents/Info.plist" "$T"
  else $PB -c "Set :Kernel:Add:$(find_kext "$T" MeowXE3Boot.kext):Enabled true" "$T"; fi
  # 2. boot-args: nmxintel=1 turns the driver on
  BA=$(pbq "Print :NVRAM:Add:$G:boot-args" "$T")
  if ! echo " $BA " | grep -q ' nmxintel=1 '; then
    NB=$(echo "$BA nmxintel=1" | sed 's/^ *//')
    pbq "Set :NVRAM:Add:$G:boot-args $NB" "$T" || $PB -c "Add :NVRAM:Add:$G:boot-args string $NB" "$T"
  fi
  # 3. NVRAM nullmoth-fbflags=1833 (GPU compositing + panel flips), written by OpenCore every boot
  pbq "Delete :NVRAM:Add:$G:nullmoth-fbflags" "$T"; $PB -c "Add :NVRAM:Add:$G:nullmoth-fbflags data $FLAGS" "$T"
  [ "$(in_delete "$T" nullmoth-fbflags)" -ge 0 ] || $PB -c "Add :NVRAM:Delete:$G:$(count "NVRAM:Delete:$G" "$T") string nullmoth-fbflags" "$T"
  [ "$(in_delete "$T" boot-args)" -ge 0 ] || $PB -c "Add :NVRAM:Delete:$G:$(count "NVRAM:Delete:$G" "$T") string boot-args" "$T"
  # 4. the escape hatch: a picker entry that starts macOS once without the driver (adds -nvoff for one boot)
  if [ -f "$PAY/OpenCore/NullMothSafe.efi" ]; then
    cp "$PAY/OpenCore/NullMothSafe.efi" "$OC/Tools/" || { echo "copy to Tools failed"; exit 1; }
    if [ "$(find_tool "$T" NullMothSafe.efi)" -lt 0 ]; then
      P=$(count Misc:Tools "$T")
      $PB -c "Add :Misc:Tools:$P dict" \
          -c "Add :Misc:Tools:$P:Arguments string once" \
          -c "Add :Misc:Tools:$P:Auxiliary bool false" \
          -c "Add :Misc:Tools:$P:Comment string MeowXE3: start macOS once without the driver (-nvoff)" \
          -c "Add :Misc:Tools:$P:Enabled bool true" \
          -c "Add :Misc:Tools:$P:Flavour string Auto" \
          -c "Add :Misc:Tools:$P:FullNvramAccess bool true" \
          -c "Add :Misc:Tools:$P:Name string MeowXE3: start once without driver" \
          -c "Add :Misc:Tools:$P:Path string NullMothSafe.efi" \
          -c "Add :Misc:Tools:$P:RealPath bool false" \
          -c "Add :Misc:Tools:$P:TextMode bool true" "$T"
    fi
  fi
  lint_and_swap "$T"; summary "$CFG" ;;

remove)
  T=$(mktemp "$OC/.config-meowxe3.XXXXXX"); cp "$CFG" "$T"
  I=$(find_kext "$T" MeowXE3Boot.kext); [ "$I" -ge 0 ] && $PB -c "Delete :Kernel:Add:$I" "$T"
  BA=$(pbq "Print :NVRAM:Add:$G:boot-args" "$T")
  NB=$(echo " $BA " | sed 's/ nmxintel=1 / /g; s/^ *//; s/ *$//'); [ "$NB" != "$BA" ] && $PB -c "Set :NVRAM:Add:$G:boot-args $NB" "$T"
  pbq "Delete :NVRAM:Add:$G:nullmoth-fbflags" "$T"
  I=$(in_delete "$T" nullmoth-fbflags); [ "$I" -ge 0 ] && $PB -c "Delete :NVRAM:Delete:$G:$I" "$T"
  I=$(find_tool "$T" NullMothSafe.efi); [ "$I" -ge 0 ] && $PB -c "Delete :Misc:Tools:$I" "$T"
  lint_and_swap "$T"
  rm -rf "$OC/Kexts/MeowXE3Boot.kext" "$OC/Tools/NullMothSafe.efi"
  summary "$CFG" ;;
*) echo "unknown mode $MODE"; exit 2 ;;
esac
