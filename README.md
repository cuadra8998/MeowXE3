# MeowXE3
A Custom Vulkan to Metal DriverStack for Graphics Acceleration of Intel XE3 PantherLake / WildCat Lake Systems.

> [!NOTE]
> This kext is not guaranteed to always work and is in **ALPHA** stages. Still currently in Development.

> [!WARNING]
> **MeowXE3** is not responsible for any damages caused by using this driver on your machine. You are taking full responsibility for using **ALPHA** software.

```
        /\_/\      Metal  *  Vulkan  *  OpenGL (Zink)  *  GPU compositing  *  brightness
       ( o.o )     on the Intel Xe3 iGPU, macOS Tahoe 26, OpenCore
        > ^ <
```

## What works

| | |
|---|---|
| GPU compositing | WindowServer draws on the GPU, panel page flips without tearing |
| Metal | apps, System Information shows Metal, Maps, Chromium WebGL |
| Vulkan | native Intel Vulkan driver for apps (Minecraft 26.3+ at 60 fps) |
| OpenGL | through Mesa Zink on the Vulkan driver (Minecraft 1.12.2 and other GL apps) |
| Display | built-in panel, brightness slider (brightness keys on the X1504MA: [guide](docs/X1504MA-brightness-keys.md)) |

Not yet: sleep (disabled), audio, Safari WebGL/YouTube (Safari's sandbox blocks the driver).

> [!CAUTION]
> **Camera apps (Photo Booth, FaceTime, ...):** the preview is black, and leaving one running for a few minutes has
> caused a kernel panic. Avoid the camera until this is fixed.

**Tested on:** ASUS Vivobook X1504MA, Intel Wildcat Lake `8086:FD80`, macOS Tahoe 26.7, OpenCore 1.0.8.

**In the driver but never run on real hardware:** Wildcat Lake `FD81`, and Panther Lake `B080`–`B087`, `B08F`, `B090`–`B092`,
`B0A0`–`B0A2`, `B0B0`. They use the same firmware family and display generation, so they have a fair chance, but expect
problems. The installer warns you, and reports from these machines are very welcome.

**External displays (HDMI / USB-C):** untested. The driver lights every connected output with the same image, so at
best an external screen **mirrors** the built-in panel. An extended desktop on a second screen is not supported yet.

## Install

1. Download `MeowXE3-<version>.zip` from [Releases](../../releases) and unzip it.
2. Right-click **`Install MeowXE3.command`** > **Open** (macOS blocks a plain double-click on downloaded scripts),
   or in Terminal: `sudo bash ~/Downloads/MeowXE3-<version>/Install\ MeowXE3.command`
3. Choose **[1] install everything**, approve MeowXE3 in System Settings > Privacy & Security if asked, restart.

Try `--dry-run` first: it checks your Mac and prints the exact OpenCore changes on a copy, without changing anything.

### What the installer changes

**macOS:**
- `/Library/Extensions`: `MeowXE3.kext`, `MeowXE3Accel.kext`, `MeowXE3AGDC.kext`
- `/Library/GPUBundles`: the Metal driver, Vulkan, Zink
- `/Library/NullMoth/firmware`: Intel GuC/HuC/DMC firmware
- The auxiliary kext collection is rebuilt.

**OpenCore** (only after you say yes; a full copy of your `EFI` folder is saved in your home folder first):
- `Kexts/MeowXE3Boot.kext` plus a Kernel > Add entry. Without it the Mac can't fully sleep with the driver on.
- boot-args `nmxintel=1`. This is the on switch.
- NVRAM `nullmoth-fbflags` = `1833`: GPU compositing and page flips.
- `Tools/NullMothSafe.efi`, shown in the boot picker as **"MeowXE3: start once without driver"**.

It does **not** touch SIP, AMFI, ACPI/DSDT, SMBIOS or your other kexts. Every edit is checked with `plutil -lint`
before it is written.

### What you must set yourself

The installer checks these and tells you if they are missing, but leaves the decision to you:

- **SIP:** third-party kext loading allowed (Kext Signing disabled), e.g. `csr-active-config` = `030A0000`.
  MeowXE3's kexts are ad-hoc signed.
- **AMFI:** boot-args `amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0`. Apps load the Metal driver
  from `/Library/GPUBundles`, which is not Apple-signed. This lowers macOS security; understand that before you add it.

### If something goes wrong

- **Black screen or hang at boot:** in the OpenCore picker, choose **"MeowXE3: start once without driver"**, then
  pick macOS. That boot runs without MeowXE3.
- **Off for good:** run the installer > **[4] uninstall**, or remove `nmxintel=1` from boot-args.
- **Your old EFI:** it was saved to `~/MeowXE3-EFI-backup-<date>/EFI`. Copy it back to the EFI partition.
- **Log:** `/Users/Shared/MeowXE3-install.log`

## Minecraft / Java on Vulkan

LWJGL ships MoltenVK. To use MeowXE3's Vulkan driver instead, add this JVM argument (in Prism Launcher: Settings >
Java > JVM arguments):

