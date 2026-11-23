# MeowXE3 on macOS Sequoia

Status: **built from the same tree as Tahoe, not yet run on real hardware.** Needs Sequoia **15.5 or newer**.

## What differs from the Tahoe build

Only the accelerator kext (`MeowXE3Accel`, NullMoth's NMXAccel). Tahoe changed the layout of Apple's IOAccelerator
classes, so NullMoth builds the accelerator twice from one source: with `NM_TAHOE` for macOS 26 and without it for
macOS 15 (`build/accel_build_all.sh` upstream). NullMoth itself started out as a Sequoia driver, so the macOS 15 path
is its original one.

Everything else is already built to load on Sequoia:

| Part | Minimum macOS | Why it's fine |
|---|---|---|
| MeowXE3.kext (NMXGPU: xe + display on LinuxKPI) | 15.0 | NullMoth's `cc*.sh` set it; upstream link-checked against 15.8.1's kernel collections |
| MeowXE3Accel | 15.0 | this branch: `MEOWXE3_TARGET=15` drops `NM_TAHOE` |
| MeowXE3AGDC, Metal plugin, translator | must be 15.0 | `build-sequoia.sh` checks and stops if any is newer |
| Mesa ANV, libdrm | 15.0 | `build-mesa.sh` |
| Zink + CGL bridge | 15.5 | `build-zink.sh`: the reason for the 15.5 floor |
| MeowXE3Boot | 15.0 | this branch |

The firmware, OpenCore changes (`nmxintel=1`, `nullmoth-fbflags=1833`, MeowXE3Boot, NullMothSafe.efi), SIP and AMFI
requirements are the same as on Tahoe.

## Building (on the Tahoe dev machine)

```sh
# 1. the normal Tahoe package first (as in CONTINUING.md), so ~/nmx/MeowXE3 is current
# 2. then:
bash tools/build/build-sequoia.sh 1.0.13 /path/to/NullMothSafe.efi
```

The script:
1. builds the macOS 15 accelerator into `~/nmx/src/nmxaccel-nmxgpu-15` (stops if it comes out identical to the Tahoe one),
2. copies the Tahoe package to `~/nmx/MeowXE3-sequoia` and repacks it with that accelerator,
3. checks every Mach-O in the kexts and GPUBundles: anything with a minimum macOS newer than 15.5 stops the build
   (rebuild that piece with `-mmacosx-version-min=15.0`; the plugin command in CONTINUING.md now has it),
4. writes `dist/MeowXE3-<version>-sequoia.zip`. Its `payload/TARGET` file says `15`.

Nothing is installed on the build machine.

If the Metal plugin or translator trips step 3, rebuild them with `-mmacosx-version-min=15.0` and run
`tools/dev/repack.sh` again before rerunning this script. Rebuild both accelerators whenever NullMoth's VRAM/flip ABI
headers change, or the desktop stays black.

## Installing on Sequoia

Same installer. It reads `payload/TARGET` and:
- accepts Sequoia 15.5+ with the `-sequoia` zip, and warns that the build is untested,
- refuses Tahoe with the `-sequoia` zip and Sequoia with the Tahoe zip (the wrong accelerator gives a black or frozen
  desktop),
- refuses Sequoia older than 15.5.

The driver installer stops before you restart if the auxiliary kernel collection does not take the kexts. That is
where a missing kernel symbol on Sequoia would show up.

## First test on a spare Sequoia volume

1. Boot Sequoia with your current EFI, and confirm the Mac already boots and the touchpad works without MeowXE3.
2. Run the installer with `--dry-run` first, then **[1] install everything**.
3. Keep **"MeowXE3: start once without driver"** in the OpenCore picker as the way back.
4. After a restart, collect:
   ```sh
   kmutil showloaded | grep -i meow
   /usr/bin/log show --last boot --predicate 'sender CONTAINS "kernelmanagerd" OR sender CONTAINS "MeowXE3"' | tail -200
   system_profiler SPDisplaysDataType
   ```
5. Run the Metal tests in `tools/tests` (`nmx-metal-test`, `nmx-metal-render`, `buftex-mip`).

Things most likely to differ from Tahoe: WindowServer's compositing path (fbflags `1833`), retiring the boot
framebuffer (Sequoia's IONDRVFramebuffer), and the IOSurface cache offsets the accelerator writes.
