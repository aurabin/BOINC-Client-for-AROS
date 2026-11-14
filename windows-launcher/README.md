# AROS Wizard powered by ChatGPT

Windows x64 launcher for AROS ABIv11 in QEMU.

## Start and update

### Native AROS update preference

Build `guest/SystemUpdates.c` with the ABIv11 SDK (`gcc -std=c99 -o SystemUpdates SystemUpdates.c`) and install the binary as `SYS:Prefs/SystemUpdates`. Run `SYS:Prefs/SystemUpdates --icon` once to create its Wanderer icon if none exists. Open **Prefs  SystemUpdates** to enable or disable prepared updates; the preference is stored in ENVARC.

Add `SYS:Prefs/SystemUpdates --apply` near the start of `S:Startup-Sequence`, before loading components the package replaces. Stage a trusted, version-matched file payload in `SYS:AROSWizard/Update/files`, preserving its directory layout. Write its relative file paths, one per line, to `SYS:AROSWizard/Update/ready.txt` after staging finishes. Destination directories must already exist. Use regular files and directories, without links. The updater skips `.info` entries and leaves existing icons and their metadata in place. It installs prepared files only; it does not download packages or execute vendor installer scripts. A multi-file update is not atomic.

On the first normal managed ISO boot, the Wizard asks whether automatic ISO updates are wanted. Yes and No are saved per Wizard installation. Cancel leaves the choice as it was. Run **AROS-Update-Einstellungen.cmd** to change the setting without booting.

- **AROS-starten.cmd** boots the locally cached AROS ABIv11 ISO in QEMU. A fresh setup discovers and downloads the latest matching boot ISO from AxRuntime. QEMU is installed via WinGet when needed.
- **AROS-aktualisieren.cmd** checks AxRuntime for a newer x86-64 ABIv11 boot ISO and downloads it without starting the VM. The previous ISO stays in AROS-Daten. A failed download leaves the previous ISO available for the next normal start.
- **AROS-AutoUpdate.cmd** or the EXE flag `--auto-update` checks the official release index before each ISO boot. It starts the previous cached ISO if the update fails. This updates the boot image cache only. Explicit local ISOs and installed DH0 systems use their selected boot media.
- Keep the launcher beside the original AROS-Daten folder to reuse an existing installation. Exit QEMU before updating. The updater checks boot images, not Windows launcher versions or in-guest packages.
- The Wizard removes its abandoned download staging files and session-port files older than 24 hours after acquiring the launcher lock. Use **AROS-Bereinigen.cmd** or `--cleanup` to run the cleanup without booting AROS. Cached boot ISOs, virtual disks, exchange files, and diagnostic logs are retained.

## Start from an offline ISO

Double-click **AROS-Offline-ISO.cmd** and select a local bootable AROS x86-64 ISO. Extract the ISO first if it came in a ZIP. The launcher checks the ISO-9660 header and boots the selected file directly. It skips downloads and leaves the installed AROS image cache untouched. QEMU must already be installed. Cancel closes the picker without starting anything.

To pass a path directly, run `AROS-starten.cmd -IsoPath "D:\Images\AROS.iso"`. To select an ISO and use Windows desktop mode in the same session, run `AROS-Offline-ISO.cmd -WindowsDesktop`.

## Virtual AROS drives

Open **AROS-Laufwerke.cmd** (or run the EXE with `--virtual-drives`) for the DH0 and DH1 image dialog. Use **Image waehlen** to select an existing QCOW2 image or enter the path for a new one. The Wizard remembers each path after a successful setup. Choose the capacity of each dynamically allocated image in MiB. Existing images can be grown. **DH1 deaktivieren** omits the second disk for that session and preserves its image.

For initial setup, boot the ISO and use AROS HDToolBox and Format to create and format partitions on the virtual IDE disks. The labels in the dialog identify disk slots. Name the corresponding AROS partitions DH0 and DH1 in AROS. Increasing the image size adds unallocated capacity, so existing partitions retain their size until you expand or recreate them in AROS. After installing AROS on the first disk, select **Von DH0 starten statt von der ISO** to boot that disk.

Use `AROS-Laufwerke.cmd -OfflineIso` to select a local boot ISO. With an existing bootable DH0 image, `AROS-Laufwerke.cmd` and the DH0 boot option start directly from disk without downloading or attaching an ISO.

## Experimental SMP guest

Open **AROS-SMP.cmd** or run the EXE with `--smp`. Choose a virtual CPU count from 1 to 255, then select an x86-64 PC SMP boot ISO from the AROS Development Team. The count defaults to the number of logical processors available to the Wizard.

- For a fixed number, run `AROS-SMP.cmd -SmpCpus 3 -IsoPath "D:\Images\AROS-SMP.iso"`.
- To model two sockets, three cores per socket and two threads per core, run `AROS-SMP.cmd -SmpSockets 2 -SmpCores 3 -SmpThreads 2`. The Wizard derives the 12 virtual CPUs.
- To test a different emulated x86 CPU, add `-SmpCpuModel` with a model from `qemu-system-x86_64.exe -cpu help`. Model availability depends on the installed QEMU build.

