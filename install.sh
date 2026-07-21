#!/usr/bin/env bash
set -eo pipefail

export PROOT_NO_SECCOMP=1
export DEBIAN_FRONTEND=noninteractive

C='\033[0;36m' G='\033[0;32m' Y='\033[1;33m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║     Ubuntu 24.04 LTS Setup (Full GUI Desktop Mode)    ║${NC}  
echo -e "${C}╚════════════════════════════════════════════════════════╝${NC}"

CPU_CORES=$(nproc 2>/dev/null || echo "32")
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

    mkdir -p "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/tmp"
    touch "$ROOTFS_DIR/dev/null" "$ROOTFS_DIR/dev/zero" "$ROOTFS_DIR/dev/random" "$ROOTFS_DIR/dev/urandom" 2>/dev/null || true

    rm -rf "$ROOTFS_DIR/etc/resolv.conf"
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
    else
        echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
    fi

    echo -e "${Y}▸ Installing XFCE4 Desktop, VNC, and GUI utilities...${NC}"
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
        apt-get install -y -qq xfce4 xfce4-goodies tigervnc-standalone-server websockify git sudo curl wget nano 2>/dev/null || true
    '

    echo -e "${Y}▸ Setting up noVNC web interface...${NC}"
    mkdir -p "$ROOTFS_DIR/usr/share/novnc"
    git clone https://github.com/novnc/noVNC.git "$ROOTFS_DIR/usr/share/novnc" 2>/dev/null || true

    touch "$ROOTFS_DIR/.setup_done"
else
    echo -e "${G}▸ Existing setup found. Fast-booting...${NC}"
fi

# Clean up old processes/tunnels
pkill -f "Xvnc" 2>/dev/null || true
pkill -f "websockify" 2>/dev/null || true
pkill -f "free.pinggy.io" 2>/dev/null || true
rm -f /tmp/pinggy_gui.log

# Configure VNC configuration safely from host
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

# Start VNC Server inside PRoot on display :1 (Port 5901)
echo -e "${Y}▸ Starting Virtual Desktop (TigerVNC)...${NC}"
proot -0 -r "$ROOTFS_DIR" vncserver -kill :1 2>/dev/null || true
proot -0 -r "$ROOTFS_DIR" vncserver :1 -geometry 1280x720 -depth 24 2>/dev/null || true

# Start noVNC Websockify server on local port 6080 bridging to VNC port 5901
echo -e "${Y}▸ Starting noVNC Web Server...${NC}"
proot -0 -r "$ROOTFS_DIR" websockify --web /usr/share/novnc/ 6080 localhost:5901 > /dev/null 2>&1 &

# Establish Pinggy HTTPS tunnel pointing to local port 6080
echo -e "${Y}▸ Establishing secure web tunnel...${NC}"
ssh -o StrictHostKeyChecking=no -p 443 -R0:localhost:6080 free.pinggy.io > /tmp/pinggy_gui.log 2>&1 &

# Wait for tunnel endpoint
echo -e "${Y}▸ Generating secure desktop link...${NC}"
for i in {1..12}; do
    if grep -q "https://" /tmp/pinggy_gui.log; then
        break
    fi
    sleep 1
done

WEB_URL=$(grep -o 'https://[^[:space:]]*' /tmp/pinggy_gui.log | head -n 1 || echo "Failed to get tunnel")

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Ubuntu 24.04 GUI Desktop Ready! Open in your browser:${NC}"
echo -e "${G}║${NC}"
echo -e "${G}║  URL:      ${C}${WEB_URL}/vnc.html?host=$(echo $WEB_URL | awk -F/ '{print $3}')&port=443&password=ubuntu${NC}"
echo -e "${G}║${NC}  Password: ${C}ubuntu${NC}"
echo -e "${G}║${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Fallback local shell
exec proot -0 -r "$ROOTFS_DIR" -b /dev -b /proc -b /sys -w /root /bin/bash -l
