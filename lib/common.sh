#!/usr/bin/env bash
# Shared helpers for every module. Sourced, never executed.
# shellcheck shell=bash

STACK_ROOT="${STACK_ROOT:?STACK_ROOT must be set by install.sh}"
STATE_DIR="${STATE_DIR:-/var/lib/vps-stack}"

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_red=$'\033[31m'; c_grn=$'\033[32m'; c_ylw=$'\033[33m'

log()  { printf '%s[%s]%s %s\n' "$c_dim" "${MODULE:-stack}" "$c_reset" "$*"; }
ok()   { printf '%s  ok%s  %s\n' "$c_grn" "$c_reset" "$*"; }
warn() { printf '%swarn%s  %s\n' "$c_ylw" "$c_reset" "$*" >&2; }
die()  { printf '%s fail%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

# Idempotence: a module records its own completion marker. --force re-runs it.
done_marker() { printf '%s/%s.done' "$STATE_DIR" "${1:?}"; }
already_done() { [ -z "${FORCE:-}" ] && [ -f "$(done_marker "${1:?}")" ]; }
mark_done() { mkdir -p "$STATE_DIR"; date -Iseconds > "$(done_marker "${1:?}")"; }

have() { command -v "${1:?}" >/dev/null 2>&1; }
need_root() { [ "$(id -u)" = 0 ] || die "run as root"; }

# Fetch a remote installer to a file first, so a truncated download cannot be
# half-executed by the shell.
run_remote_installer() {
  local url="${1:?}" tmp
  tmp="$(mktemp)"
  curl -fsSL --max-time 120 -o "$tmp" "$url" || die "download failed: $url"
  [ -s "$tmp" ] || die "empty installer: $url"
  sh "$tmp" || die "installer failed: $url"
  rm -f "$tmp"
}

# .env is the single source of truth. Load it, exporting every key.
load_env() {
  local f="${1:-$STACK_ROOT/.env}"
  [ -f "$f" ] || die "missing $f — copy .env.example and fill it in"
  set -a
  # shellcheck disable=SC1090
  . "$f"
  set +a
}

# Write a file only when its content changes, so re-runs are quiet and nothing
# restarts for no reason. Returns 0 when it changed.
write_if_changed() {
  local path="${1:?}" content="${2-}"
  if [ -f "$path" ] && [ "$(cat "$path")" = "$content" ]; then return 1; fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  return 0
}

systemd_install_unit() {
  local name="${1:?}" content="${2:?}"
  if write_if_changed "/etc/systemd/system/$name" "$content"; then
    systemctl daemon-reload
    log "unit $name written"
  fi
}
