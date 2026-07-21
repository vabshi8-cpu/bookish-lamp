# ── Ubuntu 24 Terminal .bashrc ──

# Colors
R='\[\033[0;31m\]' G='\[\033[0;32m\]' Y='\[\033[1;33m\]' B='\[\033[1;34m\]'
C='\[\033[0;36m\]' W='\[\033[1;37m\]' NC='\[\033[0m\]'

# Prompt: ┌[ubuntu24] [dev] [~/path] [ram%] [cpu]
#         └▪ 
_ram_pct() { free | awk '/Mem:/{printf "%.0f", $3/$2*100}'; }
_cpu_load() { awk '{printf "%.1f", $1}' /proc/loadavg 2>/dev/null || echo "0"; }

PS1="${C}┌──[${G}ubuntu24${C}]─[${Y}\u${C}]─[${B}\w${C}]─[\${(_ram_pct)}%⚡\${(_cpu_load)}]─[${G}\$?${C}]\n${C}└──▪${NC} "

# Aliases
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias cls='clear'
alias ports='ss -tlnp'
alias myip='curl -s ifconfig.me'
alias dock='docker'
alias dc='docker compose'
alias size='du -sh'

# History
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend

# Path
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=vim

# Welcome
echo -e "\033[0;36m  Type 'exit' to leave. Tmate running on /tmp/tmate.sock\033[0m"
