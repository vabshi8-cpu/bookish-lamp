#!/usr/bin/env bash
set -euo pipefail

# ── KERNEL & ENVIRONMENT FIXES ──
export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

C='\033[0;36m' G='\033[0;32m' Y='\033[1;33m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║        Ubuntu 24.04 LTS Setup (God Mode Fixed)         ║${NC}"
echo -e "${C}╚════════════════════════════════════════════════════════╝${NC}"

# ── RESOURCE CHECK ──
AVAIL_RAM_MB=$(awk '/MemAvailable/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || echo "N/A")
AVAIL_DISK_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "N/A")

echo -e "${G}▸ RAM:${NC} ${AVAIL_RAM_MB} MB  |  ${G}CPUs:${NC} ${CPU_CORES}  |  ${G}Disk:${NC} ${AVAIL_DISK_GB} GB"

# ── HOST DEPENDENCIES ──
echo -e "${Y}▸ Installing host dependencies...${NC}"
apt-get update -y || true
apt-get install -y proot wget curl tmate sudo xz-utils openssh-client 2>/dev/null || true

# Pre-generate SSH keys on HOST so Tmate doesn't crash
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
fi

# Set host SSH keepalives for tmate connection
cat <<EOF > ~/.ssh/config
Host *
    ServerAliveInterval 5
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF
chmod 600 ~/.ssh/config 2>/dev/null || true

# ── ROOTFS PROVISIONING ──
ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo -e "${Y}▸ Downloading Ubuntu 24.04 rootfs...${NC}"
    cd /tmp
    wget -q --show-progress "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz

    echo -e "${Y}▸ Unpacking environment...${NC}"
    cd "$ROOTFS_DIR"
    tar -xJf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || true
    rm -f /tmp/ubuntu24-rootfs.tar.xz

    # Directory skeleton fix
    mkdir -p "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/tmp"
    touch "$ROOTFS_DIR/dev/null" 2>/dev/null || true

    # Fix DNS inside rootfs
    rm -rf "$ROOTFS_DIR/etc/resolv.conf"
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
    else
        echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    fi

    echo -e "${Y}▸ Patching APT settings (Bypassing GPG & IPC Sandboxes)...${NC}"

    proot -0 -r "$ROOTFS_DIR" -w / /bin/bash -c '
        mkdir -p /etc/apt/apt.conf.d/
        cat <<EOF > /etc/apt/apt.conf.d/99proot-fix
APT::Sandbox::User "root";
Acquire::ForceIPv4 "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF

        rm -rf /etc/apt/sources.list.d/*
        cat <<EOF > /etc/apt/sources.list
deb [trusted=yes allow-insecure=yes] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb [trusted=yes allow-insecure=yes] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb [trusted=yes allow-insecure=yes] http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb [trusted=yes allow-insecure=yes] http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF
    '

    # User setup inside rootfs
    proot -0 -r "$ROOTFS_DIR" -w / /bin/bash -c '
        useradd -m -s /bin/bash dev 2>/dev/null || true
        echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    '

    REPO_RAW="https://raw.githubusercontent.com/vabshi8-cpu/bookish-lamp/main"
    curl -sL "${REPO_RAW}/.bashrc" -o "$ROOTFS_DIR/home/dev/.bashrc" 2>/dev/null || true
    chown -R 1000:1000 "$ROOTFS_DIR/home/dev" 2>/dev/null || true

    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Existing setup found. Skipping extraction.${NC}"
fi

# ── TMATE REMOTE ACCESS ──
echo -e "${Y}▸ Initializing Remote Access (Tmate)...${NC}"

PROOT_CMD="proot -0 -r $ROOTFS_DIR -b /dev -b /proc -b /sys -w /home/dev /bin/bash -l"

unset TMUX
killall -9 tmate 2>/dev/null || true
tmate -S /tmp/tmate.sock kill-server 2>/dev/null || true
rm -f /tmp/tmate.sock

# Start background tmate
tmate -S /tmp/tmate.sock new-session -d -x 120 -y 40 "$PROOT_CMD" 2>/dev/null || true

echo -e "${Y}▸ Connecting to Tmate servers (10s max wait)...${NC}"
timeout 10 tmate -S /tmp/tmate.sock wait tmate-ready 2>/dev/null || true

TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p "#{tmate_ssh}" 2>/dev/null || echo "Connection timed out")
TMATE_WEB=$(tmate -S /tmp/tmate.sock display -p "#{tmate_web}" 2>/dev/null || echo "Connection timed out")

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Ubuntu 24 Ready! Connection info:${NC}"
echo -e "${G}║${NC}  SSH:  ${C}${TMATE_SSH}${NC}"
echo -e "${G}║${NC}  Web:  ${C}${TMATE_WEB}${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── ENTER LOCAL SHELL ──
echo -e "${Y}▸ Dropping directly into local shell...${NC}"
exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /home/dev /bin/bash -l
