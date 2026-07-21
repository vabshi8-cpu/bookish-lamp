#!/usr/bin/env bash
set -eo pipefail

export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

C='\033[0;36m' G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║     Ubuntu 24.04 LTS Setup (Native SSH / Dropbear)     ║${NC}"
echo -e "${C}╚════════════════════════════════════════════════════════╝${NC}"

CPU_CORES=$(nproc 2>/dev/null || echo "32")
ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo -e "${Y}▸ Downloading Ubuntu 24.04 rootfs...${NC}"
    cd /tmp
    wget -q --show-progress "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz

    echo -e "${Y}▸ Unpacking environment...${NC}"
    cd "$ROOTFS_DIR"
    tar -I "xz -T0" --exclude='dev/*' -xf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || tar --exclude='dev/*' -xJf /tmp/ubuntu24-rootfs.tar.xz 2>/dev/null || true
    rm -f /tmp/ubuntu24-rootfs.tar.xz

    mkdir -p "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/tmp"
    touch "$ROOTFS_DIR/dev/null" "$ROOTFS_DIR/dev/zero" "$ROOTFS_DIR/dev/random" "$ROOTFS_DIR/dev/urandom" 2>/dev/null || true

    rm -rf "$ROOTFS_DIR/etc/resolv.conf"
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
    else
        echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    fi

    echo -e "${Y}▸ Installing Dropbear SSH server...${NC}"
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
        apt-get install -y -qq dropbear sudo 2>/dev/null || true
        echo "root:ubuntu" | chpasswd
    '
    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Existing setup found. Fast-booting...${NC}"
fi

# Clean up old processes
pkill -f "dropbear" 2>/dev/null || true
pkill -f "a.pinggy.io" 2>/dev/null || true
rm -f /tmp/pinggy_tcp.log

# Start Dropbear inside PRoot on local port 2222
echo -e "${Y}▸ Starting Dropbear SSH server inside container...${NC}"
proot -0 -r "$ROOTFS_DIR" /usr/sbin/dropbear -p 2222 -R -E 2>/dev/null &

# Establish Pinggy TCP tunnel to local port 2222
echo -e "${Y}▸ Establishing TCP tunnel for native SSH...${NC}"
ssh -o StrictHostKeyChecking=no -p 443 -R0:localhost:2222 tcp@a.pinggy.io > /tmp/pinggy_tcp.log 2>&1 &

# Wait for tunnel endpoint
echo -e "${Y}▸ Waiting for tunnel endpoint...${NC}"
for i in {1..10}; do
    if grep -q "tcp://" /tmp/pinggy_tcp.log; then
        break
    fi
    sleep 1
done

# Extract TCP host and port from pinggy output
PINGGY_LINE=$(grep -o 'tcp://[^[:space:]]*' /tmp/pinggy_tcp.log | head -n 1 || echo "")
if [ -n "$PINGGY_LINE" ]; then
    CLEAN_HOSTPORT=${PINGGY_LINE#tcp://}
    HOST_PART=$(echo "$CLEAN_HOSTPORT" | cut -d':' -f1)
    PORT_PART=$(echo "$CLEAN_HOSTPORT" | cut -d':' -f2)
else
    HOST_PART="FAILED"
    PORT_PART=""
fi

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Native SSH Ready! Run this in your Windows Terminal:${NC}"
echo -e "${G}║${NC}"
echo -e "${G}║  ${C}ssh -p ${PORT_PART} root@${HOST_PART}${NC}"
echo -e "${G}║${NC}  Password: ${C}ubuntu${NC}"
echo -e "${G}║${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Fallback local shell
exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /root /bin/bash -l
