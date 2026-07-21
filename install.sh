#!/usr/bin/env bash
set -eo pipefail

export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

echo "=== Ubuntu 24.04 LTS Setup (Full GUI Desktop Mode) ==="

ROOTFS_DIR="$HOME/ubuntu24"
mkdir -p "$ROOTFS_DIR"

if [ ! -f "$ROOTFS_DIR/.setup_done" ]; then
    echo "▸ Downloading Ubuntu 24.04 rootfs..."
    cd /tmp
    wget -q --show-progress "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz" -O ubuntu24-rootfs.tar.xz

    echo "▸ Unpacking environment..."
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

    echo "▸ Installing XFCE4 Desktop and VNC..."
    cat << 'EOF' > "$ROOTFS_DIR/tmp/guest_setup.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/apt/apt.conf.d/
echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99proot-fix
echo 'Acquire::ForceIPv4 "true";' >> /etc/apt/apt.conf.d/99proot-fix
echo 'Acquire::AllowInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99proot-fix

rm -rf /etc/apt/sources.list.d/*
cat << 'AEOF' > /etc/apt/sources.list
deb [trusted=yes allow-insecure=yes] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb [trusted=yes allow-insecure=yes] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb [trusted=yes allow-insecure=yes] http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb [trusted=yes allow-insecure=yes] http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
AEOF

apt-get update -y -qq || true
apt-get install -y -qq xfce4 xfce4-goodies tigervnc-standalone-server websockify git sudo curl wget nano 2>/dev/null || true
EOF

    chmod +x "$ROOTFS_DIR/tmp/guest_setup.sh"
    proot -0 -r "$ROOTFS_DIR" /tmp/guest_setup.sh
    rm -f "$ROOTFS_DIR/tmp/guest_setup.sh"

    echo "▸ Setting up noVNC web interface..."
    mkdir -p "$ROOTFS_DIR/usr/share/novnc"
    git clone https://github.com/novnc/noVNC.git "$ROOTFS_DIR/usr/share/novnc" 2>/dev/null || true

    touch "$ROOTFS_DIR/.setup_done"
else
    echo "▸ Existing setup found. Fast-booting..."
fi

pkill -f "Xvnc" 2>/dev/null || true
pkill -f "websockify" 2>/dev/null || true
pkill -f "free.pinggy.io" 2>/dev/null || true
rm -f /tmp/pinggy_gui.log

mkdir -p "$ROOTFS_DIR/root/.vnc"
cat << 'EOF' > "$ROOTFS_DIR/root/.vnc/xstartup"
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
startxfce4 &
EOF
chmod +x "$ROOTFS_DIR/root/.vnc/xstartup"

proot -0 -r "$ROOTFS_DIR" /bin/bash -c '
    echo "ubuntu" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
' 2>/dev/null || true

echo "▸ Starting Virtual Desktop..."
proot -0 -r "$ROOTFS_DIR" vncserver -kill :1 2>/dev/null || true
proot -0 -r "$ROOTFS_DIR" vncserver :1 -geometry 1280x720 -depth 24 2>/dev/null || true

echo "▸ Starting Web Server..."
proot -0 -r "$ROOTFS_DIR" websockify --web /usr/share/novnc/ 6080 localhost:5901 > /dev/null 2>&1 &

echo "▸ Establishing secure tunnel..."
ssh -o StrictHostKeyChecking=no -p 443 -R0:localhost:6080 free.pinggy.io > /tmp/pinggy_gui.log 2>&1 &

for i in {1..12}; do
    if grep -q "https://" /tmp/pinggy_gui.log; then
        break
    fi
    sleep 1
done

WEB_URL=$(grep -o 'https://[^[:space:]]*' /tmp/pinggy_gui.log | head -n 1 || echo "Failed")

if [ "$WEB_URL" != "Failed" ]; then
    DOMAIN_PART=$(echo "$WEB_URL" | cut -d'/' -f3)
else
    DOMAIN_PART="localhost"
fi

echo ""
echo "=========================================================="
echo " Ubuntu 24.04 GUI Desktop Ready!"
echo " URL:      $WEB_URL/vnc.html?host=$DOMAIN_PART&port=443&password=ubuntu"
echo " Password: ubuntu"
echo "=========================================================="
echo ""

exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /root /bin/bash -l
