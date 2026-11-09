#!/usr/bin/env bash
# The web profile links four local plugins by path. Clone them where the profile
# manifest expects them, so pnpm can resolve the "link:" dependencies.
# Already-present checkouts are fast-forwarded, never clobbered.
set -euo pipefail
MODULE=local-plugins
. "${STACK_ROOT:?}/lib/common.sh"

PLUGIN_DIR=/root/plugins
OWNER="${PLUGIN_OWNER:-Leonard-Data}"

mkdir -p "$PLUGIN_DIR"
for repo in docker-compose-panel hindsight-graph openviking-viewer openviking-server; do
  dest="$PLUGIN_DIR/$repo"
  if [ -d "$dest/.git" ]; then
    git -C "$dest" pull --ff-only --quiet 2>/dev/null || warn "$repo: pull skipped (local changes)"
    ok "$repo present"
  else
    log "cloning $repo"
    git clone --quiet "https://github.com/$OWNER/$repo" "$dest" || warn "$repo clone failed"
  fi
done
