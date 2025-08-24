#!/bin/bash
#
# Adam Wyatt (Ay1tsMe) - 2025
# PhantomNader (ph4ntomnader) - 2025
# eos2arch - migrate an installed EndeavourOS system to pure Arch Linux
#
# WARNING: Backup your system before running!!! Things could go wrong.
#
# Run with the --dry-run flag before proceeding.
# This script is for the SYSTEMD-BOOT bootloader. For the GRUB variant, see eos2arch.sh.

set -euo pipefail

# cli options
DRYRUN=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRYRUN=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run|-n]"
      exit 0 ;;
    *) echo "[ERROR] Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# --dry-run helper
run() {
  printf '[command] %s\n' "$(printf '%q ' "$@")"
  if [[ $DRYRUN -eq 0 ]]; then
    "$@"
  fi
}

# Always-execute helper for harmless queries (e.g. reflector --list-countries)
run_safe() {
  printf '[command] %s\n' "$(printf '%q ' "$@")"
  "$@"
}

# Convenience “maybe-prompt” wrapper
prompt() {
  local __q="$1" __var="$2"
  if [[ $DRYRUN -eq 1 ]]; then
    printf '[dry-run] %s (auto-answering Yes)\n' "$__q"
    printf -v "$__var" "y"
  else
    read -rp "$__q" "$__var"
  fi
}

# pre-flight sanity helpers
require_cmd()  { command -v "$1" &>/dev/null || { echo "[ERROR] command '$1' missing"; exit 1; }; }
require_file() { [[ -e "$1" ]]   || { echo "[ERROR] required file '$1' missing";  exit 1; }; }

# copy dracut helper scripts + hooks if they are absent
dracut_autosetup() {
  local REPO_DIR SCRIPT_DIR
  REPO_DIR=$(dirname "$(realpath "$0")")
  DRACUT_DIR="$REPO_DIR/dracut"

  # helper scripts → /usr/local/bin
  for f in dracut-install.sh dracut-remove.sh; do
    if [[ ! -e /usr/local/bin/$f ]]; then
      run install -Dm755 "$DRACUT_DIR/$f" "/usr/local/bin/$f"
    else
      echo "[skip] /usr/local/bin/$f already exists"
    fi
  done

  # pacman hooks → /etc/pacman.d/hooks
  for h in 60-dracut-remove.hook 90-dracut-install.hook; do
    if [[ ! -e /etc/pacman.d/hooks/$h ]]; then
      run install -Dm644 "$DRACUT_DIR/$h" "/etc/pacman.d/hooks/$h"
    else
      echo "[skip] /etc/pacman.d/hooks/$h already exists"
    fi
  done

  # delete mkinitcpio hooks if they exist
  run ln -sf /dev/null /etc/pacman.d/hooks/90-mkinitcpio-install.hook
  run ln -sf /dev/null /etc/pacman.d/hooks/60-mkinitcpio-remove.hook

  # remove mkinitcpio packages once dracut images exist
  if mkinitcpio -V &>/dev/null; then
    echo "[info] Removing mkinitcpio and its helpers..."
    run pacman -R mkinitcpio || true
  fi

  echo "[OK] dracut automatic regeneration is installed"
}

# Check that the *tools* we intend to call actually exist
for c in pacman reflector dracut grub-install efibootmgr sed awk lsblk e2label; do
  require_cmd "$c"
done
# Check that key files we will touch are present
for f in /etc/pacman.conf /etc/issue /etc/default/grub; do
  require_file "$f"
done

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root (sudo)." >&2
  exit 1
fi

echo "Welcome to eos2arch! This script migrates an installed EndeavourOS system to pure Arch Linux"
echo

# Ask whether a backup exists
if [[ $DRYRUN -eq 0 ]]; then
  prompt "It is recommended you run this with --dry-run to see if the script will work for you. Have you done this? [Y/n] " reply
  case "${reply,,}" in
    y|yes|'')  ;;
    *)         echo "Aborted. Please run with ./eos2arch.sh --dry-run first."; exit 1;;
  esac
fi

prompt "Have you made a full backup of your system? [Y/n] " reply
case "${reply,,}" in
  y|yes|'')  ;;
  *)         echo "Aborted. Please back up first."; exit 1;;
esac

prompt "Are you sure you've made a backup? If something goes wrong, you will need a backup to restore your system back to normal. [Y/n] " reply
case "${reply,,}" in
  y|yes|'')  ;;
  *)         echo "Aborted. Please back up first."; exit 1;;
esac

# Dry-run notice block
if [[ $DRYRUN -eq 1 ]]; then
  echo
  echo "Running with --dry-run; if you see any output with [skip] then the script will probably not work."
  sleep 5
fi

echo
echo "Running eos2arch"
sleep 1

# Update system
echo
echo "Updating system..."
run pacman -Syu
sleep 1

echo
echo "Updating keyrings..."
run pacman -S --needed endeavouros-keyring archlinux-keyring
echo "Successfully updated system."
sleep 1

