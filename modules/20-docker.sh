#!/usr/bin/env bash
# Module: docker — docker-ce + compose plugin from Docker's own apt repo.
# Every composed-application module depends on this.
set -euo pipefail
MODULE=docker
. "$STACK_ROOT/lib/common.sh"
need_root
already_done "$MODULE" && { ok "docker already installed"; exit 0; }

if ! have docker; then
  export DEBIAN_FRONTEND=noninteractive
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker
docker compose version >/dev/null || die "docker compose plugin missing"
ok "$(docker --version), $(docker compose version | head -1)"
mark_done "$MODULE"
