#!/usr/bin/env bash
# Module: pi — the Pi agent (earendil-works). Self-managing install under
# ~/.pi/agent with its own bundled node/fd/rg; firstmate drives it.
set -euo pipefail
MODULE=pi
. "$STACK_ROOT/lib/common.sh"
need_root

if [ -x /root/.pi/agent/bin/pi ]; then
  ok "pi $(/root/.pi/agent/bin/pi --version 2>/dev/null || echo present)"
else
  log "installing pi"
  run_remote_installer https://pi.dev/install.sh
fi

grep -q '/root/.pi/agent/bin' /root/.bashrc || echo 'export PATH="/root/.pi/agent/bin:$PATH"' >> /root/.bashrc

cat <<'NOTE'
  pi is installed but not signed in. Authenticate once, interactively:
      pi            # follow the login prompt
  Credentials land in /root/.pi/agent/auth.json and are never part of this repo.
NOTE
mark_done "$MODULE"