The guest kernel in the chosen ISO determines how many of the supplied CPUs it can bring online. The stable cached ABIv11 image is used by the normal one-CPU launch. Use separate images for experimental guest installs.

## Driver diagnostics

Run **AROS-Treiberdebug.cmd** or use `--driver-debug` with the EXE. Each run creates a directory under `AROS-Daten/Treiberlogs` with QEMU's guest-error log and the guest's serial output. To capture AROS kernel messages, add `debug=serial` to the AROS kernel line in the GRUB boot menu. A debug build of the affected driver may provide more detail.

The switch can be combined with `-OfflineIso`, `-VirtualDrives` for virtual IDE storage, `-ShareWindowsFiles` for USB mass storage, and the Wizard features that enable the RTL8139 virtual network adapter. Reproduce the issue with one device at a time to identify the failing path.

### PCI inventory and matching code in AROS

Build `guest/DriverScan.c` with the ABIv11 SDK and the PCI HIDD stubs, for example `gcc -O2 -o DriverScan DriverScan.c -lhiddstubs -loop` where those libraries are installed. Run `DriverScan >RAM:hardware.csv` in AROShell to enumerate PCI functions. The initial matching list identifies RTL8129 and RTL8138/8139 as candidates for the existing rtl8139.device. A candidate match alone does not show that the device is bound or functional.

Run `DriverScan >RAM:DriverMatches.c --autocode` for a C match table of unmapped functions. This is a starting point for a port and performs no register access. Native USB, ACPI, and device binding inventories require additional bus-specific support. No generated code is installed into the guest.

## Virtual Field Generator proposal

A native AROS editor, launched from Wanderer, would let you place images, text and animated objects on a canvas and preview the result from the same window. Start with a two-dimensional field that can recreate the Boing Ball demo.

- Use a Zune window for the object list, canvas and properties. Each object stores its position, size, layer and optional motion. The preview can be paused and restarted.
- Save the editable scene and its assets in a project drawer. Store asset paths relative to the drawer so it can move between DH0, DH1 and the Windows exchange folder.
- Save a portable HTML preview from the same scene data so a field can also be opened on Windows. Start with local images and text, then add sound and additional animation types after the save and reload workflow is stable.

The first acceptance test is to build a scene from two local assets, save it to DH0, reopen it in AROS, and compare the exported preview with the AROS preview. This is a proposed guest application.

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

## Fullscreen in the Windows edition of Wanderer

Apply `guest/wanderer-windows-fullscreen.patch` to the AROS ABIv11 2026.09 source tree before building the Windows Wizard guest. Enable the menu in this guest image's startup sequence with `SetEnv AROSWizardWindows 1` before Wanderer starts. The desktop's **Wanderer > Fullscreen** entry is hidden without that variable and is absent from stock AROS images.

Boot the resulting ISO with `AROS-Offline-ISO.cmd -WandererFullscreen`. Choose **Wanderer > Fullscreen** inside the guest to toggle the focused QEMU GTK window. The launcher uses COM1 for the local command channel. This mode uses the existing guest display resolution.

## ChatGPT for AROS

`guest/ChatGPT.c` is a native AROS x86-64 ABIv11 application. It opens its own AROS console window and retains the last four turns in Windows memory while the VM runs. It uses the OpenAI Responses API with separate API billing and does not sign in to a ChatGPT web account.

1. Build the guest program with the ABIv11 SDK from AROShell: `gcc -std=c99 -O2 -Wall -Wextra -o ChatGPT ChatGPT.c`. With an ABIv11 cross-toolchain, use its target GCC instead. Copy the executable to the AROS machine, for example via the exchange folder.
2. Set `OPENAI_API_KEY` in the Windows environment before launching. Optionally set `OPENAI_MODEL` to select another Responses API model. The default is `gpt-4.1-mini`.
3. Start `AROS-ChatGPT.cmd`. Add `-OfflineIso` to pick an existing ISO or `-ShareWindowsFiles` to attach the exchange folder. If using the EXE, pass `--chatgpt`.
4. In AROS, enable DHCP on the RTL8139 adapter and run `ChatGPT` from AROShell. Use `/reset` to clear the conversation and `/quit` to exit.

The API key stays in Windows. Any program inside this VM can contact the local chat bridge while chat mode is active, so use it with a guest image you trust. The QEMU link permits this specific service without enabling general guest internet access. The app supports Latin-1 text in the console. If the guest loses its connection, restart the VM.

## Build the included EXE launcher source

From PowerShell in this directory, run:

    & "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /platform:x64 /out:AROS-Setup-x64.exe /resource:AROS.ps1,AROS.ps1 ArosSetup.cs

The resulting EXE accepts --update, --offline-iso, --share, --share-write, --windows-desktop, --chatgpt, and --wanderer-fullscreen. Double-click it for a normal boot.

The Windows launcher is MIT-licensed. AROS and QEMU retain their own licenses.
