# Continuing MeowXE3 work

A hand-off for whoever picks this up next, including a fresh Claude session pointed at this repo. Read this, then
[FINDINGS.md](FINDINGS.md) for what works, what doesn't and what has already been tried.

## State on 2026-11-17

| Thing | Version / state |
|---|---|
| Released | **v1.0.12** (GitHub release): MeowXE3.kext 1.0.12, Accel/AGDC 1.0.12, Metal plugin with patches 0048-0062 |
| Hardware | ASUS Vivobook X1504MA, Intel Wildcat Lake `8086:FD80`, 16 GB RAM, macOS Tahoe 26.7.3, OpenCore 1.0.8 |
| EFI | `EFI-X1504MA/` (serials removed; regenerate them with GenSMBIOS for MacBookPro16,2) |
| Parked | camera fix: `patches/experimental/plugin-camera-wip-shaderwrite-via-twin.patch` (not released) |
| Dropped | audio (HD Audio route can't reach the SoundWire RT721): patches 0110-0112, kept for reference |
| Photo Booth | excluded from Metal on the dev machine (`-Photo Booth` at the top of `/Library/GPUBundles/nvmtl-allow.txt`) |

## Where everything comes from (pinned)

| Component | Upstream | Pin | Our patches |
|---|---|---|---|
| NMXGPU (kernel) | github.com/nullmoth/nvidia-macos-driver `gpu-port/` | `c104f584b71515c8e30855e9048a902a012c3131` | ericek111's `patches/xkpi` (repo below), then `patches/nmxgpu/0051-0112` |
| xkpi helpers | github.com/ericek111/vibe-nullmoth-xe3-qemu | `7246d386e94a2f5e8fe4f8a17099d11514b0ae40` | (source of ericek's xkpi, drm-kmod, mesa 0001-0008, libdrm patches) |
| drm-kmod | github.com/freebsd/drm-kmod | `c16de0f9fa84f70b9551f69fde837a7f3a73c0e9` | ericek's + 0052, 0060, 0062, 0064, 0076, 0078, 0100, 0104, 0109 |
| FreeBSD | github.com/freebsd/freebsd-src (sparse: sys/compat, sys/contrib/ck, sys/contrib/dev/acpica, sys/dev/sound) | `d2145e9b96448da34d3cfede24c509af6d830c92` | 0110 (audio only) |
| Linux xe | github.com/torvalds/linux | `v6.14` (drivers/gpu/drm/xe, include/uapi) | via `fork_xe.py` edits in 0051, 0108 |
| Metal plugin + NMXAccel + NMXAGDC | github.com/nullmoth/nvidia-macos-driver | `d96eaca` (2.0.2) + ericek's `patches/nvidia-macos-driver` | `patches/nvidia-macos-driver/0048-0062` |
| Mesa (ANV, Vulkan) | Mesa `bffd91947ef` | + `patches/base/mesa-macos-d96eaca.patch` + ericek's mesa 0001-0008 | `patches/mesa/0009-0011` |
| libdrm | `b97cbde` | + `patches/base/libdrm-macos-d96eaca.patch` + ericek's libdrm 0001-0005 | none |
| Zink (OpenGL) | Mesa `0a6fa60abb737d26ac8a316a4aad7c9ddf64f9e4` + github.com/HighDelay/nvidia-macos-driver-nvk `08085cc` (`build/prepare_zink.py`, CGL/GLD bridge) | | `patches/zink/0001` (Mesa tree), `0002` (bridge) |

`patches/nmxgpu/setup-nmxgpu-wcl.sh` fetches the kernel-side sources at these pins and applies everything in order. It
expects the build root in `NULLMOTH_BUILD_ROOT` (we used `~/nmx`).

## Layout on the dev machine (`~/nmx`)

```
~/nmx/build/gpu-src/xkpi        NMXGPU build tree (setup script output); audio port in xkpi/audio
~/nmx/build/gpu-src/kpi         drm-kmod, freebsd-src
~/nmx/src/nvmd                  nullmoth/nvidia-macos-driver checkout: branch ui-fixes-3.0 (released), camera-wip
~/nmx/src/mesa                  Mesa + patches (ANV), build: tools/build/build-mesa.sh
~/nmx/src/mesa-zink             Zink Mesa tree; ~/nmx/src/meowzink-repo = HighDelay bridge working copy
~/nmx/MeowXE3                   the package folder (kexts, GPUBundles, firmware, OpenCore) -> tools/dev/repack.sh
~/nmx/MeowXE3-repo              this repo
~/Downloads/nmxgpu-wcl-v3       patch staging (mirrors patches/ here)
```

## Rebuilding

| Part | Command |
|---|---|
| NMXGPU, full | `cd ~/nmx/build/gpu-src/xkpi && NULLMOTH_BUILD_ROOT=$HOME/nmx ./build-guest.sh all ~/nmx/out` |
| NMXGPU, after xe / runtime changes | `... ./build-guest.sh xert ~/nmx/out` (the shared ID header needs this too) |
| NMXAccel | `tools/build/build-nmxaccel.sh` (needs NVIDIA open-gpu-kernel-modules 610.57.04 headers in `~/nmx/src/ogkm610`) |
| NMXAGDC | `~/nmx/src/nvmd/kexts/NMXAGDC/build.sh <out>` |
| Metal plugin | `cd ~/nmx/src/nvmd/plugin && xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -Wno-protocol -Wno-incomplete-implementation -I$HOME/nmx/src/mesa/include -o ~/nmx/src/nvmtl-out/NVMTLDriver NVMTLDevice.m -framework Foundation -framework Metal -framework IOSurface -framework IOKit` |
| Shader translator | `~/nmx/src/nvmd/build/build_xlate.sh`, install with `tools/build/install-translator.sh` |
| Mesa ANV / Vulkan WSI | `tools/build/build-mesa.sh` (`wsi-configure`, `wsi-build`), `tools/build/install-vk-wsi.sh` |
| Zink | `tools/build/build-zink.sh`, `tools/build/install-zink-update.sh` |
| Sequoia release | `tools/build/build-sequoia.sh <version> <NullMothSafe.efi>` after the Tahoe package is built ([SEQUOIA.md](SEQUOIA.md)) |
| Package + release | `tools/dev/repack.sh <version>` (bump it, or kmutil won't rebuild) then `tools/dev/make-release.sh <version> ~/nmx/MeowXE3 <NullMothSafe.efi>` |

**Before installing a new kext:** compare `nm -u` with the installed one. Run the Metal tests in `tools/tests`
(`nmx-metal-test`, `nmx-metal-render`, `buftex-mip`) after every plugin install. Plugin-only changes need no restart:
apps pick up the new plugin when relaunched, and WindowServer at the next login.

## Rules we kept

- The user does every restart and types every sudo password.
- Never change SIP / `csr-active-config` or the AMFI boot-args. Back up the EFI before any change, show the config diff,
  and lint it with `plutil`.
- Never publish a config.plist with serials. Never send personal data anywhere.
- Weakening Safari's sandbox (NVWebKitFixup) needs the user's explicit OK.
- Escape hatch: the OpenCore picker entry "NMXGPU: start once without driver" (NullMothSafe.efi sets `-nvoff` for one
  boot).

## Open threads and where to start

1. **Camera:** start from the experimental patch. Log which texture Core Image still refuses, and follow one frame from
   Core Image's output to the screen. To catch the panic, run `tools/build/camera-panic-test.sh`.
2. **HDMI hot-plug:** `bridge_hotplug` in `override/src/nmx_fb_bridge.c`. It re-commits outside `flip_lock` and caps
   modes at the panel size.
3. **Sleep:** S3 fails in firmware (wake code `0x1f`). `tools/build/sleep-test.sh` records a run.
   **Hibernation (S4)** is the way around it and is wanted. [Issue #1](https://github.com/cuadra8998/MeowXE3/issues/1)
   (Lunar Lake, `hibernatemode 25`): the machine resumes and xe works, but NMXAccel never presents again (no
   `nmxScanoutBack`/`nmxScanoutFlip`, no `displayModeWillChange/DidChange`). NMXAccel has no sleep/wake code of its own
   (only the framebuffer kexts do). Start by checking whether the display pipe stays busy (`isTransactionComplete`)
   and what the head reports after wake.
   **Log out → log in hangs** (beachball, then the whole system's log stops; restart needed), also with the original
   1.0.12 accelerator and plugin (tested 2026-11-23, Sequoia 15.8.3). WindowServer stays up across the logout; the log
   ends right after the new session's `CGXConstructVirtualFramebuffer` / `CGXVFBSelectOnlineState` (an 8192x4320
   virtual framebuffer surface is made, as at every boot, where it does not hang). Restarting instead of logging out
   avoids it.
4. **Audio:** only via SOF + SoundWire + RT721 (large), or USB/Bluetooth. Don't retry plain HD Audio for the speakers.
5. **Safari:** port NullMoth's NVWebKitFixup, only with the user's OK.
6. **Minecraft 1.12.2 speed:** Zink presentation copies (~30 fps).
7. **Rebase onto NullMoth 3.0:** the GPU/audio parts moved to a separate NullMoth repository after 2.9. Check what it
   has before porting more by hand.
