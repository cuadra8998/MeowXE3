# Brightness keys on the ASUS Vivobook X1504MA (optional)

MeowXE3 drives the panel backlight, so the **brightness slider** in Control Center and System Settings works on its own.
The **F-key brightness keys** need two small edits to the laptop's DSDT plus `BrightnessKeys.kext`. These edits are
specific to the X1504MA's ASUS firmware: other laptops have different ACPI code, so **do not copy them blindly**.

The MeowXE3 installer does not do any of this. It's a manual, at-your-own-risk change to your OpenCore setup.

## Why the keys do nothing

On this firmware, the Fn brightness keys run ACPI method `BRTN`, which should send a notify to the panel device
`\_SB.PC00.GFX0.DD1F`. Two things stop it on macOS:

1. **OSYS.** `\_SB.PC00._INI` sets the OS version (`OSYS`) only for Windows `_OSI` strings. macOS answers only to
   `"Darwin"`, so `OSYS` stays at its old default, and the key path is only taken from Windows 8 on.
2. **BRTN.** `BRTN` picks the panel by `DIDX`/`DIDY`, values that only Intel's Windows graphics driver fills in. On
   macOS they stay empty, so `BRTN` notifies nobody.

## The two edits

You'll need your own DSDT, already disassembled (see the steps below). Make both edits in that file.

### 1. Treat macOS like Windows 10 in `\_SB.PC00._INI`

Find the `If (_OSI ("Windows 20xx"))` blocks that set `OSYS`. After the last one (the one setting `OSYS = 0x07DF`), add:

```asl
                If (_OSI ("Darwin"))
                {
                    OSYS = 0x07DF /* MeowXE3: macOS as Windows 10 - the brightness keys notify GFX0.DD1F only from Windows 8 on */
                }
```

### 2. Make `BRTN` notify the panel directly on macOS

Replace the body of `Method (BRTN, 1, Serialized)`:

```asl
    Method (BRTN, 1, Serialized)
    {
        /* MeowXE3: on macOS no Intel graphics driver fills in DIDX/EDPV, so the checks below never matched;
         * the panel is DD1F, notify it directly */
        If (_OSI ("Darwin"))
        {
            Notify (\_SB.PC00.GFX0.DD1F, Arg0)
        }
        Else
        {
            If (((DIDX & 0x0F0F) == 0x0400))
            {
                Notify (\_SB.PC00.GFX0.DD1F, Arg0)
            }

            If (((DIDY & 0x0F0F) == 0x0401))
            {
                Notify (\_SB.PC00.GFX0.DD2F, Arg0)
            }
        }
    }
```

Everything inside `Else` is the original code, so Windows and Linux behave exactly as before.

## Steps

1. **Dump your own DSDT.** Firmware versions differ, so never use someone else's. Two ways:
   - OpenCore: set `Misc > Debug > SysReport` to `true` in a DEBUG build. The tables end up in `EFI/SysReport/ACPI`.
   - Linux live USB: `sudo cat /sys/firmware/acpi/tables/DSDT > DSDT.aml`
2. **Disassemble it** with a current ACPICA `iasl` (MeowXE3 used version 20260930): `iasl -d DSDT.aml`. This gives
   you `DSDT.dsl`.
3. **Make the two edits** above in `DSDT.dsl`.
4. **Compile:** `iasl DSDT.dsl`. It must report **0 errors**; warnings and remarks are normal for ASUS tables.
5. **Back up your EFI folder.** Then copy `DSDT.aml` to `EFI/OC/ACPI/` and add an `ACPI > Add` entry for it
   (`Path` = `DSDT.aml`, `Enabled` = `true`). This replaces the whole DSDT, so keep the backup.
6. **Add `BrightnessKeys.kext`** ([acidanthera/BrightnessKeys](https://github.com/acidanthera/BrightnessKeys)) to
   `EFI/OC/Kexts`, with a `Kernel > Add` entry placed after `Lilu.kext`.
7. Restart and press the brightness keys. Brightness should step up and down, and macOS should show its on-screen
   brightness indicator.

## If it goes wrong

- **Boot hangs or ACPI errors:** in the EFI backup's config, set the `ACPI > Add` entry for `DSDT.aml` to
  `Enabled = false`, or restore the backup. The firmware's own DSDT is then used again.
- **Keys still do nothing:** check that `BrightnessKeys.kext` loaded (`kextstat | grep -i brightness`), and that your
  DSDT really has `\_SB.PC00.GFX0.DD1F`. If your BIOS names the panel device differently, use that name in edit 2.
