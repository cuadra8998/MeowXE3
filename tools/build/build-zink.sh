#!/bin/bash
# build-zink.sh: MeowXE3's Zink (Mesa 26.3.0 @0a6fa60 in ~/nmx/src/mesa-zink, prepared once with HighDelay's
# prepare_zink.py and then adapted to Intel ANV) -> ~/nmx/src/zink-out/libnvk_zink.dylib. HighDelay's build_zink.sh
# minus its prepare step, which would copy their NVK-only front end back over the Intel changes.
set -euo pipefail
T=$HOME/nmx/toolchain; SRC=$HOME/nmx/src/mesa-zink; B=$HOME/nmx/src/mesa-zink-build; OUT=$HOME/nmx/src/zink-out
REPO=$HOME/nmx/repos/highdelay
export PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin PKG_CONFIG_PATH=$T/lib/pkgconfig CC="xcrun clang" CXX="xcrun clang++" OBJC="xcrun clang"
args=(-Dbuildtype=release -Dc_args=-mmacosx-version-min=15.5 -Dcpp_args=-mmacosx-version-min=15.5 -Dc_link_args=-mmacosx-version-min=15.5 -Dcpp_link_args=-mmacosx-version-min=15.5 -Dgallium-drivers=zink -Dvulkan-drivers= -Dplatforms=
      -Degl=disabled -Dglx=disabled -Dgbm=disabled -Dglvnd=disabled
      -Dllvm=disabled -Dshared-glapi=disabled -Dvulkan-layers= -Dtools=
      -Dbuild-tests=false -Dexpat=disabled -Dzstd=disabled -Dlibunwind=disabled
      -Dlmsensors=disabled -Dvalgrind=disabled -Dxlib-lease=disabled
      -Dgallium-rusticl=false -Dspirv-tools=disabled -Dmoltenvk-dir=)
mkdir -p "$OUT"
if [ -f "$B/build.ninja" ]; then meson setup --reconfigure "$B" "$SRC" "${args[@]}"; else meson setup "$B" "$SRC" "${args[@]}"; fi
ninja -C "$B" -j 8 src/gallium/targets/nvk-zink/libnvk_zink.dylib
cp "$B/src/gallium/targets/nvk-zink/libnvk_zink.dylib" "$OUT/"
cp "$REPO/zink/nvk_zink.h" "$SRC/src/gallium/targets/nvk-zink/cgl-api-requirements.json" "$OUT/"
install_name_tool -id @rpath/libnvk_zink.dylib "$OUT/libnvk_zink.dylib"
install_name_tool -add_rpath /Library/GPUBundles/nvmtl "$OUT/libnvk_zink.dylib" 2>/dev/null || true
codesign --force --sign - "$OUT/libnvk_zink.dylib"
echo "ZINK-BUILT $(ls -la "$OUT/libnvk_zink.dylib" | awk '{print $5}') bytes"
