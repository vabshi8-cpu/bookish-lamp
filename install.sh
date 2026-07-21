#!/usr/bin/env bash
set -euo pipefail

# ── Colors ──
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

echo -e "${C}╔══════════════════════════════════════════╗${NC}"
echo -e "${C}║   ${B}Ubuntu 24 Container Terminal Setup${C}      ║${NC}"
echo -e "${C}╚══════════════════════════════════════════╝${NC}"

# ── Detect host resources ──
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
CONTAINER_RAM=$((TOTAL_RAM_MB - 256))
[[ $CONTAINER_RAM -lt 256 ]] && CONTAINER_RAM=256

CPU_CORES=$(nproc 2>/dev/null || echo 1)
TOTAL_DISK_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | tr -d 'G')
CONTAINER_DISK=$((TOTAL_DISK_GB - 5))
[[ $CONTAINER_DISK -lt 5 ]] && CONTAINER_DISK=5

echo -e "${G}▸ Host RAM:${NC} ${TOTAL_RAM_MB}MB → Container: ${CONTAINER_RAM}MB"
echo -e "${G}▸ CPU cores:${NC} ${CPU_CORES}"
echo -e "${G}▸ Disk:${NC} ${TOTAL_DISK_GB}GB → Container: ${CONTAINER_DISK}GB"

# ── Install Docker if missing ──
if ! command -v docker &>/dev/null; then
    echo -e "${Y}▸ Docker not found. Installing...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl start docker 2>/dev/null || true
    systemctl enable docker 2>/dev/null || true
fi

# ── Download repo files ──
WORKDIR="/tmp/ubuntu-terminal-$$"
mkdir -p "$WORKDIR"

REPO_RAW="https://raw.githubusercontent.com/vabshi8-cpu/bookish-lamp/main"

for f in Dockerfile entrypoint.sh .bashrc docker-compose.yml; do
    echo -e "${C}▸ Downloading ${f}...${NC}"
    curl -fsSL "${REPO_RAW}/${f}" -o "${WORKDIR}/${f}"
done
chmod +x "${WORKDIR}/entrypoint.sh"

# ── Build & Run ──
echo -e "${Y}▸ Building container...${NC}"
docker build -t ubuntu24-terminal "$WORKDIR"

echo -e "${Y}▸ Launching container...${NC}"
docker run -d \
    --name ubuntu24-term \
    --hostname ubuntu24 \
    -m ${CONTAINER_RAM}m \
    --cpus=${CPU_CORES} \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${WORKDIR}:/workspace" \
    --restart unless-stopped \
    ubuntu24-terminal

echo ""
echo -e "${G}╔══════════════════════════════════════════╗${NC}"
echo -e "${G}║  ${B}Container is running!${NC}"
echo -e "${G}║${NC}  Attach:  ${C}docker exec -it ubuntu24-term bash${NC}"
echo -e "${G}║${NC}  Tmate:   ${C}docker logs ubuntu24-term 2>&1 | grep 'ssh'${NC}"
echo -e "${G}╚══════════════════════════════════════════╝${NC}"
