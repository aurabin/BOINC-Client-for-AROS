# AROS Wizard powered by ChatGPT

Windows x64 launcher for AROS ABIv11 in QEMU.

## Start and update

- **AROS-starten.cmd** boots the locally cached AROS ABIv11 ISO in QEMU. A fresh setup discovers and downloads the latest matching boot ISO from AxRuntime. QEMU is installed via WinGet when needed.
- **AROS-aktualisieren.cmd** checks AxRuntime for a newer x86-64 ABIv11 boot ISO and downloads it without starting the VM. The previous ISO stays in AROS-Daten. A failed download leaves the previous ISO available for the next normal start.
- Keep the launcher beside the original AROS-Daten folder to reuse an existing installation. Exit QEMU before updating. The updater checks boot images, not Windows launcher versions or in-guest packages.

## Start from an offline ISO

Double-click **AROS-Offline-ISO.cmd** and select a local bootable AROS x86-64 ISO. Extract the ISO first if it came in a ZIP. The launcher checks the ISO-9660 header and boots the selected file directly. It skips downloads and leaves the installed AROS image cache untouched. QEMU must already be installed. Cancel closes the picker without starting anything.

To pass a path directly, run `AROS-starten.cmd -IsoPath "D:\Images\AROS.iso"`. To select an ISO and use Windows desktop mode in the same session, run `AROS-Offline-ISO.cmd -WindowsDesktop`.

## Windows file exchange

Start **AROS-Dateiaustausch.cmd** once to create the AROS-Austausch folder beside the launcher. Close QEMU, copy the files you want to share into that folder, then start the same launcher again. QEMU presents the folder to AROS as a virtual USB FAT disk labeled **WINDOWS**. In Wanderer, look for the WINDOWS volume. If it is missing, open Prefs/Trident and check whether the USB mass-storage device is detected.

The file exchange is read-only by default. For a writable folder, run:

    AROS-starten.cmd -ShareWindowsFiles -WritableShare

QEMU's writable virtual FAT support is experimental. Use copies of your files, use ASCII filenames, close QEMU before editing the folder in Windows, and use the folder only for files you want AROS to see.

## Control the Windows desktop from AROS

1. Start a Windows VNC server configured for interactive desktop control and password authentication. Bind it exclusively to IPv4 loopback, `127.0.0.1:5900`. Use a server that shares your current Windows desktop.
2. Double-click **AROS-Windows-Desktop.cmd**. For a different Windows server port, run `AROS-Windows-Desktop.cmd -DesktopPort 5901`. The guest endpoint stays the same.
3. In AROS, enable networking with DHCP on the virtual RTL8139 adapter. In a VNC viewer built for x86-64 ABIv11, connect to IP address `10.0.2.100` and TCP port `5900` and authenticate with the VNC server password.

The desktop gives you mouse and keyboard control. Open Explorer for files, launch apps from Start, and use PowerShell for commands under your Windows account. Windows applies its normal permissions. UAC secure-desktop support depends on the Windows VNC server.

This mode adds one QEMU guest-to-host forwarding rule. General network access stays disabled in this mode. Without the desktop option, QEMU has no network adapter. The launcher does not install a server or a viewer. Restart the VM if the VNC connection drops and the viewer cannot reconnect.

## Build the included EXE launcher source

From PowerShell in this directory, run:

    & "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /platform:x64 /out:AROS-Setup-x64.exe /resource:AROS.ps1,AROS.ps1 ArosSetup.cs

The resulting EXE accepts --update, --offline-iso, --share, --share-write, and --windows-desktop. Double-click it for a normal boot.

The Windows launcher is MIT-licensed. AROS and QEMU retain their own licenses.
