#!/bin/bash
# build-nmxaccel.sh [out]: NullMoth 2.0.2's build/nmxaccel_build.sh for NMXAccel.kext (kexts/NVRM/accel, -DNMX_ACCEL).
# MEOWXE3_TARGET=26 (default) is the macOS 26 build (-DNM_TAHOE: Tahoe's IOAccelerator vtable slots); MEOWXE3_TARGET=15 is
# the macOS 15 Sequoia build, as NullMoth's accel_build_all.sh makes it (the same source without NM_TAHOE). Both are
# linked for macOS 15.0 so the one SDK builds either, with NVIDIA open-gpu-kernel-modules 610.57.04's headers (~/nmx/src/ogkm610, a sparse
# checkout) and the RM defines of src/nvidia/Makefile in place of NullMoth's generated compile_cmds.sh, which is not
# published; as in NullMoth's script, -DNVRM and -D_LANGUAGE_C are left out.
set -uo pipefail
TARGET=${MEOWXE3_TARGET:-26}
case $TARGET in 26) TAHOE=(-DNM_TAHOE); SUF=;; 15) TAHOE=(); SUF=-15;; *) echo "MEOWXE3_TARGET must be 15 or 26"; exit 1;; esac
SRC=$HOME/nmx/src/nvmd/kexts/NVRM; OUT=${1:-$HOME/nmx/src/nmxaccel-out$SUF}; mkdir -p "$OUT/NMXAccel.kext/Contents/MacOS"
OGKM=$HOME/nmx/src/ogkm610; RE=$SRC/accel/re
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"; NV="$OGKM/src/nvidia"; KMS="$OGKM/src/nvidia-modeset"
RMINC=( -I"$NV/arch/nvalloc/unix/include" -I"$NV/arch/nvalloc/common/inc" -I"$NV/arch/nvalloc/common/inc/gsp"
  -I"$OGKM/src/common/sdk/nvidia/inc" -I"$OGKM/src/common/sdk/nvidia/inc/hw" -I"$OGKM/src/common/inc"
  -I"$OGKM/src/common/shared/inc" -I"$NV/inc" -I"$NV/inc/os" -I"$NV/inc/kernel" -I"$NV/kernel/inc" -I"$NV/interface"
  -I"$OGKM/src/common/nvlink/interface" -I"$OGKM/src/common/inc/swref" -I"$OGKM/src/common/inc/swref/published"
  -I"$NV/inc/libraries" -I"$NV/src/libraries" -I"$NV/generated" -I"$NV/src/mm/uvm/interface"
  -I"$OGKM/src/common/uproc/os/libos-v2.0.0/include" -I"$OGKM/src/common/uproc/os/common/include"
  -I"$OGKM/src/common/inc/displayport" -I"$OGKM/src/common/nvlink/inband/interface" )
KMSINC=( -I"$KMS/os-interface/include" -I"$KMS/kapi/interface" -I"$KMS/kapi/include" -I"$OGKM/src/common/unix/nvidia-push/interface" -I"$KMS/interface" -I"$KMS/include"
         -I"$OGKM/src/common/unix/common/inc" -I"$OGKM/src/common/modeset" -I"$OGKM/src/common/unix/common/utils/interface" )
RMDEFS=( -D__NO_CTYPE -DLOCK_VAL_ENABLED=0 -DPORT_ATOMIC_64_BIT_SUPPORTED=1 -DPORT_IS_KERNEL_BUILD=1 -DPORT_IS_CHECKED_BUILD=0
  -DPORT_MODULE_atomic=1 -DPORT_MODULE_core=1 -DPORT_MODULE_cpu=1 -DPORT_MODULE_crypto=1 -DPORT_MODULE_debug=1
  -DPORT_MODULE_memory=1 -DPORT_MODULE_safe=1 -DPORT_MODULE_string=1 -DPORT_MODULE_sync=1 -DPORT_MODULE_thread=1
  -DPORT_MODULE_time=1 -DPORT_MODULE_util=1 -DPORT_MODULE_example=0 -DPORT_MODULE_mmio=0 -DRS_STANDALONE=0
  -DRS_STANDALONE_TEST=0 -DRS_COMPATABILITY_MODE=1 -DRS_PROVIDES_API_STATE=0 -DNV_CONTAINERS_NO_TEMPLATES
  -DINCLUDE_NVLINK_LIB -DINCLUDE_NVSWITCH_LIB -DNV_PRINTF_STRINGS_ALLOWED=1 -DNV_ASSERT_FAILED_USES_STRINGS=1
  -DPORT_ASSERT_FAILED_USES_STRINGS=1 -DNV_X86_64 -DNV_ARCH_BITS=64 )
CFLAGS=( -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$SRC" "${RMINC[@]}" "${KMSINC[@]}"
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT "${RMDEFS[@]}" -DNMX_ACCEL "${TAHOE[@]}" -mmacosx-version-min=15.0
  -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common
  -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -Wno-unused-function -O2 )
xcrun clang++ "${CFLAGS[@]}" -I"$SRC/accel" -I"$SRC/accel/iofam" -I"$RE" -c "$SRC/accel/nvrm-accel.cpp" -o "$OUT/nmx-accel.o" 2>"$OUT/nmxaccel.err" || { grep -m12 -A3 "error" "$OUT/nmxaccel.err"; exit 1; }
xcrun clang++ -arch x86_64 -mmacosx-version-min=15.0 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext "$OUT/nmx-accel.o" -o "$OUT/NMXAccel.kext/Contents/MacOS/NMXAccel" 2>"$OUT/nmxaccelld.err" || { head -20 "$OUT/nmxaccelld.err"; exit 1; }
cp "$SRC/accel/nmx/Info.plist" "$OUT/NMXAccel.kext/Contents/Info.plist"
echo "NMXAccel (macOS $TARGET) $(md5 -q "$OUT/NMXAccel.kext/Contents/MacOS/NMXAccel") $(stat -f %z "$OUT/NMXAccel.kext/Contents/MacOS/NMXAccel") B  warnings $(grep -c 'warning:' "$OUT/nmxaccel.err")"