echo
echo "Removing EndeavourOS packages..."
packages=(
  reflector-simple eos-log-tool
  endeavouros-branding endeavouros-keyring endeavouros-mirrorlist
  eos-apps-info eos-bash-shared eos-dracut eos-hooks eos-packagelist
  eos-rankmirrors eos-translations eos-update-notifier welcome eos-settings-gnome
)

# Filter out packages that are not installed
installed_packages=()
for pkg in "${packages[@]}"; do
  pacman -Qi "$pkg" &>/dev/null && installed_packages+=("$pkg")
done

if [ ${#installed_packages[@]} -gt 0 ]; then
  run pacman -R "${installed_packages[@]}"
else
  echo "No EndeavourOS packages found to remove."
fi
sleep 1

# Change pacman keyrings to Arch only
echo
echo "Editing pacman keyrings to Arch only..."
if [[ -e /etc/pacman.conf ]]; then
  if grep -q '^\[endeavouros\]' /etc/pacman.conf; then
    run sed -i '/^\[endeavouros\]/{N;N;N;d}' /etc/pacman.conf
  else
    echo "[skip] No EndeavourOS repo block in /etc/pacman.conf"
  fi
else
  echo "[skip] /etc/pacman.conf not found"
fi
sleep 0.5

echo
echo "Downloading reflector..."
run pacman -S reflector pacman-contrib
sleep 1

echo
echo "Running reflector..."
run_safe reflector --list-countries
read -rp "Type in your country code e.g. AU, DE, US " country_code
country_code=${country_code^^} # Uppercase
if reflector --list-countries | grep -wq "$country_code"; then
	echo "Country Code Valid. Proceeding..."
	run reflector --country "$country_code" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
else
	echo "Aborted. Invalid Country Code."
	exit 1
fi
sleep 1

echo
echo "Syncing Arch Linux keyrings..."
run pacman -Sy --needed archlinux-keyring
sleep 1

# Update os-release files
echo
echo "Updating os-release to Arch Linux..."
echo
echo "Deleting old os-release files..."
[[ -e /usr/lib/os-release ]] && run rm /usr/lib/os-release || echo "[skip] /usr/lib/os-release not found"
[[ -e /etc/os-release ]] && run rm /etc/os-release || echo "[skip] /etc/os-release not found"
sleep 0.5

echo
echo "Reinstalling Arch os-release files..."
run pacman -S --overwrite /usr/lib/os-release filesystem
sleep 1

# Update tty /etc/issue
echo
echo "Removing eos branding from tty..."
if [[ -e /etc/issue ]]; then
  if grep -qi 'EndeavourOS' /etc/issue; then
    run sed -i 's/EndeavourOS/Arch/g' /etc/issue
  else
    echo "[skip] /etc/issue already shows Arch"
  fi
else
  echo "[skip] /etc/issue not found"
fi
sleep 1

# Update grub
# Update systemd-boot
echo "Removing eos branding from boot entries..."
[[ -e /boot/loader/entries/endeavouros.conf ]] && rm /boot/loader/entries/endeavouros.conf || echo "[skip] EndeavourOS entry not found"
sleep 0.5

echo "Creating new systemd-boot entry for Arch..."
cat <<EOF > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$(blkid -s UUID -o value /dev/sda1) rw
EOF

echo "Updating systemd-boot configuration..."
bootctl update
sleep 1

echo "Removing old EOS boot entry..."
eos_id=$(bootctl list | awk '/EndeavourOS/{print $1}' | head -1)
if [[ -n "$eos_id" ]]; then
  bootctl remove "$eos_id"
else
  echo "[skip] No EndeavourOS boot entry found"
fi
sleep 0.5

echo
echo "Removing EOS branding folder..."
[[ -d /boot/efi/EFI/ENDEAVOUROS ]] && run rm -rf /boot/efi/EFI/ENDEAVOUROS || echo "[skip] /boot/efi/EFI/ENDEAVOUROS not found"
[[ -d /usr/share/endeavouros ]] && run rm -rf /usr/share/endeavouros || echo "[skip] /usr/share/endeavouros not found"
sleep 1

# Rebuilding dracut
echo
echo "Rebuilding dracut..."
run dracut --hostonly --no-hostonly-cmdline --add-confdir no-network /boot/initramfs-linux.img --force
sleep 1
run dracut /boot/initramfs-linux-fallback.img --force

# Copying dracut scripts + hooks
echo
echo "Setting up dracut automatic kernal hooks..."
dracut_autosetup
sleep 1

echo
echo "Initializing systemd-boot"
bootctl update
sleep 1

echo
echo "Renaming partition label..."
drive=$(lsblk -f | grep -w endeavouros | awk '{gsub(/[^a-zA-Z0-9]/,"",$1); print $1}') || true
if [[ -n "$drive" ]]; then
  run e2label /dev/"$drive" "arch"
  echo
  echo "Renamed /dev/$drive to arch"
else
  echo "[skip] Could not find partition with label endeavouros"
fi

echo
echo "[SUCCESS] You can now reboot your system!"
sleep 2
