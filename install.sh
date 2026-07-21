=#!/usr/bin/env bash
set -eo pipefail

export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

C='\033[0;36m' G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║     Ubuntu 24.04 LTS Setup (Pinggy Turbo Mode)        ║${NC}"
echo -e "${C}╚════════════════════════════════════════════════════════╝${NC}"

# Resource check
AVAIL_RAM_MB=$(awk '/MemAvailable/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || echo "32")
AVAIL_DISK_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "N/A")
echo -e "${G}▸ RAM:${NC} ${AVAIL_RAM_MB} MB  |  ${G}CPUs:${NC} ${CPU_CORES}  |  ${G}Disk:${NC} ${AVAIL_DISK_GB} GB"

# Host dependencies
MISSING_DEPS=()
for cmd in proot wget curl sudo xz ssh; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    apt-get update -y -qq || true
    apt-get install -y -qq proot wget curl sudo xz-utils openssh-client 2>/dev/null || true
fi

ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo -e "${Y}▸ Downloading Ubuntu 24.04 rootfs...${NC}"
    cd /tmp
    wget -q --show-progress "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz

    echo -e "${Y}▸ Unpacking environment using all ${CPU_CORES} CPU cores...${NC}"
    cd "$ROOTFS_DIR"
    tar -I "xz -T0" --exclude='dev/*' -xf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || tar --exclude='dev/*' -xJf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || true
    rm -f /tmp/ubuntu24-rootfs.tar.xz

    mkdir -p "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/tmp" "$ROOTFS_DIR/var/run/sshd"
    touch "$ROOTFS_DIR/dev/null" "$ROOTFS_DIR/dev/zero" "$ROOTFS_DIR/dev/random" "$ROOTFS_DIR/dev/urandom" 2>/dev/null || true

    rm -rf "$ROOTFS_DIR/etc/resolv.conf"
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
    else
        echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    fi

    echo -e "${Y}▸ Installing OpenSSH Server & configuring rootfs...${NC}"
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

        apt-get update -y -qq || true
        apt-get install -y -qq openssh-server sudo python3 nano htop 2>/dev/null || true
        
        # Configure SSH for root access without keys/passwords issues
        sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
        sed -i "s/#PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
        echo "root:ubuntu" | chpasswd
    '
    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Existing setup found. Fast-booting...${NC}"
fi

# Ensure sshd folder exists inside rootfs
mkdir -p "$ROOTFS_DIR/var/run/sshd"

# Start internal SSH server inside PRoot
echo -e "${Y}▸ Starting internal OpenSSH server...${NC}"
proot -0 -r "$ROOTFS_DIR" /usr/sbin/sshd 2>/dev/null || true

# Start Pinggy TCP tunnel in background mapping to container's port 22
echo -e "${Y}▸ Establishing Pinggy secure tunnel...${NC}"
pkill -f "a.pinggy.io" 2>/dev/null || true
rm -f /tmp/pinggy.url
ssh -o StrictHostKeyChecking=no -p 443 -R0:localhost:22 tcp@a.pinggy.io > /tmp/pinggy_raw.log 2>&1 &

# Extract Pinggy URL dynamically
echo -e "${Y}▸ Waiting for tunnel endpoint...${NC}"
for i in {1..10}; do
    if grep -q "tcp://" /tmp/pinggy_raw.log; then
        break
    fi
    sleep 1
done

PINGGY_URL=$(grep -o 'tcp://[^[:space:]]*' /tmp/pinggy_raw.log | head -n 1 || echo "Failed to get tunnel")

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Ubuntu 24 Ready! Connect from your PC:${NC}"
echo -e "${G}║${NC}  Command: ${C}ssh ${PINGGY_URL}${NC}"
echo -e "${G}║${NC}  Password:${C} ubuntu${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Enter local shell as fallback
exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /root /bin/bash -l
