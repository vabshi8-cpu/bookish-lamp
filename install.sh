#!/usr/bin/env bash
set +e

export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

echo "=== Ubuntu 24.04 GUI Setup ==="

# Install host-side dependencies required for networking & proxying
apt-get update -y -qq || true
apt-get install -y -qq websockify openssh-client wget procps git 2>/dev/null || true

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
kill $(pgrep -f free.pinggy.io) 2>/dev/null || true
rm -f /tmp/pinggy_gui.log

mkdir -p "$ROOTFS_DIR/root/.vnc"
echo '#!/bin/bash' > "$ROOTFS_DIR/root/.vnc/xstartup"
echo 'unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS' >> "$ROOTFS_DIR/root/.vnc/xstartup"
echo 'startxfce4 &' >> "$ROOTFS_DIR/root/.vnc/xstartup"
chmod +x "$ROOTFS_DIR/root/.vnc/xstartup"

proot -0 -r "$ROOTFS_DIR" /bin/bash -c 'echo "ubuntu" | vncpasswd -f > /root/.vnc/passwd && chmod 600 /root/.vnc/passwd' 2>/dev/null || true

echo "Starting VNC server..."
proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys vncserver -kill :1 2>/dev/null || true
proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys vncserver :1 -geometry 1280x720 -depth 24 2>/dev/null || true

echo "Starting websockify on host..."
websockify --web "$ROOTFS_DIR/usr/share/novnc/" 6080 localhost:5901 > /dev/null 2>&1 &

echo "Starting tunnel..."
ssh -o StrictHostKeyChecking=no -p 443 -R0:localhost:6080 free.pinggy.io > /tmp/pinggy_gui.log 2>&1 &

echo "Waiting for tunnel URL..."
WEB_URL=""
for i in {1..15}; do
    if [ -f /tmp/pinggy_gui.log ]; then
        WEB_URL=$(grep -o 'https://[^[:space:]]*pinggy[^[:space:]]*' /tmp/pinggy_gui.log | head -n 1)
        if [ -n "$WEB_URL" ]; then
            break
        fi
    fi
    sleep 1
done

[ -z "$WEB_URL" ] && WEB_URL="https://failed-to-grab-url"
DOMAIN_PART=$(echo "$WEB_URL" | cut -d'/' -f3)

echo ""
echo "=========================================================="
echo " Ubuntu 24.04 GUI Desktop Ready!"
echo " URL:      $WEB_URL/vnc.html?host=$DOMAIN_PART&port=443&password=ubuntu"
echo " Password: ubuntu"
echo "=========================================================="
echo ""

exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /root /bin/bash -l
