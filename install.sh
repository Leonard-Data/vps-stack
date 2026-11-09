#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# vps-stack — one command rebuilds this VPS over an SSH connection.
#
#   curl -fsSL https://raw.githubusercontent.com/Leonard-Data/vps-stack/main/install.sh | bash
#   # or, from a checkout:
#   ./install.sh                      run every module, in order
#   ./install.sh --only dsh,apps      run just these
#   ./install.sh --from 70-dsh        resume at a module (after a failure)
#   ./install.sh --list               show the module graph and stop
#   ./install.sh --dry-run            print what would run
#   ./install.sh --force              re-run modules already marked done
#
# Modules are ordered and idempotent: each records a marker under
# /var/lib/vps-stack and skips itself on a re-run unless --force. A failure
# stops the run, so --from resumes instead of starting over.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STACK_ROOT
export STATE_DIR="${STATE_DIR:-/var/lib/vps-stack}"
REPO_URL="${VPS_STACK_REPO:-https://github.com/Leonard-Data/vps-stack}"

# Piped into bash with no checkout: clone first, then re-exec from disk.
if [ ! -d "$STACK_ROOT/modules" ]; then
  command -v git >/dev/null || { apt-get update -qq && apt-get install -y -qq git; }
  TARGET="${VPS_STACK_DIR:-/opt/vps-stack}"
  [ -d "$TARGET/.git" ] || git clone --quiet "$REPO_URL" "$TARGET"
  exec "$TARGET/install.sh" "$@"
fi

. "$STACK_ROOT/lib/common.sh"

MODULES=(
  00-base        # apt packages, gh, git identity
  10-tailscale   # tailnet membership — the network path to every Web UI
  20-docker      # docker-ce + compose plugin
  30-node        # /opt/node22, global CLIs, uv
  40-pi          # pi agent
  50-herdr-ovis  # herdr session server + Ovis Web UI plugin
  60-firstmate   # agent fleet supervisor
  70-dsh         # DeepSeek Harness: runtime, web profile, systemd unit
  75-hindsight   # per-repo memory daemon + health timer
  80-apps        # traefik, 9router, hermes, openviking (compose)
)

ONLY=""; FROM=""; DRY=""; LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --force) export FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --list) LIST=1; shift ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [ -n "$LIST" ]; then
  printf '%s\n' "${MODULES[@]}"
  exit 0
fi

need_root
mkdir -p "$STATE_DIR"

# .env gates the whole run: every module reads it, and a half-filled one fails
# later and messier than it does here.
[ -f "$STACK_ROOT/.env" ] || die "no .env — cp .env.example .env, fill it in, then re-run"
"$STACK_ROOT/scripts/render-env.mjs" check 2>/dev/null \
  || /opt/node22/bin/node "$STACK_ROOT/scripts/render-env.mjs" check \
  || die ".env is incomplete (see above)"

selected() {
  local m="${1:?}" short="${1#*-}"
  if [ -n "$ONLY" ]; then printf '%s' "$ONLY" | tr ',' '\n' | grep -qxF -e "$m" -e "$short"; return; fi
  return 0
}

started=""; [ -z "$FROM" ] && started=1
failed=""
for m in "${MODULES[@]}"; do
  if [ -z "$started" ]; then
    [ "$m" = "$FROM" ] || [ "${m#*-}" = "$FROM" ] || continue
    started=1
  fi
  selected "$m" || continue

  printf '\n\033[1m── %s ──\033[0m\n' "$m"
  if [ -n "$DRY" ]; then echo "  (dry run) $STACK_ROOT/modules/$m.sh"; continue; fi

  if ! bash "$STACK_ROOT/modules/$m.sh"; then
    failed="$m"
    break
  fi
done

[ -n "$DRY" ] && exit 0

if [ -n "$failed" ]; then
  printf '\n\033[31mmodule %s failed.\033[0m Fix the cause, then resume:\n  %s --from %s\n' \
    "$failed" "$0" "$failed" >&2
  exit 1
fi

printf '\n\033[1mverifying\033[0m\n'
"$STACK_ROOT/scripts/doctor.sh" || warn "doctor reported failures — see above"

cat <<EOF

Done. What is left is interactive and cannot be scripted:

  1. pi         : run \`pi\` once and sign in
  2. gh         : \`gh auth login -s project,workflow\`
  3. 9router    : open https://${NINEROUTER_PROJECT:-9router-nxkt}.${TRAEFIK_HOST:-your-domain},
                  sign in with INITIAL_PASSWORD, mint an API key, put it in .env
                  as NINEROUTER_API_KEY, then: ./install.sh --only apps --force
  4. OpenViking : the dsh memory plugin needs a user key — see docs/MANUAL.md §9

  Web GUI: http://$( [ -f "$STATE_DIR/tailscale-ip" ] && cat "$STATE_DIR/tailscale-ip" || echo 127.0.0.1):${DSH_PORT:-3080}
EOF
