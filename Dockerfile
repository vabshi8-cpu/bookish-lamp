FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# ── Base system + Docker CLI + Tmate ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git vim nano htop tmux tree jq unzip \
    ca-certificates gnupg lsb-release sudo \
    openssh-client sshpass net-tools iputils-ping \
    build-essential python3 python3-pip \
    tmate \
    && rm -rf /var/lib/apt/lists/*

# ── Install Docker CLI (for DinD socket use) ──
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user with sudo ──
RUN useradd -m -s /bin/bash dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY .bashrc /home/dev/.bashrc
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown dev:dev /home/dev/.bashrc

WORKDIR /workspace
USER dev

ENTRYPOINT ["/entrypoint.sh"]
