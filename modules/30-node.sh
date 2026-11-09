#!/usr/bin/env bash
# Module: node — the two Node runtimes this host really runs on.
#   /opt/node22              : system Node for global CLIs (the *-axi tools)
#   ~/.local/share/pi-node   : the runtime dsh ships and runs under
# Separate on purpose: dsh pins its own Node and must not break when the system
# Node is upgraded.
set -euo pipefail
MODULE=node
. "$STACK_ROOT/lib/common.sh"
need_root
load_env

NODE22="${NODE22_VERSION:-22.21.1}"
if [ "$(/opt/node22/bin/node --version 2>/dev/null || true)" != "v$NODE22" ]; then
  log "installing system node v$NODE22 into /opt/node22"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/node.tar.xz" "https://nodejs.org/dist/v$NODE22/node-v$NODE22-linux-x64.tar.xz"
  tar -xf "$tmp/node.tar.xz" -C "$tmp"
  rm -rf /opt/node22
  mv "$tmp/node-v$NODE22-linux-x64" /opt/node22
  rm -rf "$tmp"
  for b in node npm npx; do ln -sf "/opt/node22/bin/$b" "/usr/local/bin/$b"; done
fi
ok "system node $(/opt/node22/bin/node --version)"

export PATH="/opt/node22/bin:$PATH"
# Global CLIs the agents call by name.
for pkg in tasks-axi gh-axi quota-axi chrome-devtools-axi; do
  if ! [ -x "/opt/node22/bin/$pkg" ]; then
    log "npm i -g $pkg"
    npm install -g "$pkg" >/dev/null 2>&1 || warn "$pkg install failed (non-fatal)"
  fi
  [ -x "/opt/node22/bin/$pkg" ] && ln -sf "/opt/node22/bin/$pkg" /usr/local/bin/
done

# uv — runs the Hindsight daemon through uvx. System-wide, because the
# unprivileged hindsight user needs it too.
if ! have uv; then
  log "installing uv"
  curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
fi
ok "uv $(uv --version 2>/dev/null || echo missing)"

grep -q '/opt/node22/bin' /root/.bashrc || echo 'export PATH="/opt/node22/bin:$PATH"' >> /root/.bashrc
mark_done "$MODULE"
