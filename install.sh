#!/usr/bin/env bash
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔══════════════════════════════════════════╗${NC}"
echo -e "${C}║   ${B}Ubuntu 24 Terminal Setup${C}               ║${NC}"
echo -e "${C}╚══════════════════════════════════════════╝${NC}"

# ── Detect AVAILABLE resources ──
AVAIL_RAM_MB=$(free -m | awk '/Mem:/{print $7}')
CPU_CORES=$(nproc)
AVAIL_DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')

echo -e "${G}▸ Available RAM:${NC} ${AVAIL_RAM_MB}MB  ${G}▸ CPU Cores:${NC} ${CPU_CORES}  ${G}▸ Available Disk:${NC} ${AVAIL_DISK_GB}GB"

# ── Install deps ──
echo -e "${Y}▸ Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y -qq proot wget curl tmate sudo vim nano htop tmux 2>/dev/null || true

# ── Start Tmate on HOST (reliable) ──
echo -e "${Y}▸ Starting Tmate...${NC}"
tmate -S /tmp/tmate.sock new-session -d -x 256x48 2>/dev/null || true
tmate -S /tmp/tmate.sock wait tmate-ready 2>/dev/null || true

TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p "#{tmate_ssh}" 2>/dev/null || echo "waiting...")
TMATE_WEB=$(tmate -S /tmp/tmate.sock display -p "#{tmate_web}" 2>/dev/null || echo "waiting...")

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Tmate is running!${NC}"
echo -e "${G}║${NC}  SSH:  ${C}${TMATE_SSH}${NC}"
echo -e "${G}║${NC}  Web:  ${C}${TMATE_WEB}${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Download Ubuntu 24.04 rootfs ──
ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo -e "${Y}▸ Downloading Ubuntu 24.04 rootfs...${NC}"
    cd /tmp
    wget -q "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz
    
    echo -e "${Y}▸ Extracting rootfs (skipping /dev)...${NC}"
    cd "$ROOTFS_DIR"
    # --exclude='dev' skips the mknod errors entirely
    tar --exclude='dev' -xJf /tmp/ubuntu24-rootfs.tar.xz || true
    rm -f /tmp/ubuntu24-rootfs.tar.xz
    
    echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.4.4" >> "$ROOTFS_DIR/etc/resolv.conf"
    
    echo -e "${Y}▸ Installing packages inside Ubuntu 24...${NC}"
    proot -0 -w / -b /dev -b /proc -b /sys -r "$ROOTFS_DIR" /bin/bash -c '
        apt-get update -qq
        apt-get install -y -qq curl wget vim nano htop tmux sudo ca-certificates openssh-client python3 2>/dev/null
        apt-get clean
    '
    
    proot -0 -w / -b /dev -b /proc -b /sys -r "$ROOTFS_DIR" /bin/bash -c '
        useradd -m -s /bin/bash dev
        echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    '
    
    REPO_RAW="https://raw.githubusercontent.com/vabshi8-cpu/bookish-lamp/main"
    curl -sL "${REPO_RAW}/.bashrc" -o "$ROOTFS_DIR/home/dev/.bashrc"
    chown 1000:1000 "$ROOTFS_DIR/home/dev/.bashrc" 2>/dev/null || true
    
    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Ubuntu 24 rootfs already exists, skipping download.${NC}"
fi

# ── Drop into Ubuntu 24 ──
echo -e "${Y}▸ Dropping into Ubuntu 24 shell... (type exit to return)${NC}"
exec proot -0 -w /home/dev -b /dev -b /proc -b /sys -r "$ROOTFS_DIR" /bin/bash --login
