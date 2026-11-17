#!/bin/bash
# build-mesa.sh [configure|build]: Mesa bffd91947ef + NullMoth's mesa-macos.patch + ericek111's 8 Mesa patches
# (~/nmx/src/mesa), Intel Vulkan (ANV) only, built natively for x86_64 macOS with Apple clang, the conda-forge toolchain
# in ~/nmx/toolchain (meson, ninja, bison, LLVM 21 + SPIR-V translator for mesa_clc) and our patched libdrm.
set -euo pipefail
T=$HOME/nmx/toolchain
SRC=$HOME/nmx/src/mesa
B=$HOME/nmx/src/mesa-build
export PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PKG_CONFIG_PATH=$HOME/nmx/src/sysroot/lib/pkgconfig:$T/lib/pkgconfig
export CC="xcrun clang" CXX="xcrun clang++" OBJC="xcrun clang"
export CFLAGS="-arch x86_64 -mmacosx-version-min=15.0" CXXFLAGS="-arch x86_64 -mmacosx-version-min=15.0"
export LDFLAGS="-arch x86_64 -mmacosx-version-min=15.0 -Wl,-rpath,$T/lib"
# wsi-configure / wsi-build: a second ANV with Metal window surfaces (VK_EXT_metal_surface, -Dplatforms=macos) for
# apps that use Vulkan directly (Minecraft 26.3+), in ~/nmx/src/mesa-build-wsi; the Metal plugin keeps the other one.
BW=$HOME/nmx/src/mesa-build-wsi
case "${1:-build}" in
wsi-configure)
  rm -rf "$BW"
  meson setup "$BW" "$SRC" --buildtype=release --prefix=/Library/GPUBundles/nvmtl/vk-wsi \
    -Dvulkan-drivers=intel -Dgallium-drivers= -Dplatforms=macos -Dglx=disabled -Degl=disabled -Dgles1=disabled \
    -Dgles2=disabled -Dopengl=false -Dllvm=enabled -Dshared-llvm=enabled -Dintel-rt=disabled -Dintel-elk=false \
    -Dvideo-codecs= -Dvalgrind=disabled -Dlibunwind=disabled -Dbuild-tests=false -Dtools= -Dzstd=disabled \
    -Dmesa-clc=auto -Dprecomp-compiler=auto
  ;;
wsi-build)
  ninja -C "$BW" src/intel/vulkan/libvulkan_intel.dylib
  ;;
configure)
  rm -rf "$B"
  meson setup "$B" "$SRC" --buildtype=release --prefix=/Library/GPUBundles/nvmtl \
    -Dvulkan-drivers=intel -Dgallium-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled -Dgles1=disabled \
    -Dgles2=disabled -Dopengl=false -Dllvm=enabled -Dshared-llvm=enabled -Dintel-rt=disabled -Dintel-elk=false \
    -Dvideo-codecs= -Dvalgrind=disabled -Dlibunwind=disabled -Dbuild-tests=false -Dtools= -Dzstd=disabled \
    -Dmesa-clc=auto -Dprecomp-compiler=auto
  ;;
build)
  ninja -C "$B" src/intel/vulkan/libvulkan_intel.dylib
  ;;
esac
