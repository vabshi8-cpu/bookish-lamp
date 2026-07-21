#!/usr/bin/env bash
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔══════════════════════════════════════════╗${NC}"
echo -e "${C}║   ${B}Ubuntu 24 Terminal Setup${C}               ║${NC}"
echo -e "${C}╚══════════════════════════════════════════╝${NC}"

# ── Detect resources ──
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
CPU_CORES=$(nproc 2>/dev/null || echo 1)
DISK_AVAIL_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')

echo -e "${G}▸ RAM:${NC} ${TOTAL_RAM_MB}MB  ${G}▸ CPU:${NC} ${CPU_CORES}  ${G}▸ Disk free:${NC} ${DISK_AVAIL_GB}GB"

# ── Install deps ──
echo -e "${Y}▸ Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y -qq proot wget curl tmate sudo vim nano htop tmux 2>/dev/null || true

# ── Download Ubuntu 24.04 rootfs ──
ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo -e "${Y}▸ Downloading Ubuntu 24.04 rootfs...${NC}"
    cd /tmp
    wget -q "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz
    
    echo -e "${Y}▸ Extracting rootfs...${NC}"
    cd "$ROOTFS_DIR"
    tar -xJf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || tar -xf /tmp/ubuntu24-rootfs.tar.xz
    rm -f /tmp/ubuntu24-rootfs.tar.xz
    
    # ── Setup resolv ──
    echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.4.4" >> "$ROOTFS_DIR/etc/resolv.conf"
    
    # ── Install packages inside rootfs ──
    echo -e "${Y}▸ Installing packages inside Ubuntu 24...${NC}"
    proot -0 -w / -b /dev -b /proc -b /sys -r "$ROOTFS_DIR" /bin/bash -c '
        apt-get update -qq
        apt-get install -y -qq curl wget vim nano htop tmux tmate sudo ca-certificates openssh-client python3 2>/dev/null
        apt-get clean
    '
    
    # ── Create user ──
    proot -0 -w / -b /dev -b /proc -b /sys -r "$ROOTFS_DIR" /bin/bash -c '
        useradd -m -s /bin/bash dev
        echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    '
    
    # ── Copy .bashrc ──
    REPO_RAW="https://raw.githubusercontent.com/vabshi8-cpu/bookish-lamp/main"
    curl -sL "${REPO_RAW}/.bashrc" -o "$ROOTFS_DIR/home/dev/.bashrc"
    chown 1000:1000 "$ROOTFS_DIR/home/dev/.bashrc" 2>/dev/null || true
    
    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Ubuntu 24 rootfs already exists, skipping download.${NC}"
fi

# ── Start Tmate inside proot ──
echo -e "${Y}▸ Starting Tmate inside Ubuntu 24...${NC}"

proot -0 -w /home/dev -b /dev -b /proc -b /sys -b /tmp:/tmate-sock -r "$ROOTFS_DIR" /bin/bash -c '
    source /home/dev/.bashrc
    
    RAM_MB=$(free -m | awk "/Mem:/{print \$2}")
    CPU_N=$(nproc)
    DISK_GB=$(df -hG / | tail -1 | awk "{print \$2}")
    
    echo ""
    echo -e "\033[0;36m╔═══════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[0;36m║\033[1;37m  🐧 Ubuntu 24.04 Terminal (proot)\033[0m"
    echo -e "\033[0;36m╠═══════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[0;36m║\033[0m  RAM:  \033[1;32m${RAM_MB}MB\033[0m"
    echo -e "\033[0;36m║\033[0m  CPU:  \033[1;32m${CPU_N} cores\033[0m"
    echo -e "\033[0;36m║\033[0m  Disk: \033[1;32m${DISK_GB}GB\033[0m"
    echo -e "\033[0;36m╚═══════════════════════════════════════════════════╝\033[0m"
    echo ""
    
    tmate -S /tmate-sock/tmate.sock new-session -d -x 256x48 2>/dev/null || true
    tmate -S /tmate-sock/tmate.sock wait tmate-ready 2>/dev/null || true
    
    TMATE_SSH=$(tmate -S /tmate-sock/tmate.sock display -p "#{tmate_ssh}" 2>/dev/null)
    TMATE_WEB=$(tmate -S /tmate-sock/tmate.sock display -p "#{tmate_web}" 2>/dev/null)
    
    echo -e "\033[1;33m▸ Tmate SSH:  ${TMATE_SSH}\033[0m"
    echo -e "\033[1;33m▸ Tmate Web:  ${TMATE_WEB}\033[0m"
    echo ""
    
    sleep infinity
' &

sleep 5

# ── Read tmate output ──
if [ -f /tmp/tmate-sock/tmate.sock ]; then
    TMATE_SSH=$(tmate -S /tmp/tmate-sock/tmate.sock display -p "#{tmate_ssh}" 2>/dev/null || echo "waiting...")
    TMATE_WEB=$(tmate -S /tmp/tmate-sock/tmate.sock display -p "#{tmate_web}" 2>/dev/null || echo "waiting...")
else
    TMATE_SSH="check: cat /tmp/tmate-ssh.txt"
    TMATE_WEB="check: cat /tmp/tmate-web.txt"
fi

echo ""
echo -e "${G}╔══════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Ubuntu 24 is running!${NC}"
echo -e "${G}║${NC}  Enter:   ${C}proot -0 -w /home/dev -b /dev -b /proc -b /sys -r ~/ubuntu24 /bin/bash${NC}"
echo -e "${G}║${NC}  Tmate:   ${C}${TMATE_SSH}${NC}"
echo -e "${G}╚══════════════════════════════════════════╝${NC}"
