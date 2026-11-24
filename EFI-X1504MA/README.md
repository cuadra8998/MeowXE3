# OpenCore EFI: ASUS Vivobook X1504MA (Intel Wildcat Lake)

The OpenCore EFI this MeowXE3 work was done on, uploaded as a reference. It boots macOS Tahoe 26.7 with MeowXE3 on.

> [!WARNING]
> **This is one machine's EFI.** The DSDT and the USB, ACPI and kext setup are made for this exact laptop and BIOS.
> Use it as a reference, not a drop-in. Back up your own EFI before trying anything from it.

## Before it can boot anything

The serial number, board serial (MLB), system UUID and ROM have been **removed** (`PlatformInfo > Generic`). Generate
your own with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) for `MacBookPro16,2` and fill them in. `ROM` is six
zero bytes now: put your network card's MAC address there.

## What's in it

- **OpenCore** with `SecureBootModel` set to `Disabled`, and the escape tool `Tools/NullMothSafe.efi`. The tool shows in
  the boot picker as "NMXGPU: start once without driver" and boots once without MeowXE3.
- **ACPI:** a patched `DSDT.aml` and two SSDTs (EC/USBX, PLUG). The DSDT is the laptop's own with the brightness-key edits
  from [docs/X1504MA-brightness-keys.md](../docs/X1504MA-brightness-keys.md). It only fits this model and BIOS.
- **Kexts:** Lilu, VirtualSMC (+ SMCProcessor, SMCBatteryManager), ECEnabler, VoodooPS2, VoodooI2C/HID, AirportItlwm,
  IntelBluetoothFirmware, BlueToolFixup, USBToolBox, NVMeFix, RestrictEvents, AMFIPass, BrightnessKeys, and
  **MeowXE3Boot** (from this repo).
- **boot-args:** `nmxintel=1` turns MeowXE3 on.
  - `amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0` lets apps load the Metal driver. This lowers macOS
    security.
  - `-v keepsyms=1 debug=0x100` are for debugging.
  - `revcpu=1` (RestrictEvents) makes About This Mac show the real CPU ("Intel(R) Core(TM) 5 315") instead of the
    MacBookPro16,2 model's "6-Core Intel Core i5".
- **NVRAM:** `nullmoth-fbflags` = `1833`, written every boot. `csr-active-config` = `430A0000`, which loosens SIP so
  unsigned kexts load.

The MeowXE3 kexts themselves are not in the EFI: they install into `/Library/Extensions` with the
[release](../../../releases) installer.

## Credits

The kexts and OpenCore belong to their authors (acidanthera, OpenIntelWireless, VoodooI2C, USBToolBox and others) under
their own licenses. They are included unchanged, as distributed.
