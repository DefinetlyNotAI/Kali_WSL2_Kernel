# Shahm's Kali WSL2 custom kernel kit

This folder restores the captured **x86-64 Kali under WSL2** setup:
`6.18.54.1-microsoft-standard-WSL2-CustomShahmKernal`.
It is not a native Kali/GRUB kernel installer or a complete Kali distribution backup.

## Future installation

1. Install WSL2 and Kali on the new Windows computer if necessary. In an administrator terminal:
   `wsl --install -d kali-linux`
   Finish any requested Windows restart, open Kali once, and create your Linux user.
2. Copy this **entire folder**, including `assets`, onto a local Windows drive.
3. Double-click **Install.cmd**. It installs Kali build/DKMS prerequisites, restores
   the captured sources, configuration, firmware and driver settings, installs the
   existing kernel/module image, and activates XTRX against that kernel.

For a differently named WSL distribution, run from this folder in PowerShell:

```powershell
.\Install.cmd -Distro YourKaliDistroName
```

The installer needs Internet access for Kali packages. It stops **all WSL
distributions**, including Docker, when activating the kernel. WSL's custom kernel
configuration is global, so other WSL2 distributions also use this kernel.
The installed Windows files live under `%USERPROFILE%\ShahmCustomKernel`;
the folder can be copied between different Windows usernames.
Unrelated `.wslconfig` options are retained. Its first pre-install copy is saved as
`%USERPROFILE%\.wslconfig.before-shahm-kit`, rather than making a backup every run.

## What is preserved

- Exact original kernel image and compressed module VHDX, including the configured
  in-kernel drivers and ISO9660 support.
- Exact `.config`, including `-CustomShahmKernal`, and kernel source at Microsoft
  commit `d504d40ab83839cb61942a812a99d183c42227b9`.
- Kernel build metadata and module symbol versions, needed for external drivers.
- XTRX source `0.0.1+git20190320.5ae3a3e`, plus its existing compiled module and
  DKMS binary archive. The normal installer imports that binary rather than rebuilding it.
- Realtek RTL8814AU source `5.8.5.1~git20250903.8d82854` and RTL88xxAU source
  `5.6.4.2~git20250330.c3fb89a`, registered with DKMS as on the original system.
- Existing `/usr/lib/firmware`, `/etc/modprobe.d`, `/etc/modules-load.d`,
  `/etc/modules`, `/etc/dkms`, and WSL's `systemd=true` boot setting.
- Recorded package versions, running kernel metadata, DKMS status and SHA-256 hashes.

The two old Realtek DKMS packages were **added but not installed** on the captured
6.18 kernel. Their source configuration explicitly restricts them to kernels below
6.15. This kit preserves that actual state and does not disable their compatibility
restriction. Enabled in-kernel Realtek drivers remain in the module image.
Windows USB passthrough/device attachment is separate from Linux driver installation;
this kit does not attach USB devices automatically or recreate hardware bindings.

The installer restores the captured driver settings, replacing matching files in
Kali. Keep it for a fresh install or a deliberate restoration of those settings.
It does not copy home-directory secrets, SSH keys, application data or entire WSL disks.

## Rebuild from the actual source

The normal install uses your existing binaries. To compile them yourself instead,
open Kali, change into this folder (its Windows path is under `/mnt/c/`), then run:

```bash
sudo bash rebuild.sh
```

This compiles the bundled kernel source with the captured configuration, builds
XTRX, installs the kernel modules into a staging directory, and creates a WSL
artifact VHDX using Microsoft's bundled script. It produces `rebuilt/kernel`,
`rebuilt/modules.vhdx.gz`, matching build metadata and checksums. From Windows,
activate those files with:

```powershell
.\Install.cmd -Rebuilt
```

Allow substantial disk space and compilation time. Set `JOBS` to limit compilation
parallelism. The build directory under `/var/tmp/shahm-kernel-build.*` is printed
and retained; remove that exact directory yourself when no longer needed.
The script refuses to overwrite an existing `rebuilt` directory.
Rebuilding preserves source, configuration and driver versions; a newer compiler
or different build timestamp can change binary bytes. Use the normal installer for
the captured original kernel binary.

## Roll back

If you had a previous `.wslconfig`, restore
`%USERPROFILE%\.wslconfig.before-shahm-kit` as `.wslconfig`, then run `wsl --shutdown`.
If there was no previous file, remove only the `kernel` and `kernelModules` lines
from its `[wsl2]` section, then run `wsl --shutdown` to use WSL's default kernel.

## Status

Captured on `2026-10-09`. The installer and rebuild script were **not run or tested**. Existing kernel files, source trees and system configuration were
not changed while preparing this kit.


Scripts, metadata and bundled assets are committed locally. Archives and the kernel
binary use Git LFS. Install Git LFS before cloning, then run `git lfs install`.


A normal `git clone` downloads the full kit, including the assets. If LFS downloads
were skipped, run `git lfs pull` inside the clone before using the installer.
The Git remote must also contain the LFS objects; this kit has not been pushed.
