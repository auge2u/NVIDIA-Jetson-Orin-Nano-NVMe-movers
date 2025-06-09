#!/bin/bash
set -euo pipefail

### iliketomoveit.sh — Jetson NVMe Easy Migrator & Container Setup Tool
# Repository: NVIDIA-Jetson-Orin-Nano-NVMe-movers
# © Agustin Musi

show_logo() {
  echo -e "\033[1;34m
     ╔════════════╗        ╔════════════════════╗        ╔════════════╗
     ║   JETSON   ║ ───▶   ║  CONTAINERS (🐳)    ║ ───▶   ║   NVMe     ║
     ╚════════════╝        ╚════════════════════╝        ╚════════════╝
        [SOC]                 [Image Layers]                [Storage]
\033[0m"
  echo -e "\033[1;36m   🔁 Clone   ⚙️ Setup   🐳 Runtime   📦 Persist   📡 Wi-Fi Ready\033[0m"
  echo -e "\n\033[0;37mAutomates SD ➜ NVMe migration, dual-entry bootloader, container runtime setup, Wi-Fi/hostname, safe fallback.\033[0m"
  echo -e "\n\033[0;90mCreated for NVIDIA Jetson Orin Nano users — enjoy a baby powerhouse without the onboarding pain.\033[0m"
  echo -e "\033[0;90mAgustin Musi — Zurich, Switzerland\033[0m\n"
}

# --- Argument Parsing ---
show_logo_flag=false
show_help_flag=false
validate_flag=false
autoname_value=""
wifi_ssid=""
wifi_pass=""
rescue_flag=false

while (( $# )); do
  case "$1" in
    --help) show_help_flag=true ;; 
    --logo) show_logo_flag=true ;; 
    --validate) validate_flag=true ;; 
    --autoname) shift; autoname_value="$1" ;; 
    --wifi) shift; wifi_ssid="$1"; shift; wifi_pass="$1" ;; 
    --rescue) rescue_flag=true ;; 
    *) echo "Unknown option: $1" >&2; exit 1 ;; 
  esac
  shift
 done

# --- Ensure helper scripts present ---
SCRIPT_DIR="$HOME/migrate-jetson-to-ssd"
if [[ -d "$SCRIPT_DIR" ]]; then
  if [[ ! -f "$SCRIPT_DIR/copy_partitions.sh" || ! -f "$SCRIPT_DIR/make_partitions.sh" ]]; then
    echo "⚠️ Incomplete repo detected; recloning..."
    rm -rf "$SCRIPT_DIR"
  else
    echo "🔄 Updating migrate-jetson-to-ssd..."
    git -C "$SCRIPT_DIR" pull || {
      echo "⚠️ Pull failed; recloning..."
      rm -rf "$SCRIPT_DIR"
    }
  fi
fi
if [[ ! -d "$SCRIPT_DIR" ]]; then
  echo "📥 Cloning migrate-jetson-to-ssd helper repo..."
  git clone https://github.com/jetsonhacks/migrate-jetson-to-ssd.git "$SCRIPT_DIR"
fi
chmod +x "$SCRIPT_DIR"/{copy_partitions.sh,make_partitions.sh}

# --- Rescue Mode ---
if $rescue_flag; then
  echo "🔧 Rescue: Copy boot partition & rebuild bootloader"
  SD_ROOT="/dev/mmcblk0p1"
  NVME_BASE=$(lsblk -ndo NAME | grep -E '^nvme[0-9]+n[0-9]+$' | head -n1)
  NVME_ROOT="/dev/${NVME_BASE}p1"
  MNT_SD="/mnt/sdroot"; MNT_NV="/mnt/nvmeroot"
  sudo mkdir -p "$MNT_SD" "$MNT_NV"
  sudo umount "$MNT_SD" "$MNT_NV" 2>/dev/null || true
  sudo mount "$SD_ROOT" "$MNT_SD"
  sudo mount "$NVME_ROOT" "$MNT_NV"
  echo "📥 Syncing /boot to NVMe..."
  sudo rsync -aHAXx --delete "$MNT_SD/boot/" "$MNT_NV/boot/"
  echo "ℹ️ Installing syslinux/extlinux..."
  sudo apt-get update
  sudo apt-get install -y syslinux
  sudo extlinux --install "$MNT_NV/boot/extlinux"
  sudo dd if=/usr/lib/syslinux/extlinux.bin of="/dev/$NVME_BASE" bs=440 count=1 conv=notrunc
  sudo umount "$MNT_SD" "$MNT_NV"
  echo "🎉 Rescue complete: NVMe boot restored."
  exit 0
fi

# --- Help & Logo ---
$show_logo_flag && show_logo
if $show_help_flag; then
  show_logo
  cat <<EOF
Usage: ./iliketomoveit.sh [options]
  --validate          Check boot & root
  --autoname <host>   Set hostname
  --wifi <SSID> <PW>  Configure Wi-Fi
  --rescue            Rescue NVMe boot partition
  --logo              Show logo/info
  --help              This help
EOF
  exit 0
fi

# --- Validation Mode ---
if $validate_flag; then
  show_logo
  echo -e "\n🔎 VALIDATION:"
  printf "Root: %s\n" "$(findmnt -n -o SOURCE /)"
  printf "Boot: %s\n" "$(findmnt -n -o SOURCE /boot 2>/dev/null || echo 'none')"
  [[ -f /boot/extlinux/extlinux.conf ]] && echo "extlinux.conf:" && grep -E 'LABEL|APPEND' /boot/extlinux/extlinux.conf
  exit 0
