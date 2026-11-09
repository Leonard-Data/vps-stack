#!/usr/bin/env bash
# One runnable check for the whole host: every module's observable end state.
# Exit 0 = the stack matches what this repo claims to install.
set -uo pipefail
cd "$(dirname "$0")/.."
STACK_ROOT="$PWD"
. lib/common.sh
[ -f .env ] && load_env

fails=0
check() {
  local label="${1:?}" cmd="${2:?}"
  if eval "$cmd" >/dev/null 2>&1; then printf '  ok    %s\n' "$label"
  else printf '  FAIL  %s\n' "$label"; fails=$((fails + 1)); fi
}

echo "runtimes"
check "system node /opt/node22"        "/opt/node22/bin/node --version"
check "dsh runtime node"               "/root/.local/share/pi-node/current/bin/node --version"
check "dsh cli ${DSH_VERSION:-}"        "[ \"\$(/root/.local/share/pi-node/current/bin/dsh --version)\" = \"${DSH_VERSION:-0.2.2-rc.1}\" ]"
check "uv"                             "uv --version"
check "docker compose"                 "docker compose version"

echo "agents"
check "pi"                             "/root/.pi/agent/bin/pi --version"
check "herdr"                          "herdr --version"
check "ovis herdr plugin"              "test -d /root/.config/ovis"
check "firstmate checkout"             "test -d /root/firstmate/.git"

echo "services"
check "tailscaled running"             "systemctl is-active --quiet tailscaled"
check "tailscale joined"               "tailscale status --json | grep -q '\"BackendState\":\"Running\"'"
check "docker running"                 "systemctl is-active --quiet docker"
check "dsh.service running"            "systemctl is-active --quiet dsh"
check "hindsight-daemon active"        "systemctl is-active --quiet hindsight-daemon"
check "hindsight healthcheck timer"    "systemctl is-active --quiet hindsight-healthcheck.timer"

echo "endpoints"
check "dsh web :${DSH_PORT:-3080}"      "curl -fsS -m 5 -o /dev/null http://127.0.0.1:${DSH_PORT:-3080}/"
check "hindsight :${HINDSIGHT_PORT:-9077}/health" "curl -fsS -m 5 -o /dev/null http://127.0.0.1:${HINDSIGHT_PORT:-9077}/health"
check "openviking :${OPENVIKING_PORT:-1933}"      "curl -fsS -m 5 -o /dev/null http://127.0.0.1:${OPENVIKING_PORT:-1933}/"
check "9router :${NINEROUTER_PORT:-32768}"        "curl -fsS -m 5 -o /dev/null http://127.0.0.1:${NINEROUTER_PORT:-32768}/"

echo "containers"
for c in openviking openviking-ollama; do
  check "container $c up" "[ \"\$(docker inspect -f '{{.State.Running}}' $c 2>/dev/null)\" = true ]"
done

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi
exit "$fails"
