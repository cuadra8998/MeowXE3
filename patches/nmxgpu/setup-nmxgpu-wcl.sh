#!/bin/bash
# setup-nmxgpu-wcl.sh: fetches and prepares everything to build NullMoth's NMXGPU (Linux 6.14 xe on macOS)
# for Wildcat Lake (8086:FD80) on bare metal, on this Intel Mac. It builds nothing and installs nothing.
#
# Sources (all fetched from their own upstreams at fixed commits):
#   NullMoth nvidia-macos-driver  c104f584  last public tree with gpu-port/ (removed in df2cff0); xkpi = d96eaca's
#   ericek111/vibe-nullmoth-xe3-qemu 7246d386  50 xkpi patches + 1 drm-kmod patch (VF guest work, mostly generic)
#   freebsd/drm-kmod              c16de0f9  DRM core / TTM at the Linux 6.14 level
#   freebsd/freebsd-src           d2145e9b  LinuxKPI (sys/compat), ck, acpica headers
#   torvalds/linux                v6.14     xe sources and uapi headers
#   linux-firmware                main      xe/ptl_guc_70.bin, xe/ptl_huc.bin, i915/xe3lpd_3002_dmc.bin
# plus 0051-wildcat-lake-bare-metal.patch (this folder): FD80/FD81 as Panther Lake, Xe3 graphics 30.03-30.05 and
# media 30.02 IP entries, and ericek's 0001 (.has_sriov) undone because bare metal is the physical function,
# and 0052-wildcat-lake-display-30.02.patch: the display 30.02 backport onto drm-kmod's 6.14 display code.
# and 0053-igpu-scanout-in-stolen-and-retire-boot-fb.patch: the display bridge on an integrated GPU (scan-out buffer
# in stolen memory so it is one physical run; the firmware's boot framebuffer retired once NMXGPU's is up).
# and 0054-build-fixes-macos26-sdk.patch: builds on the macOS 26 SDK (Apple's uuid_copy renamed in the prelude) and
# this FreeBSD's LinuxKPI (pci_drivers/pci_lock declared for the port's linux_pci.c fork).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${NULLMOTH_BUILD_ROOT:-$HOME/nmx}
SRC=$ROOT/build/gpu-src
mkdir -p "$SRC/kpi" "$ROOT/repos"
R=$ROOT/repos