fi

# --- Hostname & Wi-Fi Setup ---
if [[ -n "$autoname_value" ]]; then
  echo "🧬 Hostname: $autoname_value"
  echo "$autoname_value" | sudo tee /etc/hostname
  sudo hostnamectl set-hostname "$autoname_value"
  sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$autoname_value/" /etc/hosts || true
fi
if [[ -n "$wifi_ssid" && -n "$wifi_pass" ]]; then
  echo "📶 Wi-Fi: $wifi_ssid"
  sudo tee /etc/NetworkManager/system-connections/${wifi_ssid}.nmconnection > /dev/null <<WIFI
[connection]
id=${wifi_ssid}
type=wifi
[wifi]
ssid=${wifi_ssid}
[wifi-security]
key-mgmt=wpa-psk
psk=${wifi_pass}
WIFI
  sudo chmod 600 /etc/NetworkManager/system-connections/${wifi_ssid}.nmconnection
  sudo nmcli connection reload
fi

# --- Preconditions: SD boot check ---
current_root=$(findmnt -n -o SOURCE /)
if [[ "$current_root" != *mmcblk* ]]; then
  echo "⚠️ Run from SD card. Aborting." >&2
  exit 1
fi

# --- Start Migration ---
echo -e "\n🚀 Starting Jetson NVMe migration"
if ! grep -qi "tegra" /proc/device-tree/compatible && [ ! -f /etc/nv_tegra_release ]; then
  echo "❌ Not a Jetson device."; exit 1
fi

ROOT_SRC="$current_root"
BOOT_SRC=$(findmnt -n -o SOURCE /boot 2>/dev/null || echo none)
echo "🔍 Root: $ROOT_SRC | Boot: $BOOT_SRC"

nvmes=($(lsblk -ndo NAME | grep -E '^nvme[0-9]+n[0-9]+$'))
(( ${#nvmes[@]} )) || { echo "❌ No NVMe"; exit 1; }
if (( ${#nvmes[@]} > 1 )); then
  echo "🪬 NVMe found: ${nvmes[*]}";
  read -rp "Clone to all? (y/N): " clone_all;
fi

# --- Backup bootloader config ---
if [[ -f /boot/extlinux/extlinux.conf ]]; then
  sudo cp /boot/extlinux/extlinux.conf{,.bak}
  echo "📦 extlinux.conf backed up"
fi

# --- Partition & Clone ---
for dev in "${nvmes[@]}"; do
  echo -e "\n🚚 Migrating to /dev/$dev"
  # partition if needed
  if [[ ! -b "/dev/${dev}p1" ]]; then
    echo "🧩 Partitioning NVMe: /dev/$dev"
    sudo "$SCRIPT_DIR/make_partitions.sh" -d "/dev/$dev"
    sudo partprobe /dev/$dev; sleep 2
  fi
  # clone partitions
  SRC_DISK=$(lsblk -ndo PKNAME "$ROOT_SRC")
  SRC_DEV="/dev/$SRC_DISK"
  echo "   Source: $SRC_DEV | Dest: /dev/$dev"
  sudo "$SCRIPT_DIR/copy_partitions.sh" -s "$SRC_DEV" -d "/dev/$dev"
  sudo partprobe /dev/$dev; sleep 2
  # validate
  MNT="/mnt/$dev"; sudo mkdir -p "$MNT"
  sudo mount "/dev/${dev}p1" "$MNT"
  UUID=$(blkid -s UUID -o value "/dev/${dev}p1")
  echo "🔍 Validating rootfs (UUID=$UUID)"
  for d in etc usr var; do
    [[ -d "$MNT/$d" ]] && echo "  ✔ $d" || echo "  ✖ $d missing"
  done
  sudo umount "$MNT"
done

# --- Sync Boot Partition ---
echo "\n🔧 Syncing /boot"
sudo mkdir -p /mnt/sd /mnt/nv
sudo mount /dev/mmcblk0p1 /mnt/sd
sudo mount /dev/${nvmes[0]}p1 /mnt/nv
sudo rsync -aHAXx --delete /mnt/sd/boot/ /mnt/nv/boot/
sudo umount /mnt/sd /mnt/nv
echo "✅ Boot synced"

# --- Patch bootloader ---
echo "🛠 Patching extlinux.conf"
sudo tee -a /boot/extlinux/extlinux.conf > /dev/null <<EOF
LABEL nvme_root
  MENU LABEL Boot from NVMe (UUID=$UUID)
  LINUX /boot/Image
  APPEND root=UUID=$UUID rw rootwait
EOF

echo "✅ extlinux.conf updated"

# --- Container Runtime ---
echo -e "\n🔧 Container runtime"
echo "1) Docker  2) nerdctl"
read -rp "Select (1/2): " choice
case "$choice" in
  1) echo "🐳 Docker placeholder";;
  2) echo "🐧 nerdctl placeholder";;
  *) echo "❌ Invalid"; exit 1;;
esac

# --- Preserve Script ---
echo "\n📋 Preserving script"
sudo cp "$0" /usr/local/bin/iliketomoveit.sh && sudo chmod +x /usr/local/bin/iliketomoveit.sh
sudo mount /dev/${nvmes[0]}p1 /mnt/nv
sudo cp "$0" /mnt/nv/iliketomoveit.sh
sudo umount /mnt/nv

echo -e "\n🎉 iliketomoveit.sh complete!"
echo "Reboot to test NVMe boot or run --validate."
