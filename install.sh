#!/usr/bin/env bash
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔══════════════════════════════════════════╗${NC}"
echo -e "${C}║   Ubuntu 24 Terminal Setup               ║${NC}"
echo -e "${C}╚══════════════════════════════════════════╝${NC}"

# ── Detect AVAILABLE resources ──
AVAIL_RAM_MB=$(awk '/MemAvailable/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || echo "N/A")
AVAIL_DISK_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "N/A")

echo -e "${G}▸ Available RAM:${NC} ${AVAIL_RAM_MB}MB  ${G}▸ CPU Cores:${NC} ${CPU_CORES}  ${G}▸ Available Disk:${NC} ${AVAIL_DISK_GB}GB"

# ── Install host dependencies ──
echo -e "${Y}▸ Installing host dependencies...${NC}"
apt-get update -qq || true
apt-get install -y -qq proot wget curl tmate sudo vim nano htop tmux 2>/dev/null || true

# ── Download and Configure Ubuntu 24.04 ──
ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo -e "${Y}▸ Downloading Ubuntu 24.04 rootfs...${NC}"
    cd /tmp
    wget -q "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz
    
    echo -e "${Y}▸ Extracting rootfs...${NC}"
    cd "$ROOTFS_DIR"
    tar -xJf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || true
    rm -f /tmp/ubuntu24-rootfs.tar.xz
    
    # Pre-create necessary directories and pseudo-devices
    mkdir -p "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys"
    touch "$ROOTFS_DIR/dev/null" 2>/dev/null || true

    # Force DNS
    rm -f "$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.4.4" >> "$ROOTFS_DIR/etc/resolv.conf"
    
    echo -e "${Y}▸ Bypassing APT limits & fixing cache permissions...${NC}"
    
    # Fix AppStream writable error permanently
    mkdir -p "$ROOTFS_DIR/var/cache/swcatalog/cache"
    chmod -R 777 "$ROOTFS_DIR/var/cache/swcatalog" 2>/dev/null || true
    
    # Execute bootstrapper inside proot
    proot -0 -r "$ROOTFS_DIR" -w / /bin/bash -c '
        export DEBIAN_FRONTEND=noninteractive
        
        # Force-install Ubuntu GPG keys by downloading the raw DEB package (Bypasses NO_PUBKEY completely)
        wget -q "http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2023.11.28.1_all.deb" -O /tmp/keyring.deb
        dpkg -i /tmp/keyring.deb 2>/dev/null || true
        rm -f /tmp/keyring.deb
        
        # Now apt-get update will verify flawlessly!
        apt-get update -qq
        apt-get install -y -qq curl wget vim nano htop tmux sudo openssh-client python3
        apt-get clean
    '
    
    # Create user
    proot -0 -r "$ROOTFS_DIR" -w / /bin/bash -c '
        useradd -m -s /bin/bash dev 2>/dev/null || true
        echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    '
    
    # Fetch user configuration
    REPO_RAW="https://raw.githubusercontent.com/vabshi8-cpu/bookish-lamp/main"
    curl -sL "${REPO_RAW}/.bashrc" -o "$ROOTFS_DIR/home/dev/.bashrc" 2>/dev/null || true
    chown -R 1000:1000 "$ROOTFS_DIR/home/dev" 2>/dev/null || true
    
    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Ubuntu 24 rootfs already exists, skipping download.${NC}"
fi

# ── Start Tmate (Bulletproof Window Sizing) ──
echo -e "${Y}▸ Starting Tmate (Ubuntu 24 session)...${NC}"

PROOT_CMD="proot -0 -r $ROOTFS_DIR -b /dev -b /proc -b /sys -w /home/dev /bin/bash"

# Clean up stale locks and TMUX environments
unset TMUX
tmate -S /tmp/tmate.sock kill-server 2>/dev/null || true
rm -f /tmp/tmate.sock

# Start tmate with absolute fallback dimensions (-x 120 width, -y 40 height)
tmate -S /tmp/tmate.sock new-session -d -x 120 -y 40 "$PROOT_CMD"
tmate -S /tmp/tmate.sock wait tmate-ready 2>/dev/null || true

# Extract SSH and Web links
TMATE_SSH=""
for i in {1..15}; do
    TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p "#{tmate_ssh}" 2>/dev/null || echo "")
    if [[ "$TMATE_SSH" == *"ssh"* ]]; then
        break
    fi
    sleep 1
done

TMATE_WEB=$(tmate -S /tmp/tmate.sock display -p "#{tmate_web}" 2>/dev/null || echo "waiting...")

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Setup Complete! Connect from your PC:${NC}"
echo -e "${G}║${NC}  SSH:  ${C}${TMATE_SSH}${NC}"
echo -e "${G}║${NC}  Web:  ${C}${TMATE_WEB}${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Drop locally into rootfs shell
echo -e "${Y}▸ Dropping into Ubuntu 24 shell locally...${NC}"
exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /home/dev /bin/bash
