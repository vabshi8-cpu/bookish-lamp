#!/bin/bash
source /home/dev/.bashrc

# ── Resource detection ──
RAM_MB=$(free -m | awk '/Mem:/{print $2}')
CPU_N=$(nproc)
DISK_GB=$(df -hG / | tail -1 | awk '{print $2}')

echo ""
echo -e "\033[0;36m╔═══════════════════════════════════════════════════╗\033[0m"
echo -e "\033[0;36m║\033[1;37m  🐧 Ubuntu 24.04 Container Terminal\033[0m"
echo -e "\033[0;36m╠═══════════════════════════════════════════════════╣\033[0m"
echo -e "\033[0;36m║\033[0m  RAM:  \033[1;32m${RAM_MB}MB\033[0m"
echo -e "\033[0;36m║\033[0m  CPU:  \033[1;32m${CPU_N} cores\033[0m"
echo -e "\033[0;36m║\033[0m  Disk: \033[1;32m${DISK_GB}GB\033[0m"
echo -e "\033[0;36m║\033[0m  Docker: \033[1;32m$(docker --version 2>/dev/null | awk '{print $3}' || echo 'socket mount needed')\033[0m"
echo -e "\033[0;36m╚═══════════════════════════════════════════════════╝\033[0m"
echo ""

# ── Start Tmate ──
tmate -S /tmp/tmate.sock new-session -d -x 256x48 2>/dev/null || true
tmate -S /tmp/tmate.sock wait tmate-ready 2>/dev/null || true

TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}' 2>/dev/null)
TMATE_WEB=$(tmate -S /tmp/tmate.sock display -p '#{tmate_web}' 2>/dev/null)

echo -e "\033[1;33m▸ Tmate SSH:  ${TMATE_SSH}\033[0m"
echo -e "\033[1;33m▸ Tmate Web:  ${TMATE_WEB}\033[0m"
echo ""

# ── Keep alive ──
sleep infinity &
wait
