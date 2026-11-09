#!/usr/bin/env bash
# Module: hindsight — the per-repo code-memory daemon. It runs as an
# unprivileged user, not root: it indexes repositories and talks to an LLM, so
# it gets no more access than it needs. A 2-minute timer restarts it after two
# consecutive failed health checks (one blip must not bounce it).
set -euo pipefail
MODULE=hindsight
. "$STACK_ROOT/lib/common.sh"
need_root
load_env

HS_USER="${HINDSIGHT_USER:-hindsight}"
HS_PORT="${HINDSIGHT_PORT:-9077}"
HS_PROFILE="${HINDSIGHT_PROFILE:-coding-agent}"

id "$HS_USER" >/dev/null 2>&1 || {
  log "creating unprivileged user $HS_USER"
  useradd --create-home --shell /usr/sbin/nologin "$HS_USER"
}

have uv || die "uv missing — run module 30-node first"

# Client-side config for the agent plugin: which port, and that the daemon is
# managed by systemd rather than spawned per session.
mkdir -p /root/.hindsight
write_if_changed /root/.hindsight/coding-agent.json "$(cat <<JSON
{
  "serverMode": "daemon",
  "apiPort": $HS_PORT,
  "daemonProfile": "$HS_PROFILE"
}
JSON
)" || true

install -m 0755 "$STACK_ROOT/scripts/hindsight-healthcheck.sh" /usr/local/bin/hindsight-healthcheck.sh
sed -i "s|^URL=.*|URL=\"http://127.0.0.1:$HS_PORT/health\"|" /usr/local/bin/hindsight-healthcheck.sh

systemd_install_unit hindsight-daemon.service "$(cat <<UNIT
[Unit]
Description=Hindsight local memory daemon (embedded, unprivileged user)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$HS_USER
Group=$HS_USER
Environment=HOME=/home/$HS_USER
Environment=PATH=/usr/local/bin:/usr/bin:/bin
WorkingDirectory=/home/$HS_USER
ExecStart=/usr/local/bin/uvx hindsight-embed@latest -p $HS_PROFILE daemon start
ExecStop=/usr/local/bin/uvx hindsight-embed@latest -p $HS_PROFILE daemon stop
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
UNIT
)"

systemd_install_unit hindsight-healthcheck.service "$(cat <<'UNIT'
[Unit]
Description=Hindsight daemon health check and auto-restart
After=hindsight-daemon.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hindsight-healthcheck.sh
UNIT
)"

systemd_install_unit hindsight-healthcheck.timer "$(cat <<'UNIT'
[Unit]
Description=Run the Hindsight daemon health check every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=15s

[Install]
WantedBy=timers.target
UNIT
)"

systemctl enable --now hindsight-daemon.service
systemctl enable --now hindsight-healthcheck.timer

for _ in $(seq 1 24); do
  [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$HS_PORT/health" || true)" = 200 ] && break
  sleep 5
done
ok "hindsight health: $(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$HS_PORT/health" || echo timeout)"
mark_done "$MODULE"
