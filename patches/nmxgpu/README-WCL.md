# NMXGPU on Wildcat Lake (8086:FD80), bare metal: first bring-up

Goal of this round: Linux 6.14's `xe` (NullMoth's NMXGPU) takes the GPU, loads the GuC/HuC/DMC firmware, brings the
render engines up and drives the built-in panel itself with the backported display 30.02 code. No acceleration yet.

What 0051-wildcat-lake-bare-metal.patch changes (on NullMoth's gpu-port + ericek's 50 xkpi patches):
- FD80/FD81 added to xe's device table as `ptl_desc` (what current Linux does) and to NMXGPU's force-probe list.
- Graphics IP 30.03/30.04/30.05 and media IP 30.02 added (later Linux treats them like 30.00). Their newer
  workaround rules are NOT backported yet.
- ericek's 0001 (`.has_sriov = true`) undone: on bare metal the GPU is the physical function.

What 0052-wildcat-lake-display-30.02.patch changes (on drm-kmod's 6.14 display code, which xe compiles):
- Every upstream Linux commit specific to display 30.02 / Wildcat Lake: device info (3 pipes; ports A, B, TC1,
  TC2), power wells, 480 MHz max CDCLK, its own DMC firmware (`i915/xe3lpd_3002_dmc.bin`), C10 PHYs on A and B,
  22 GB/s bandwidth limit, HBR3 max link rate, one scaler per pipe, no pipe joiner, its workarounds.
- The Panther Lake fixes it depends on that came after 6.14: the 5-bit DDI clock select, Xe3 CDCLK_CTL
  programming, Xe3 bandwidth parameters, min plane width.
- Bring-up safety: panel self refresh (PSR), framebuffer compression (FBC) and DC5/DC6 power states start OFF on
  this display. The log says `WCL bring-up: PSR 0, FBC 0, DC 0`. They come back once the panel works.
- Not backported (not needed for the internal panel): VRR timing generator always-on, PHY idle power workaround,
  pipe C DMC reload, external-display dot-clock cap and YUV420 pruning.

Nothing here has been compiled yet. Expect the first build to need fixes.

What 0053-igpu-scanout-in-stolen-and-retire-boot-fb.patch changes (NullMoth's display bridge was written for discrete
AMD cards, where the screen buffer is contiguous VRAM):
- On an integrated GPU the bridge's screen buffer goes into stolen memory, GGTT-mapped, which is one physical run, as
  Linux's own fbdev does on Intel. Xe3 reaches stolen directly through BAR2. Without this the bridge refuses
  ("not physically contiguous") and macOS gets no NMXGPU framebuffer.
- Once NMXGPU's framebuffer is up, the firmware boot framebuffer on the same GPU (IONDRVFramebuffer) is retired,
  the way an unplugged display goes away. Otherwise WindowServer keeps a phantom second display drawing into
  memory xe has freed. Boot argument `-nmxkeepndrv` keeps it.

Machine-specific checks already done against your tables and config: the GPU's ACPI (SSDT16 `IgfxSsdt`: OpRegion at
`ASLS`, VBT inline or at `RVDA`, `_DSM`, `_DOD` with the eDP panel) is standard Intel and is read through macOS's own
ACPI, not interpreted by the port; no WhateverGreen or GPU device properties in the EFI to conflict; Tahoe's Intel
graphics kexts only match Ice Lake IDs.

## 1. Prepare and build (no system changes)

```sh
bash setup-nmxgpu-wcl.sh
export NULLMOTH_BUILD_ROOT=$HOME/nmx
cd $HOME/nmx/build/gpu-src/xkpi && ./build-guest.sh all $HOME/nmx/out
```

It ends with `compile failures: N`. If N > 0, send the error lines it prints. Success leaves
`$HOME/nmx/out/NMXGPU.kext` (about 15 MB).

## 2. One-time system setup

- OpenCore `config.plist`:
  - Misc → Security → `SecureBootModel` = `Disabled` (already done).
  - NVRAM → Add → `7C436110-...` → `csr-active-config` = `03080000` (data). This allows a kext you built
    yourself in the Auxiliary Kernel Collection. Reboot once after changing it.
  - Remove `NMIntelFB.kext` and `nmhybrid=1` for these tests: both drivers match the Intel GPU. Test one at a time.
- Firmware:
  ```sh
  sudo mkdir -p /Library/NullMoth/firmware/xe /Library/NullMoth/firmware/i915
  sudo cp ~/nmx/repos/linux-firmware/xe/ptl_guc_70.bin ~/nmx/repos/linux-firmware/xe/ptl_huc.bin /Library/NullMoth/firmware/xe/
  sudo cp ~/nmx/repos/linux-firmware/i915/xe3lpd_3002_dmc.bin /Library/NullMoth/firmware/i915/
  ```

## 3. Install (harmless until opted in)

```sh
sudo cp -R ~/nmx/out/NMXGPU.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/NMXGPU.kext
sudo kmutil install --update-all
```

Approve it in System Settings → Privacy & Security if asked, then reboot. NMXGPU now loads at every boot but
declines the GPU unless opted in, so nothing changes yet.

## 4. Test boot (one shot)

```sh
sudo nvram nullmoth-gpu-once=1
```

Turn AirportItlwm off for this boot (its log spam pushes NMXGPU's lines out of `dmesg`), reboot with `-v`, and film
the verbose screen. The variable is consumed during that boot, so the next boot is back to normal no matter what.
NMXGPU also parks the GPU on the next start if an attach never returned.

Expect the panel to blink or go black for a second when xe takes it over from the boot framebuffer (a modeset).
If it stays black or freezes: wait 2 minutes, hold the power button, boot again (normal), and send the video.
The boot argument `-nvoff` also keeps NMXGPU off for a start.

After the test boot:

```sh
ioreg -l -w0 | grep -E "NMXGPU|nullmoth-gpu"
sudo dmesg | grep -i -E "xe 0000|nmx|nullmoth|guc|huc|drm" | head -80
```

Before the test, note what drives the screen now (send it along with the results):
`ioreg -l -w0 -p IOService | grep -E "IONDRV|IOFramebuffer|GFX0" | head`

Lines to look for: `NullMoth: scan-out buffer in stolen memory`, `NullMoth display: 1920x1080 ... phys 0x...`,
`retiring the boot framebuffer IONDRVFramebuffer`, `Found pantherlake/wildcatlake ... display version 30.02` (backport active),
`WCL bring-up: PSR 0, FBC 0, DC 0`, `Finished loading DMC firmware i915/xe3lpd_3002_dmc.bin`,
`Using GuC firmware ... ptl_guc_70.bin`, anything with `[ENCODER` / `eDP` / `link training` / `underrun`, `Hardware reports unknown graphics/media version` (an IP version we have
not added yet: send the number), and any `failed` / `error`.

## Undo

`sudo rm -rf /Library/Extensions/NMXGPU.kext && sudo kmutil install --update-all`, reboot.

## GPU compositing with panel flips (2026-11-15)

`sudo bash ~/nmx/setup-compositing-test.sh` arms a one-boot test with nullmoth-fbflags 1833:
0x400 panel flips | 0x200 accelerated head | 0x100 watchers off | 0x20 IOGraphics power | 0x8 keep boot fb | 0x1 not console.
0x400 (patches 0099/0100) double-buffers the panel and flips with MMIO commits (no DSB: its completion interrupt never
fired on Wildcat Lake). Result: no tearing, ~60 flips/s, Metal window test 58 fps. Pass 809 for the old copy path.
