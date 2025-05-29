# eos2arch – Migrate an EndeavourOS installation to pure Arch Linux
(Bash script by Adam Wyatt – Ay1tsMe, 2025)

## What this script does
`eos2arch` converts an existing EndeavourOS installation into a stock Arch Linux system in place.

It removes all EndeavourOS-specific packages and branding, switches you to the official Arch repositories and keyrings, rebuilds the bootloader and initramfs, and finally renames the filesystem label so your machine now identifies as Arch Linux everywhere.

## Before you begin
- Back up absolutely EVERYTHING. The script asks twice-but you are responsible for your data.
- You must run it as root (`sudo ./eos2arch.sh`).
- The migration is one-way. Rolling back requires restoring from your backup.
- I recommend [Timeshift](https://github.com/linuxmint/timeshift) for your backups.
- Do a dry-run first before running the actual script.

## Prerequisites
- An internet connection.
- EFI system with GRUB bootloader.
- No custom kernals or multiple kernals. (I tried this with zen kernal and it broke `dracut`. Probably a workaround to this.)
- Script uses `dracut` instead of `mkinitcpio`. If you use `mkinitcpio`, do not run.

## Usage
```
# Make it executable
chmod +x eos2arch.sh

# Help command
./eos2arch.sh -h

# Do a dry-run first
sudo ./eos2arch.sh --dry-run

# Run as root
sudo ./eos2arch.sh
```

## Step-by-Step Procedure
1. Updates the system
2. Uninstalls all EndeavourOS packages
3. Removes EndeavourOS repo from `/etc/pacman.conf`
4. Rewrites pacmans mirrorlist with `reflector`
5. De-brands all system files and changes them to Arch. e.g. `/etc/os-release`, `/etc/issue`
6. Deletes old EndeavourOS boot entry and replaces it with Arch boot entry
7. Rebuild initramfs with `dracut`
8. Regenerate GRUB
9. Rename root filesystem label

## License
This project is licensed under the MIT License. See the LICENSE file for more information.

