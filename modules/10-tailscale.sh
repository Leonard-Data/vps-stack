#!/usr/bin/env bash
# Module: tailscale — the only network path to the Web UIs. dsh binds to the
# tailnet IP, so this must come up before dsh.
set -euo pipefail
MODULE=tailscale
. "$STACK_ROOT/lib/common.sh"
need_root
load_env

if ! have tailscale; then
  log "installing tailscale"
  run_remote_installer https://tailscale.com/install.sh
fi

systemctl enable --now tailscaled

if tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
  ok "already joined: $(tailscale ip -4 | head -1)"
else
  [ -n "${TS_AUTHKEY:-}" ] || die "TS_AUTHKEY is empty in .env — mint a reusable key, or run 'tailscale up' by hand"
  tailscale up --authkey "$TS_AUTHKEY" --hostname "${TS_HOSTNAME:-$(hostname)}" --ssh
  ok "joined as $(tailscale ip -4 | head -1)"
fi

# Record the address we actually got, so the dsh module binds the real IP even
# if .env guessed wrong.
mkdir -p "$STATE_DIR"
tailscale ip -4 | head -1 > "$STATE_DIR/tailscale-ip"
mark_done "$MODULE"