need() { command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need git; need python3; need rsync
if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
    echo "Command Line Tools missing: run  xcode-select --install  then this script again"; exit 1
fi

fetch() {  # fetch <dir> <url> <commit-or-tag> [sparse paths...]
    local dir=$1 url=$2 rev=$3; shift 3
    if [ ! -d "$dir/.git" ]; then
        git init -q "$dir"; git -C "$dir" remote add origin "$url"
    fi
    if [ $# -gt 0 ]; then
        git -C "$dir" sparse-checkout init --cone >/dev/null 2>&1 || true
        git -C "$dir" sparse-checkout set "$@"
    fi
    echo "== $(basename "$dir") @ $rev"
    git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$rev"
    git -C "$dir" -c advice.detachedHead=false checkout -q -f FETCH_HEAD
}

# 1. NullMoth gpu-port, then ericek's 50 xkpi patches, then the Wildcat Lake patch
fetch "$R/nullmoth" https://github.com/nullmoth/nvidia-macos-driver c104f584b71515c8e30855e9048a902a012c3131 gpu-port
fetch "$R/ericek"   https://github.com/ericek111/vibe-nullmoth-xe3-qemu 7246d386e94a2f5e8fe4f8a17099d11514b0ae40
git -C "$R/nullmoth" reset -q --hard && git -C "$R/nullmoth" clean -qfdx gpu-port
for p in "$R"/ericek/patches/xkpi/*.patch; do git -C "$R/nullmoth" apply --whitespace=nowarn "$p"; done
git -C "$R/nullmoth" apply "$HERE/0051-wildcat-lake-bare-metal.patch"
git -C "$R/nullmoth" apply "$HERE/0053-igpu-scanout-in-stolen-and-retire-boot-fb.patch"
git -C "$R/nullmoth" apply "$HERE/0054-build-fixes-macos26-sdk.patch"
git -C "$R/nullmoth" apply "$HERE/0055-bringup-trace-checkpoints.patch"
git -C "$R/nullmoth" apply "$HERE/0056-wire-bar-mappings.patch"
git -C "$R/nullmoth" apply "$HERE/0057-share-bar-mappings-between-iomap-users.patch"
git -C "$R/nullmoth" apply "$HERE/0058-trace-breadcrumb-in-nvram.patch"
git -C "$R/nullmoth" apply "$HERE/0059-xe-display-probe-checkpoints.patch"
git -C "$R/nullmoth" apply "$HERE/0061-framebuffer-publish-checkpoints.patch"
git -C "$R/nullmoth" apply "$HERE/0063-scanout-buffer-checkpoints.patch"
git -C "$R/nullmoth" apply "$HERE/0065-stolen-scanout-buffer-cleared-by-cpu.patch"
git -C "$R/nullmoth" apply "$HERE/0066-xe-gem-vmap-for-the-display-bridge.patch"
git -C "$R/nullmoth" apply "$HERE/0067-coarse-nvram-breadcrumbs-and-fb-start-steps.patch"
git -C "$R/nullmoth" apply "$HERE/0068-iographics-callback-breadcrumbs.patch"
git -C "$R/nullmoth" apply "$HERE/0069-interrupt-heartbeat-and-storm-guard.patch"
git -C "$R/nullmoth" apply "$HERE/0070-fbstop-bisect-switch.patch"
git -C "$R/nullmoth" apply "$HERE/0071-fbflags-console-and-vblank-switches.patch"
git -C "$R/nullmoth" apply "$HERE/0072-nmxgpu-stays-powered-on.patch"
git -C "$R/nullmoth" apply "$HERE/0073-fbflags-no-framebuffer-power-driver.patch"
git -C "$R/nullmoth" apply "$HERE/0074-flight-recorder.patch"
git -C "$R/nullmoth" apply "$HERE/0075-irq-diagnostics-and-pV-in-the-flight-log.patch"
git -C "$R/nullmoth" apply "$HERE/0077-skip-the-registration-hotplug-commit.patch"
git -C "$R/nullmoth" apply "$HERE/0079-fbflags-keep-boot-fb-and-flight-log-truncation.patch"
git -C "$R/nullmoth" apply "$HERE/0080-retire-boot-framebuffer-before-the-attach.patch"
git -C "$R/nullmoth" apply "$HERE/0081-macos-side-power-watchers-and-synced-flight-log.patch"
git -C "$R/nullmoth" apply "$HERE/0082-framebuffer-iofbdependentid-for-the-iographics-controller.patch"
git -C "$R/nullmoth" apply "$HERE/0083-framebuffer-opt-in-iographics-power-handling.patch"
git -C "$R/nullmoth" apply "$HERE/0084-watchers-log-only-no-nvram-inside-iographics.patch"
git -C "$R/nullmoth" apply "$HERE/0085-framebuffer-retire-boot-fb-before-start.patch"
git -C "$R/nullmoth" apply "$HERE/0086-retire-boot-fb-after-windowserver-holds-it.patch"
git -C "$R/nullmoth" apply "$HERE/0087-retire-stop-appleupstreamuserclient-first.patch"
git -C "$R/nullmoth" apply "$HERE/0088-display-hold-synchronous-retire-flight-prealloc.patch"
git -C "$R/nullmoth" apply "$HERE/0089-retire-pause-hold-and-reenable-pci-decode.patch"
git -C "$R/nullmoth" apply "$HERE/0090-skip-redundant-dpms-shutdown-breadcrumbs.patch"
git -C "$R/nullmoth" apply "$HERE/0091-watchers-off-switch-and-flight-alive-line.patch"
git -C "$R/nullmoth" apply "$HERE/0092-flight-log-open-only-while-writing.patch"
git -C "$R/nullmoth" apply "$HERE/0093-flight-log-context-per-open.patch"
git -C "$R/nullmoth" apply "$HERE/0094-delayed-claim-for-nmxaccel-bring-up.patch"
git -C "$R/nullmoth" apply "$HERE/0095-accelerated-head-mode-for-nmxaccel.patch"
git -C "$R/nullmoth" apply "$HERE/0096-accelerated-head-nvrmtiming-for-nmxagdc.patch"
git -C "$R/nullmoth" apply "$HERE/0097-gpu-model-and-vram-for-system-information.patch"
git -C "$R/nullmoth" apply "$HERE/0098-double-buffered-panel-flips.patch"
git -C "$R/nullmoth" apply "$HERE/0099-flips-opt-in-timeout-keeps-visible-buffer.patch"
git -C "$R/nullmoth" apply "$HERE/0101-queued-flips-three-buffers.patch"
git -C "$R/nullmoth" apply "$HERE/0102-per-app-gpu-memory-report.patch"
git -C "$R/nullmoth" apply "$HERE/0103-drm-clients-labelled-with-their-process.patch"
git -C "$R/nullmoth" apply "$HERE/0105-panel-brightness.patch"
git -C "$R/nullmoth" apply "$HERE/0106-gpu-clock-report.patch"
git -C "$R/nullmoth" apply "$HERE/0107-clock-report-without-guc-queries.patch"
git -C "$R/nullmoth" apply "$HERE/0108-panther-lake-shipping-ids.patch"
echo "patches applied: 50 (ericek) + 0051 (Wildcat Lake) + 0053 (integrated-GPU display bridge) + 0054 (build fixes) + 0055 (bring-up checkpoints, off unless nmxtrace is set) + 0056 (checked BAR mappings) + 0057 (shared BAR mappings kept until the last user) + 0058 (nmxtrace=3 NVRAM breadcrumb) + 0059 (xe display-probe checkpoints) + 0061 (framebuffer publish checkpoints) + 0063 (scan-out buffer checkpoints) + 0065 (stolen scan-out buffer cleared by the CPU) + 0066 (xe GEM vmap) + 0067 (coarse NVRAM breadcrumbs) + 0068 (IOGraphics callback breadcrumbs) + 0069 (interrupt heartbeat) + 0070 (fbstop switch) + 0071 (fbflags switch) + 0072 (NMXGPU stays powered on) + 0073 (fbflags 0x4) + 0074 (flight recorder)"

# 2. drm-kmod with ericek's one patch, FreeBSD and Linux (only the parts the build reads)
fetch "$SRC/kpi/drm-kmod" https://github.com/freebsd/drm-kmod c16de0f9fa84f70b9551f69fde837a7f3a73c0e9
git -C "$SRC/kpi/drm-kmod" apply "$R"/ericek/patches/drm-kmod/*.patch
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0052-wildcat-lake-display-30.02.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0060-drm-kmod-display-probe-checkpoints.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0062-drm-kmod-modeset-commit-checkpoints.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0064-drm-kmod-client-buffer-checkpoints.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0076-drm-kmod-display-irq-checkpoints.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0078-drm-kmod-vblank-path-traces.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0100-drm-kmod-flips-without-dsb.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0104-drm-kmod-client-pid-is-the-process.patch"
git -C "$SRC/kpi/drm-kmod" apply "$HERE/0109-drm-kmod-panther-lake-shipping-ids.patch"
echo "display 30.02 backport applied (0052) + display probe and modeset checkpoints (0060, 0062, 0064)"
fetch "$SRC/kpi/freebsd-src" https://github.com/freebsd/freebsd-src d2145e9b96448da34d3cfede24c509af6d830c92 \
    sys/compat sys/contrib/ck sys/contrib/dev/acpica
fetch "$SRC/linux-6.14" https://github.com/torvalds/linux v6.14 drivers/gpu/drm/xe include/uapi
# NMXNPU's scripts look for gpu-src/linux; not built here, but keep the name resolvable
[ -e "$SRC/linux" ] || ln -s linux-6.14 "$SRC/linux"

# 3. xkpi in the layout the scripts expect, with this Mac's paths
cd "$R/nullmoth/gpu-port/xkpi"
PY=$(command -v python3)
for f in *.sh kext/*.sh kext-npu/*.sh; do
    [ -f "$f" ] || continue
    sed -i '' -e "s|/opt/homebrew/bin/python3|$PY|g" -e "s|/Volumes/MiniData/build/gpu-src|\$NULLMOTH_BUILD_ROOT/build/gpu-src|g" "$f"
done
chmod +x ./*.sh kext/*.sh
# a real copy, not a symlink: build-guest.sh makes relative links (../linux-6.14, ../../kpi) from inside xkpi
rm -rf "$SRC/xkpi"; cp -R "$R/nullmoth/gpu-port/xkpi" "$SRC/xkpi"

# 4. GPU firmware (installed later, by hand: see README)
fetch "$R/linux-firmware" https://gitlab.com/kernel-firmware/linux-firmware main xe i915
ls -l "$R/linux-firmware/xe/ptl_guc_70.bin" "$R/linux-firmware/xe/ptl_huc.bin" "$R/linux-firmware/i915/xe3lpd_3002_dmc.bin"

cat <<EOF

Ready. To build (30-90 minutes on this laptop):
  export NULLMOTH_BUILD_ROOT=$ROOT
  cd $SRC/xkpi && ./build-guest.sh all $ROOT/out
The kext lands in $ROOT/out/NMXGPU.kext. Read README-WCL.md before installing anything.
EOF
