#!/usr/bin/env bash
# Module: herdr + Ovis — the session/terminal server (herdr) and the Ovis Web UI
# that runs as a herdr plugin. The Ovis installer pulls herdr and Bun when they
# are missing, so one call covers all three; it also publishes the UI to the
# tailnet with 'tailscale serve' when Tailscale is up — hence the module order.
set -euo pipefail
MODULE=herdr-ovis
. "$STACK_ROOT/lib/common.sh"
need_root

have herdr && ok "herdr $(herdr --version 2>/dev/null) already present"

log "running the Ovis installer"
run_remote_installer https://ovis.sh/install.sh

ln -sf /root/.local/bin/herdr /usr/local/bin/herdr 2>/dev/null || true
ok "herdr $(herdr --version 2>/dev/null || echo '?') + Ovis plugin installed"
log "Ovis config: /root/.config/ovis — herdr plugin state: /root/.config/herdr"
mark_done "$MODULE"
