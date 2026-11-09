#!/usr/bin/env bash
# Module: dsh — the DeepSeek Harness: its pinned Node runtime, the global CLI,
# the 'web' profile with its bundle list, and the systemd unit that serves the
# Web GUI on the tailnet address.
set -euo pipefail
MODULE=dsh
. "$STACK_ROOT/lib/common.sh"
need_root
load_env
mkdir -p "$STATE_DIR"

DSH_NODE="${DSH_NODE_VERSION:-24.22.2}"
PI_NODE_DIR=/root/.local/share/pi-node
NODE_HOME="$PI_NODE_DIR/node-v$DSH_NODE-linux-x64"

# dsh runs under its own pinned Node, installed beside it and symlinked as
# 'current' — the systemd unit's PATH points at that symlink, so an upgrade is
# a re-point and a restart, not a reinstall.
if [ ! -x "$NODE_HOME/bin/node" ]; then
  log "installing dsh runtime node v$DSH_NODE"
  mkdir -p "$PI_NODE_DIR"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/node.tar.xz" "https://nodejs.org/dist/v$DSH_NODE/node-v$DSH_NODE-linux-x64.tar.xz"
  tar -xf "$tmp/node.tar.xz" -C "$PI_NODE_DIR"
  rm -rf "$tmp"
fi
ln -sfn "$NODE_HOME" "$PI_NODE_DIR/current"
export PATH="$PI_NODE_DIR/current/bin:$PATH"
ok "dsh runtime node $(node --version)"

# corepack provides the pnpm that dsh uses to install profile plugins.
corepack enable >/dev/null 2>&1 || true

WANT="${DSH_VERSION:-0.2.2-rc.1}"
HAVE="$(dsh --version 2>/dev/null || true)"
if [ "$HAVE" != "$WANT" ]; then
  log "npm i -g @deepseek-ai/dsh@$WANT (have: ${HAVE:-none})"
  npm install -g "@deepseek-ai/dsh@$WANT"
fi
ok "dsh $(dsh --version)"

export DSH_HOME=/root/.dsh
PROFILE_DIR="$DSH_HOME/profiles/web"
mkdir -p "$PROFILE_DIR"

# The profile is declarative: package.json names the plugins and the bundle
# order, cordis.patch.yml configures them. Both are tracked in this repo, so a
# rebuilt host gets the same harness, not a default one.
cp "$STACK_ROOT/profiles/web/package.json" "$PROFILE_DIR/package.json"
"$STACK_ROOT/scripts/render-env.mjs" dsh-patch > "$PROFILE_DIR/cordis.patch.yml"
ok "profile manifest + patch written"

# Local plugins are linked by path; clone them first so pnpm can resolve them.
"$STACK_ROOT/scripts/clone-local-plugins.sh"

log "installing profile plugins (pnpm, can take a few minutes)"
( cd "$PROFILE_DIR" && dsh plugin --profile web install ) || die "profile plugin install failed"

BIND="${DSH_BIND_IP:-}"
[ -z "$BIND" ] && [ -f "$STATE_DIR/tailscale-ip" ] && BIND="$(cat "$STATE_DIR/tailscale-ip")"
[ -z "$BIND" ] && BIND=127.0.0.1

systemd_install_unit dsh.service "$(cat <<UNIT
[Unit]
Description=DeepSeek Harness web UI (dsh)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Environment=PATH=$PI_NODE_DIR/current/bin:/usr/local/bin:/usr/bin:/bin
Environment=DSH_HOME=/root/.dsh
WorkingDirectory=/root
ExecStart=$PI_NODE_DIR/current/bin/dsh web --no-open \\
  --host $BIND --port ${DSH_PORT:-3080} \\
  --trusted-host ${TS_FQDN:-localhost} \\
  --trusted-host ${TS_HOSTNAME:-$(hostname)} \\
  --trusted-host localhost
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
)"

systemctl enable --now dsh
systemctl restart dsh
ok "dsh web on http://$BIND:${DSH_PORT:-3080}"
mark_done "$MODULE"
