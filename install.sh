#!/usr/bin/env bash
set +e

export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

echo "=== Ubuntu 24.04 GUI Setup for Railway ==="

# Install host-side dependencies
apt-get update -y -qq || true
apt-get install -y -qq websockify wget procps git curl 2>/dev/null || true

# Railway provides a dynamic PORT. Fall back to 6080 if not present.
WEB_PORT="${PORT:-6080}"

# Detect System Resources (RAM & Disk / ROM)
TOTAL_RAM=$(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || echo "Unknown")
TOTAL_DISK=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "Unknown")
AVAIL_DISK=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "Unknown")

ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo "Downloading rootfs..."
    cd /tmp
    wget -q "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O rootfs.tar.xz
    cd "$ROOTFS_DIR"
    tar -xf /tmp/rootfs.tar.xz 2>/dev/null || true
    rm -f /tmp/rootfs.tar.xz

    mkdir -p dev etc proc sys tmp
    touch dev/null dev/zero dev/random dev/urandom 2>/dev/null || true

    echo "nameserver 8.8.8.8" > etc/resolv.conf

    echo "Configuring apt inside rootfs..."
    cat << 'EOF' > /tmp/setup.sh
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/apt/apt.conf.d/
echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99proot-fix
echo 'Acquire::ForceIPv4 "true";' >> /etc/apt/apt.conf.d/99proot-fix
echo 'Acquire::AllowInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99proot-fix

cat << 'AEOF' > /etc/apt/sources.list
deb [trusted=yes] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb [trusted=yes] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb [trusted=yes] http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb [trusted=yes] http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
AEOF

apt-get update -y -qq || true
apt-get install -y -qq xfce4 xfce4-goodies tigervnc-standalone-server sudo curl wget nano 2>/dev/null || true
EOF

    chmod +x /tmp/setup.sh
    proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys /tmp/setup.sh
    rm -f /tmp/setup.sh

    mkdir -p usr/share/novnc
    git clone https://github.com/novnc/noVNC.git usr/share/novnc 2>/dev/null || true

    touch .setup_done
fi

kill $(pgrep -f Xvnc) 2>/dev/null || true
kill $(pgrep -f websockify) 2>/dev/null || true

mkdir -p "$ROOTFS_DIR/root/.vnc"
echo '#!/bin/bash' > "$ROOTFS_DIR/root/.vnc/xstartup"
echo 'unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS' >> "$ROOTFS_DIR/root/.vnc/xstartup"
echo 'startxfce4 &' >> "$ROOTFS_DIR/root/.vnc/xstartup"
chmod +x "$ROOTFS_DIR/root/.vnc/xstartup"

proot -0 -r "$ROOTFS_DIR" /bin/bash -c 'echo "ubuntu" | vncpasswd -f > /root/.vnc/passwd && chmod 600 /root/.vnc/passwd' 2>/dev/null || true

echo "Starting VNC server..."
proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys vncserver -kill :1 2>/dev/null || true
proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys vncserver :1 -geometry 1280x720 -depth 24 2>/dev/null || true

echo "Starting websockify on Railway port $WEB_PORT..."
websockify --web "$ROOTFS_DIR/usr/share/novnc/" "$WEB_PORT" localhost:5901 > /dev/null 2>&1 &

echo ""
echo "=========================================================="
echo " Ubuntu 24.04 GUI Desktop Ready on Railway!"
echo " --------------------------------------------------------"
echo " Detected RAM:  $TOTAL_RAM"
echo " Detected Disk: $TOTAL_DISK (Free: $AVAIL_DISK)"
echo " --------------------------------------------------------"
echo " How to access:"
echo " 1. Go to your Railway project dashboard settings."
echo " 2. Open your assigned public Domain URL."
echo " 3. Use URL suffix: /vnc.html?password=ubuntu"
echo " Password: ubuntu"
echo "=========================================================="
echo ""
echo "24/7 Uptime Guardian active. Railway will keep this running."

# 24/7 Uptime Guardian Loop: Auto-restarts services if they drop & keeps container alive
while true; do
    if ! pgrep -f Xvnc > /dev/null; then
        proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys vncserver :1 -geometry 1280x720 -depth 24 2>/dev/null || true
    fi
    if ! pgrep -f websockify > /dev/null; then
        websockify --web "$ROOTFS_DIR/usr/share/novnc/" "$WEB_PORT" localhost:5901 > /dev/null 2>&1 &
    fi
    sleep 30
done
