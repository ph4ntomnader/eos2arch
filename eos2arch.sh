#!/bin/bash
#
# Adam Wyatt (Ay1tsMe) - 2025
# eos2arch - migrate an installed EndeavourOS system to pure Arch Linux
#
# WARNING: Backup your system before running!!! Things could go wrong.

set -euo pipefail

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root (sudo)." >&2
  exit 1
fi

echo "Welcome to eos2arch! This script migrates an installed EndeavourOS system to pure Arch Linux"
echo

# Ask whether a backup exists
read -rp "Have you made a full backup of your system? [Y/n] " reply
case "${reply,,}" in          
  y|yes)  ;;
  *)      echo "Aborted. Please back up first."; exit 1;;
esac

read -rp "Are you sure you've made a backup? If something goes wrong, you will need a backup to restore your system back to normal. [Y/n] " reply
case "${reply,,}" in          
  y|yes)  ;;
  *)      echo "Aborted. Please back up first."; exit 1;;
esac

echo
echo "Running eos2arch"
sleep 1

# Update system
echo
echo "Updating system..."
pacman -Syu
sleep 1

echo
echo "Updating keyrings..."
pacman -S --needed endeavouros-keyring archlinux-keyring
echo "Successfully updated system."
sleep 1

echo
echo "Removing EndeavourOS packages..."
packages=(
  reflector-simple eos-log-tool
  endeavouros-branding endeavouros-keyring endeavouros-mirrorlist
  eos-apps-info eos-bash-shared eos-dracut eos-hooks eos-packagelist
  eos-rankmirrors eos-translations eos-update-notifier welcome
)

# Filter out packages that are not installed
installed_packages=()
for pkg in "${packages[@]}"; do
  pacman -Qi "$pkg" &>/dev/null && installed_packages+=("$pkg")
done

if [ ${#installed_packages[@]} -gt 0 ]; then
  pacman -R "${installed_packages[@]}"
else
  echo "No EndeavourOS packages found to remove."
fi
sleep 1

# Change pacman keyrings to Arch only
echo
echo "Editing pacman keyrings to Arch only..."
sed -i '/^\[endeavouros\]/{N;N;N;d}' /etc/pacman.conf
sleep 0.5

echo
echo "Downloading reflector..."
pacman -S reflector pacman-contrib
sleep 1

echo
echo "Running reflector..."
reflector --list-countries
read -rp "Type in your country code e.g. AU, DE, US " country_code
country_code=${country_code^^} # Uppercase
if reflector --list-countries | grep -wq "$country_code"; then
	echo "Country Code Valid. Proceeding..."
	reflector --country "$country_code" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
else
	echo "Aborted. Invalid Country Code."
	exit 1
fi
sleep 1


echo
echo "Syncing Arch Linux keyrings..."
pacman -Sy --needed archlinux-keyring
sleep 1

# Update os-release files
echo
echo "Updating os-release to Arch Linux..." 
echo
echo "Deleting old os-release files..."
rm /usr/lib/os-release
rm /etc/os-release
sleep 0.5

echo
echo "Reinstalling Arch os-release files..."
pacman -S --overwrite /usr/lib/os-release filesystem
sleep 1

# Update tty /etc/issue
echo
echo "Removing eos branding from tty..."
sed -i 's/EndeavourOS/Arch/g' /etc/issue
sleep 1

# Update grub
echo
echo "Removing eos branding from grub..."
rm /etc/lsb-release
sleep 0.5
pacman -S lsb-release

echo
echo "Editing GRUB_DISTRIBUTOR to Arch..."
sed -i 's/EndeavourOS/Arch/g' /etc/default/grub
sleep 0.5

echo
echo "Creating new grub entry"
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Arch Linux" --recheck
sleep 1

echo
echo "Removing old EndeavourOS grub entry and replacing with Arch Linux entry..."
eos_id=$(efibootmgr | awk '/endeavouros/{print substr($1,5,4)}' | head -1)
sudo efibootmgr -b $eos_id -B 
sleep 0.5

echo
echo "Removing EOS branding folder..."
rm -rf /boot/efi/EFI/ENDEAVOUROS
rm -rf /usr/share/endeavouros
sleep 1

# Rebuilding dracut
echo
echo "Rebuilding dracut..."
dracut --hostonly --no-hostonly-cmdline --add-confdir no-network /boot/initramfs-linux.img --force
sleep 1
dracut /boot/initramfs-linux-fallback.img --force

echo
echo "Initalise grub"
grub-mkconfig -o /boot/grub/grub.cfg
sleep 1

echo
echo "Renaming partition label..."
drive=$(lsblk -f | grep -w endeavouros | awk '{gsub(/[^a-zA-Z0-9]/,"",$1); print $1}')
e2label /dev/"$drive" "arch"
echo
echo "Renamed /dev/"$drive" to arch"

echo
echo "[SUCCESS] You can now reboot your system!"
sleep 2
