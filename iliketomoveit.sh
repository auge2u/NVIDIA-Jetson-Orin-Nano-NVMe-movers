#!/bin/bash
set -e

### iliketomoveit.sh — Jetson NVMe Easy Migrator & Container Setup Tool
# Repository: NVIDIA-Jetson-Orin-Nano-NVMe-movers — https://github.com/auge2u/NVIDIA-Jetson-Orin-Nano-NVMe-movers

show_logo() {
  echo -e "\033[1;34m
     ╔════════════╗        ╔════════════════════╗        ╔════════════╗
     ║   JETSON   ║ ───▶   ║  CONTAINERS (🐳)    ║ ───▶   ║   NVMe     ║
     ╚════════════╝        ╚════════════════════╝        ╚════════════╝
        [SOC]                 [Image Layers]                [Storage]
\033[0m"
  echo -e "\033[1;36m   🔁 Clone   ⚙️ Setup   🐳 Runtime   📦 Persist   📡 Wi-Fi Ready\033[0m"
  echo -e "\n\033[0;37mThis tool automates Jetson OS migration from SD to NVMe, patches the bootloader,
configures your container runtime (Docker or nerdctl), sets Wi-Fi, supports host renaming,
and can clone to multiple NVMe drives — all in one script.\033[0m"
  echo -e "\n\033[0;90mCreated for those who like the NVIDIA Jetson Orin Nano system platform but don't want to get super frustrated
by trying to figure out why they made it so amazing, but didn't get the onboarding quite right.\033[0m"
  echo -e "\033[0;90mThank you jetsonhacks — I found your GitHub far later than I should have. Now let's get this 'baby powerhouse'
ready to do some amazing things.\033[0m"
  echo -e "\033[0;90mAgustin Musi — Zurich, Switzerland\033[0m"
  echo
}

# Parse arguments
show_logo_flag=false
show_help_flag=false
validate_flag=false
autoname_value=""
wifi_ssid=""
wifi_pass=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) show_help_flag=true ;;
    --logo) show_logo_flag=true ;;
    --validate) validate_flag=true ;;
    --autoname) autoname_value="$2"; shift ;;
    --wifi) wifi_ssid="$2"; wifi_pass="$3"; shift 2 ;;
  esac
  shift
done

$show_logo_flag && show_logo
if $show_help_flag; then
  show_logo
  echo "\nUsage: ./iliketomoveit.sh [options]"
  echo "  --validate              Show boot/root status"
  echo "  --autoname <hostname>   Rename this Jetson device"
  echo "  --wifi <SSID> <PASS>    Preconfigure Wi-Fi network"
  echo "  --logo                  Display ASCII logo"
  echo "  --help                  Show this message"
  exit 0
fi

if $validate_flag; then
  show_logo
  echo "\n🔎 VALIDATION MODE: Checking current boot environment..."
  ROOT_SRC=$(findmnt -n -o SOURCE /)
  echo "📌 Current root device: $ROOT_SRC"
  echo "📄 Checking extlinux.conf (if present)..."
  [[ -f /boot/extlinux/extlinux.conf ]] && grep "APPEND" /boot/extlinux/extlinux.conf || echo "❌ extlinux.conf not found."
  echo "📄 Checking /etc/fstab (root entry)..."
  grep -E ' / ' /etc/fstab || echo "⚠️ No root entry in /etc/fstab. Might be using kernel cmdline."
  echo "🔁 Mounted devices:\n   Root: $ROOT_SRC\n   Boot: $(findmnt -n -o SOURCE /boot || echo 'not mounted')"
  exit 0
fi

[[ -n "$autoname_value" ]] && echo "🧬 Setting hostname to $autoname_value" && \
  echo "$autoname_value" | sudo tee /etc/hostname && \
  sudo hostnamectl set-hostname "$autoname_value" && \
  sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$autoname_value/" /etc/hosts

if [[ -n "$wifi_ssid" && -n "$wifi_pass" ]]; then
  echo "📶 Configuring Wi-Fi network: $wifi_ssid"
  sudo tee /etc/NetworkManager/system-connections/${wifi_ssid}.nmconnection > /dev/null <<EOF
[connection]
id=${wifi_ssid}
type=wifi
permissions=
[wifi]
mode=infrastructure
ssid=${wifi_ssid}
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${wifi_pass}
[ipv4]
method=auto
[ipv6]
method=auto
EOF
  sudo chmod 600 /etc/NetworkManager/system-connections/${wifi_ssid}.nmconnection
  sudo nmcli connection reload
fi

