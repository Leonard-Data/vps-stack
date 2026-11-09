#!/usr/bin/env bash
# Module: firstmate — the agent-fleet supervisor: a git checkout of shell tools
# plus agent hook installs. Its bootstrap reports what is still missing rather
# than silently continuing.
set -euo pipefail
MODULE=firstmate
. "$STACK_ROOT/lib/common.sh"
need_root
mkdir -p "$STATE_DIR"

FM_DIR=/root/firstmate
if [ -d "$FM_DIR/.git" ]; then
  log "updating existing checkout"
  git -C "$FM_DIR" pull --ff-only --quiet || warn "pull skipped (local changes)"
else
  git clone --quiet https://github.com/kunchenguid/firstmate "$FM_DIR"
fi

mkdir -p "$FM_DIR/config"
# tmux backend: terminals on this host are driven through tmux.
write_if_changed "$FM_DIR/config/backend" "tmux" || true

export PATH="/opt/node22/bin:/root/.pi/agent/bin:$PATH"
log "fm-bootstrap (reports anything still missing)"
if bash "$FM_DIR/bin/fm-bootstrap.sh" > "$STATE_DIR/firstmate-bootstrap.log" 2>&1; then
  if grep -qiE 'MISSING|OUTDATED|ERROR' "$STATE_DIR/firstmate-bootstrap.log"; then
    warn "firstmate bootstrap reported gaps:"
    grep -iE 'MISSING|OUTDATED|ERROR' "$STATE_DIR/firstmate-bootstrap.log" | head -12 >&2
  else
    ok "firstmate bootstrap clean"
  fi
else
  warn "fm-bootstrap exited non-zero; see $STATE_DIR/firstmate-bootstrap.log"
fi
mark_done "$MODULE"
