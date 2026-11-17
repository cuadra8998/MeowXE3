#!/bin/bash
# install-vk-wsi.sh [remove]: MeowXE3's Vulkan driver for apps that use Vulkan directly (Minecraft 26.3+): Intel ANV
# built with Metal window surfaces (VK_EXT_metal_surface, software present), at /Library/GPUBundles/nvmtl/vk-wsi, and
# its manifest in the Vulkan loader's own search folder (/Library/GPUBundles/nvmtl/etc/vulkan/icd.d). The Metal
# driver opens its own ANV directly and is not affected. Apps reach it with the loader
# /Library/GPUBundles/nvmtl/libvulkan.1.dylib (Minecraft: -Dorg.lwjgl.vulkan.libname=<that path>).
set -e
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
G=/Library/GPUBundles/nvmtl; D=$G/vk-wsi; I=$G/etc/vulkan/icd.d
if [ "${1:-}" = remove ]; then rm -rf $D $I/meowxe3_intel_icd.json; echo VK-WSI-REMOVED; exit 0; fi
mkdir -p $D $I
cp ${NMX:-$HOME/nmx}/src/vk-wsi/libvulkan_intel.dylib $D/.new && mv -f $D/.new $D/libvulkan_intel.dylib
cat > $I/meowxe3_intel_icd.json <<'J'
{
    "ICD": {
        "api_version": "1.4.363",
        "library_arch": "64",
        "library_path": "/Library/GPUBundles/nvmtl/vk-wsi/libvulkan_intel.dylib"
    },
    "file_format_version": "1.0.1"
}
J
chown -R root:wheel $D $G/etc; chmod 755 $D/libvulkan_intel.dylib; chmod 644 $I/meowxe3_intel_icd.json
ls -l $D $I; echo VK-WSI-INSTALLED
