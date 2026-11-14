# AROS for Windows x64

## Start and update

- **AROS-starten.cmd** boots the locally cached AROS ABIv11 ISO in QEMU. A fresh setup discovers and downloads the latest matching boot ISO from AxRuntime. QEMU is installed via WinGet when needed.
- **AROS-aktualisieren.cmd** checks AxRuntime for a newer x86-64 ABIv11 boot ISO and downloads it without starting the VM. The previous ISO stays in AROS-Daten. A failed download leaves the previous ISO available for the next normal start.
- Keep the launcher beside the original AROS-Daten folder to reuse an existing installation. Exit QEMU before updating. The updater checks boot images, not Windows launcher versions or in-guest packages.

## Windows file exchange

Start **AROS-Dateiaustausch.cmd** once to create the AROS-Austausch folder beside the launcher. Close QEMU, copy the files you want to share into that folder, then start the same launcher again. QEMU presents the folder to AROS as a virtual USB FAT disk labeled **WINDOWS**. In Wanderer, look for the WINDOWS volume. If it is missing, open Prefs/Trident and check whether the USB mass-storage device is detected.

The file exchange is read-only by default. For a writable folder, run:

    AROS-starten.cmd -ShareWindowsFiles -WritableShare

QEMU's writable virtual FAT support is experimental. Use copies of your files, use ASCII filenames, close QEMU before editing the folder in Windows, and use the folder only for files you want AROS to see. QEMU guest networking is disabled.

## Build the included EXE launcher source

From PowerShell in this directory, run:

    & "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /platform:x64 /out:AROS-Setup-x64.exe /resource:AROS.ps1,AROS.ps1 ArosSetup.cs

The resulting EXE accepts --update, --share, or --share-write. Double-click it for a normal boot.

The Windows launcher is MIT-licensed. AROS and QEMU retain their own licenses.