echo "\n🚀 Starting Jetson NVMe + Container Setup"
if ! grep -qi "tegra" /proc/device-tree/compatible && [ ! -f /etc/nv_tegra_release ]; then
    echo "❌ Not a Jetson device. Exiting."
    exit 1
fi

ROOT_SRC=$(findmnt -n -o SOURCE /)
BOOT_SRC=$(findmnt -n -o SOURCE /boot || echo "unknown")
echo "🔍 Root filesystem: $ROOT_SRC"
echo "🔍 Boot source: $BOOT_SRC"

if [[ "$ROOT_SRC" == *"nvme"* ]]; then
  echo "⚠️ Already booted from NVMe. No migration needed."
  exit 0
else
  echo "✅ Booted from SD card. Proceeding with migration."
fi

nvme_devices=($(lsblk -ndo NAME | grep -E '^nvme[0-9]+n[0-9]+$'))
[[ ${#nvme_devices[@]} -eq 0 ]] && echo "❌ No NVMe device found." && exit 1

if [[ ${#nvme_devices[@]} -gt 1 ]]; then
  echo "🪬 Multiple NVMe devices detected: ${nvme_devices[*]}"
  read -rp "Clone system to all NVMe devices? (y/N): " clone_all
fi

SCRIPT_DIR="$HOME/migrate-jetson-to-ssd"
cd ~ && [[ ! -d "$SCRIPT_DIR" ]] && git clone https://github.com/jetsonhacks/migrate-jetson-to-ssd.git "$SCRIPT_DIR"
cd "$SCRIPT_DIR" && chmod +x copy_partitions.sh

for dev in "${nvme_devices[@]}"; do
  if [[ "$clone_all" == "y" || "$clone_all" == "Y" || ${#nvme_devices[@]} -eq 1 ]]; then
    echo "🚚 Migrating to /dev/$dev..."
    sudo ./copy_partitions.sh "/dev/$dev"
    sudo partprobe "/dev/$dev"
    sleep 2
    uuid=$(blkid -s UUID -o value "/dev/${dev}p1")
    NVME_MOUNT="/mnt/${dev}"
    sudo mkdir -p "$NVME_MOUNT"
    sudo mount "/dev/${dev}p1" "$NVME_MOUNT"
    echo "📌 UUID of NVMe rootfs: $uuid"
  fi
done

if [[ -f /boot/extlinux/extlinux.conf ]]; then
  echo "🛠 Patching bootloader..."
  UUID=$(blkid -s UUID -o value /dev/${nvme_devices[0]}p1)
  sudo sed -i "s@APPEND .*@APPEND root=UUID=$UUID rw rootwait@" /boot/extlinux/extlinux.conf
  echo "✅ extlinux.conf updated."
fi

echo -e "\n🔧 Choose container runtime:"
echo "1) Docker (not NVIDIA recommended)"
echo "2) nerdctl + containerd (preferred)"
read -rp "Choose 1 or 2: " runtime_choice

if [[ "$runtime_choice" == "1" ]]; then
  sudo apt-get remove -y docker docker.io containerd runc containerd.io || true
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo mkdir -p "$NVME_MOUNT/docker"
  echo -e "{\"data-root\": \"$NVME_MOUNT/docker\"}" | sudo tee /etc/docker/daemon.json
  sudo systemctl enable docker
  sudo systemctl restart docker
  docker info | grep "Root Dir"
elif [[ "$runtime_choice" == "2" ]]; then
  sudo apt-get install -y containerd
  VERSION="1.7.5"
  curl -LO https://github.com/containerd/nerdctl/releases/download/v${VERSION}/nerdctl-${VERSION}-linux-arm64.tar.gz
  sudo tar -C /usr/local/bin -xzf nerdctl-${VERSION}-linux-arm64.tar.gz
  rm nerdctl-${VERSION}-linux-arm64.tar.gz
  sudo containerd config default | sudo tee /etc/containerd/config.toml
  sudo sed -i "s|^root = .*|root = \"$NVME_MOUNT/containerd\"|" /etc/containerd/config.toml
  sudo sed -i "s|^state = .*|state = \"$NVME_MOUNT/containerd-state\"|" /etc/containerd/config.toml
  sudo mkdir -p "$NVME_MOUNT/containerd" "$NVME_MOUNT/containerd-state"
  sudo systemctl restart containerd
  sudo nerdctl --address /run/containerd/containerd.sock info | grep Root || echo "⚠️ nerdctl info failed"
else
  echo "❌ Invalid option."
  exit 1
fi

echo -e "\n🎉 Setup complete. Reboot to test NVMe boot. Use --validate to verify."