```
-Dorg.lwjgl.vulkan.libname=/Library/GPUBundles/nvmtl/libvulkan.1.dylib
```

Then pick Vulkan in Minecraft 26.3+ Video Settings. Older OpenGL versions run through Zink automatically.

## More apps on Metal

Every app is allowed by default (`*` in `/Library/GPUBundles/nvmtl-allow.txt`). To manage the list:
`sudo bash /Library/GPUBundles/MeowXE3/allow-app.sh NAME` (`-r NAME` removes).

## Repository layout

| Path | What |
|---|---|
| `Install MeowXE3.command` | the installer (needs the release zip's `payload/` next to it) |
| `tools/oc-patch.sh` | OpenCore config edits, using Apple's PlistBuddy (`apply` / `remove` / `check`) |
| `tools/install-meowxe3.sh` | the driver part of the install |
| `tools/dev/` | `make-release.sh` (builds the release zip) and `repack.sh` (renames the NullMoth build outputs to MeowXE3) |
| `patches/nmxgpu/` | kernel driver patches for Wildcat Lake on NullMoth's NMXGPU (xe + i915 display on LinuxKPI) |
| `patches/nvidia-macos-driver/` | NMXAccel and Metal plugin patches |
| `patches/mesa/` | Mesa ANV patches (macOS Metal window surfaces) |
| `patches/zink/` | Zink on Intel: `0001` on Mesa 26.3.0 @0a6fa60 after HighDelay's `prepare_zink.py`, `0002` on HighDelay's CGL/GLD bridge |
| `tools/build/` | build and install scripts for Mesa ANV, Zink, the translator and the Metal plugin (expect sources under `$NMX`, default `~/nmx`) |
| `tools/tests/` | Metal regression tests (compute, render, mipmapped buffer textures) |
| `tools/com.meowxe3.java-vulkan.plist` | optional LaunchAgent: every Java program uses MeowXE3's Vulkan driver |
| `src/MeowXE3Boot/` | the small OpenCore-injected kext |
| `docs/` | [findings and open problems](docs/FINDINGS.md), [X1504MA brightness keys](docs/X1504MA-brightness-keys.md) |
| `EFI-X1504MA/` | the OpenCore EFI this was developed on (serials removed), as a reference |

The binaries (about 340 MB, including LLVM) are in the release zip, not in git.

## License and credits

MeowXE3 is a renamed, modified build of [NullMoth](https://github.com/nullmoth/nvidia-macos-driver) with patches by
ericek111 and the MeowXE3 patches in this repository. It is under the **PolyForm Noncommercial 1.0.0** license
(`LICENSE-NullMoth.md`): **noncommercial use only**, and keep the notice.

Required Notice: Copyright (c) 2026 NullMoth Systems (https://nullmothsystems.com)

These parts keep their own licenses: Mesa (MIT), libdrm (MIT), the Linux xe/i915 code (MIT/GPL-2.0, as marked in each
file), LLVM (Apache-2.0 with LLVM exception), zstd (BSD), and Intel's linux-firmware blobs (redistribution allowed
under Intel's license). See `NOTICE.md`.
