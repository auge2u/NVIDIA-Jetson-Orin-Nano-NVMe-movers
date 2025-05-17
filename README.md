# 🚀 iliketomoveit.sh — Jetson NVMe Easy Migrator

**“I like to move it”** — A powerful and fun-to-use Jetson NVMe migration + onboarding tool  
Supports SD ➜ NVMe boot, container runtime setup (Docker or nerdctl), Wi-Fi config, host naming, and more.

     ╔════════════╗        ╔════════════════════╗        ╔════════════╗
     ║   JETSON   ║ ───▶   ║  CONTAINERS (🐳)    ║ ───▶   ║   NVMe     ║
     ╚════════════╝        ╚════════════════════╝        ╚════════════╝
        [SOC]                 [Image Layers]                [Storage]


🔗 Repo: [NVIDIA-Jetson-Orin-Nano-NVMe-movers](https://github.com/auge2u/NVIDIA-Jetson-Orin-Nano-NVMe-movers)

---

## ⚡ Quick Start

Run this on your Jetson Nano / Orin:

```bash
wget https://raw.githubusercontent.com/auge2u/NVIDIA-Jetson-Orin-Nano-NVMe-movers/main/iliketomoveit.sh
chmod +x iliketomoveit.sh
./iliketomoveit.sh --logo --help
```

Or launch with setup:

```bash
./iliketomoveit.sh --autoname jetson01 --wifi MySSID MyPass
```

---

## 🛠 Features

- 🔁 Clone system from SD card to NVMe
- ⚙️ Patch bootloader (extlinux.conf)
- 🐳 Choose Docker or nerdctl + containerd
- 📡 Auto-configure Wi-Fi
- 🧬 Set hostname on boot
- 💽 Multi-NVMe cloning support
- 🧪 Validate current boot and root state
- 🎨 ASCII-powered onboarding with credits

---

## 🔧 Requirements

- Jetson Nano Orin, NX, or Xavier board
- JetPack / L4T pre-installed
- External NVMe connected and detected
- Internet connection for `wget` and runtime setup
- Tools: `rsync`, `parted`, `gdisk`, `containerd` or `docker`

---

## 🙏 Credits

Thanks to [jetsonhacks](https://github.com/jetsonhacks) for the foundation scripts and hardware inspiration.

Created by [Agustin Musi](https://github.com/auge2u) — Zurich 🇨🇭  
Project: [NVIDIA-Jetson-Orin-Nano-NVMe-movers](https://github.com/auge2u/NVIDIA-Jetson-Orin-Nano-NVMe-movers)
