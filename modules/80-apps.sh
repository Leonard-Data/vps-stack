#!/usr/bin/env bash
# Module: apps — the composed applications, in dependency order:
#   traefik    the only process on :80/:443; terminates TLS for the others
#   9router    LLM proxy; dsh, OpenViking extraction and the agents all call it
#   hermes     the VPS provider's management agent
#   openviking cross-project memory server + its local embedding model
#
# Compose files live in this repo under apps/ and are copied to the layout the
# host actually uses: /docker/<project>/ for the provider-facing apps (the
# compose project name is the Traefik subdomain, so the directory name matters),
# and the openviking-server plugin repo for OpenViking, which owns its own file.
set -euo pipefail
MODULE=apps
. "$STACK_ROOT/lib/common.sh"
need_root
load_env
have docker || die "docker missing — run module 20-docker first"

OV_DIR="${OPENVIKING_DIR:-/root/plugins/openviking-server}"

deploy() {
  local src="${1:?}" dir="${2:?}"
  mkdir -p "$dir"
  write_if_changed "$dir/docker-compose.yml" "$(cat "$STACK_ROOT/$src")" \
    && log "$dir/docker-compose.yml updated"
}

deploy apps/traefik/docker-compose.yml "/docker/${TRAEFIK_PROJECT}"
deploy apps/9router/docker-compose.yml "/docker/${NINEROUTER_PROJECT}"
deploy apps/hermes/docker-compose.yml  "/docker/${HERMES_PROJECT}"
# OpenViking's compose file belongs to its own repo; only fill the gap if the
# checkout is missing, so we never fight that repo over its own deliverable.
[ -f "$OV_DIR/docker-compose.yml" ] || deploy apps/openviking/docker-compose.yml "$OV_DIR"

# Per-app env files and ov.conf are rendered from the single root .env, never
# hand-edited. This also re-renders after an .env change, which is why
# '--only apps --force' is the way to roll a rotated secret.
"$STACK_ROOT/scripts/render-env.mjs" apps

up() {
  local name="${1:?}" dir="${2:?}"
  [ -f "$dir/docker-compose.yml" ] || die "$dir/docker-compose.yml missing"
  log "compose up: $name"
  ( cd "$dir" && docker compose up -d --remove-orphans )
  ok "$name running"
}

ONLY_APPS="${APPS_ONLY:-}"
want() { [ -z "$ONLY_APPS" ] || printf '%s' "$ONLY_APPS" | tr ',' '\n' | grep -qx "${1:?}"; }

# Traefik first: it owns :80/:443 and the ACME challenge, so a later app's
# labels have somewhere to register.
want traefik    && up "${TRAEFIK_PROJECT}"    "/docker/${TRAEFIK_PROJECT}"
want 9router    && up "${NINEROUTER_PROJECT}" "/docker/${NINEROUTER_PROJECT}"
want hermes     && up "${HERMES_PROJECT}"     "/docker/${HERMES_PROJECT}"
want openviking && up openviking              "$OV_DIR"

# The embedding model is pulled on first use and the first request would
# otherwise time out; pull it here, once.
if want openviking; then
  log "pulling the embedding model (first run only)"
  docker exec openviking-ollama ollama pull "${OPENVIKING_EMBED_MODEL}" >/dev/null 2>&1 \
    || warn "ollama pull failed — retry: docker exec openviking-ollama ollama pull ${OPENVIKING_EMBED_MODEL}"
fi

docker compose ls
mark_done "$MODULE"
