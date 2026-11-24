# MeowXE3 findings and open problems

Notes from bringing up the Intel Wildcat Lake Xe3 iGPU (`8086:FD80`, ASUS Vivobook X1504MA) on macOS Tahoe 26.7 with
OpenCore, written down so the next person (or the next session) does not start from zero. Patch numbers refer to
`patches/`.

## What works and the fixes behind it

| Area | State | Key fixes |
|---|---|---|
| Panel / boot | works | `nmxintel=1`; MeowXE3Boot.kext sets `AAPL,iokit-ignore-ndrv` so no boot framebuffer blocks sleep |
| GPU compositing | works | NVRAM `nullmoth-fbflags` = `1833` (0x400 flips, 0x200 accelerated head, 0x100, 0x20, 0x8, 0x1) |
| Tearing | fixed | flips opt-in (0099); drm-kmod commits without the DSB path, whose completion never came on WCL (0100); three queued buffers (0101) |
| Metal | works (Metal 3) | NullMoth's NVMTL plugin + Mesa ANV; no soft VRAM gate on unified memory (0054) |
| Vulkan apps | works | ANV built with Metal surfaces (Mesa 0010); present by `replaceRegion` (Mesa 0011: a no-copy MTLBuffer over the swapchain pinned pages and hung maximize) |
| OpenGL | works through Zink | `patches/zink`; Intel needs the GPU present path (native present gave zero pixels) |
| Brightness | works | backlight through xe (0105); keys need DSDT edits ([guide](X1504MA-brightness-keys.md)) |
| Dock badges, login picture | fixed | WindowServer asks for mipmapped buffer textures; one-level live view instead of nil (plugin 0061) |
| UI from NullMoth 3.0 | ported | 0055-0060: heap swizzle, managed-upload order, Dock blur sampler restore |
| GPU hangs | fixed | periodic GuC min/max frequency queries hung the render engine; removed (0107) |

## Open problems

### Sleep: disabled
The firmware's S3 path fails in EFI (wake ends at code `0x1f`). With MeowXE3Boot the Mac reaches real sleep, but it
does not come back. Sleep is turned off.

### Camera: works in browsers; Apple's apps show a black preview and Photo Booth can panic
The camera and capture stack work: browsers show the camera (tested). The problem is how Apple's own apps draw the
preview through Core Image on the Metal driver.
- **Panic:** `thread_invoke: preemption_level -1 ... unlocking an unlocked mutex or spinlock`, in Photo Booth's process.
  Two of three runs with Metal panicked (after 6 min and after ~1 min). Reviewed and found balanced: the port's spin mutex
  (unused; Linux spinlocks map to sleeping `lck_mtx`), the callout and malloc spin locks, `nmx_critical_*` (interrupts
  only), and NMXAccel's IOSimpleLocks and family lock. Unverified suspect: NMXAccel writes Apple's IOSurfaceDeviceCache
  internals at fixed offsets (`nvAccelSurfDirty`). Panics got more frequent with IOSurface copy traffic (~14k copies).
  A run without Metal for Photo Booth was too short to tell.
- **Black preview:** Core Image refused the 720x480 BGRA preview surface ("texture usage must include ShaderWrite"):
  pitch-linear BGRA is no storage image on Intel, so ShaderWrite was never reported. Branch `camera-wip` of the plugin
  reports it through the optimal-tiled storage twin; Core Image then renders at 30 fps but the preview stays black and
  some refusals remain. Camera frames are two-plane `420v`; VideoToolbox writes R32Uint views and Photo Booth reads R16
  views, synced through private copies (that part works). Without Metal, Photo Booth cannot draw at all.
- Camera apps work in Chromium-based browsers.

### Audio: none (speakers are SoundWire)
- Controller `8086:4D28`, PCI class `04:01` (DSP mode). macOS 26 ships no AppleHDA.
- The speaker/headphone codec is a **Realtek RT721 on SoundWire** (ACPI `A721`, `_ADR 0x000330025D072101`, link 3).
  Driving it needs Intel's SOF DSP firmware, the SoundWire bus and an RT721 driver: a large port.
- Tried NullMoth's NMXAudio (FreeBSD `snd_hda`) with Wildcat Lake support (patches 0110: IDs + PIO immediate commands as
  Linux uses for LNL+; 0111: 04:01 match and linker fixes). It attached but only the HD Audio link is reachable (Intel
  HDMI codec at best). Removed.
- **Pitfall found:** two kexts linking the same layer must not define the same IOKit class (`NMXIrq`,
  `IOAccelNMXDRMClient`). The second to load fails; when it was the GPU kext, boot looped.
- Workaround: USB or Bluetooth audio, or a virtual output (BlackHole). Any output device also fixes Safari's black
  YouTube video.

### Safari WebGL / YouTube
Safari's WebContent sandbox blocks the Metal driver bundle. NullMoth's NVWebKitFixup approach would work but weakens
Safari's sandbox; not done.

### Animation speed (Launchpad, Mission Control)
- **Cause found (1.0.13, Sequoia):** with the panel's copy path, WindowServer waited for the GPU after every Metal flush
  (`CompositorMetal::composite` → `commitAndWaitUntilSubmitted` → `waitUntilCompleted`, also for each blur pass and
  CoreDisplay's `AccessComplete`). CPU and GPU took turns, the GPU idled half the time, and its clock stayed at RPe
  (900 MHz of 2300). Launchpad: 25-30 fps, 35-68 ms frames. The vblank timer (±1.2 ms) and the copy (~1 ms) were not it.
- **Fix (patch 0063):** ordered frames on the panel. WindowServer no longer waits; a thread call copies each frame once
  its command buffers are published, then completes the transaction. 38 fps, long gaps 179 → 65 in 12 s.
  `debug.nmxfb_blob_ordered=0` switches back live.
- **Next:** the GPU clock under compositing (SLPC only ramps under near-constant load), and the CPU side of encoding
  (`MetalCompositeCoreAnimation`, about a third of WindowServer's frame time). Measure with `tools/tests/frame-gaps.m`.

### Others
- **Minecraft 1.12.2 on Zink:** ~30 fps, limited by presentation copies.
- **Panther Lake / FD81:** IDs are in the driver (0108/0109) but never run on hardware.
- **HDMI:** works when the monitor is connected at boot (tested by the user); the one scan-out image is mirrored to every
  output. Hot-plug after boot does not bring the monitor up (`bridge_hotplug` in `nmx_fb_bridge.c` re-commits outside the
  flip lock and limits modes to the panel size: the place to start). No HDMI audio: the Intel HDMI codec sits on the
  HD Audio link, and the NMXAudio attempt (0110/0111) was removed. USB-C / DisplayPort untested.
- **IOVersatile boot messages:** an Apple Silicon kext failing to load on x86; harmless, unrelated.

## Lessons
- Always diff `nm -u` of a new kext against the installed one before installing.
- kmutil only rebuilds the auxiliary collection when a version or binary changes: bump the version.
- Plug-ins nested in a third-party kext are not matched from the auxiliary collection: install them top-level.
- zsh has its own `log` builtin; use `/usr/bin/log show`.
- The Metal allow list stops at the first match: `-Name` exclusions must come before `*`.
