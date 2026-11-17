#!/bin/bash
# install-metal.sh [uninstall]: NullMoth 2.0.2's prebuilt Intel Metal path beside our NMXGPU, laid out as its installer
# does: NMXAccel.kext (macOS 26 build) in /Library/Extensions and the Auxiliary KC; the Metal plugin (NVMTLDriver.bundle,
# with the AIR->SPIR-V translator), the Vulkan loader, air-opt, Mesa ANV (libvulkan_intel) and libdrm in
# /Library/GPUBundles. The plugin's allow list admits only nmx-metal-test for now. NMXAccel starts only on a GPU NMXGPU
# has claimed, so normal boots (NMXGPU parked) are unaffected. Run with sudo.
set -u
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
S=${NMX:-$HOME/nmx}/downloads/nullmoth-2.0.2/stage/pkgroot
GB=/Library/GPUBundles
if [ "${1:-}" = uninstall ]; then
  rm -rf /Library/Extensions/NMXAccel.kext "$GB/NVMTLDriver.bundle" "$GB/nvmtl" "$GB/nvmtl-allow.txt"
  echo "removed; the Auxiliary KC drops NMXAccel when it is next rebuilt (kmutil load -p of NMXGPU or a restart)"
  exit 0
fi
[ -d "$S/Library/NullMoth/kexts/26/NMXAccel.kext" ] || { echo "staged files missing in $S"; exit 1; }
mkdir -p "$GB/nvmtl" || exit 1
ditto "$S/Library/GPUBundles/NVMTLDriver.bundle" "$GB/NVMTLDriver.bundle" || exit 1
for f in air-opt libvulkan.1.4.362.dylib; do ditto "$S/Library/GPUBundles/nvmtl/$f" "$GB/nvmtl/$f" || exit 1; done
ln -sf "$GB/nvmtl/libvulkan.1.4.362.dylib" "$GB/nvmtl/libvulkan.1.dylib"
ln -sf "$GB/nvmtl/libvulkan.1.dylib" "$GB/nvmtl/libvulkan.dylib"
for f in intel_icd.json libvulkan_intel.dylib libdrm.2.dylib; do
  ditto "$S/Library/NullMoth/gpu-userland/$f" "$GB/nvmtl/$f" || exit 1
done
printf '%s\n' "# NMXGPU bring-up: only the test program gets the GPU for now" "nmx-metal-test" > "$GB/nvmtl-allow.txt"
chown -R root:wheel "$GB" && chmod -R go-w "$GB"
rm -rf /Library/Extensions/NMXAccel.kext
ditto "$S/Library/NullMoth/kexts/26/NMXAccel.kext" /Library/Extensions/NMXAccel.kext || exit 1
chown -R root:wheel /Library/Extensions/NMXAccel.kext && chmod -R 755 /Library/Extensions/NMXAccel.kext
echo "loading NMXAccel into the Auxiliary KC (approve it in System Settings > Privacy & Security if asked)"
kmutil load -p /Library/Extensions/NMXAccel.kext 2>&1 | tail -3
ls -la "$GB" "$GB/nvmtl"
echo "METAL-INSTALLED"
