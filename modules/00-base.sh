#!/usr/bin/env bash
# Module: base — apt packages every later module assumes, plus git identity.
set -euo pipefail
MODULE=base
# shellcheck source=../lib/common.sh
. "$STACK_ROOT/lib/common.sh"
need_root
already_done "$MODULE" && { ok "base already installed"; exit 0; }
load_env

export DEBIAN_FRONTEND=noninteractive
log "apt update"
apt-get update -qq

# Deliberately the surveyed set: build-essential is needed by node-gyp builds
# inside plugin installs, sqlite3/jq/unzip by the agents' own scripts, tmux and
# screen by firstmate's tmux backend.
apt-get install -y -qq \
  build-essential ca-certificates curl wget git gnupg jq unzip sqlite3 \
  tmux screen byobu htop net-tools vim nano python3 \
  software-properties-common

# GitHub CLI from its own apt repo (the agents drive releases and projects with it).
if ! have gh; then
  mkdir -p -m 755 /etc/apt/keyrings
  wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq
  apt-get install -y -qq gh
fi
ok "gh $(gh --version | head -1)"

git config --global user.name "${GIT_USER_NAME:-root}"
git config --global user.email "${GIT_USER_EMAIL:-root@localhost}"
git config --global init.defaultBranch main

mark_done "$MODULE"
ok "base ready"
