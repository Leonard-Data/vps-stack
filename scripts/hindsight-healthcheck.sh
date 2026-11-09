#!/bin/bash
# Restart the local Hindsight daemon when it stops answering health checks.
# Two consecutive failures (~4 minutes) are required, so a slow cold start or a
# brief blip does not trigger a restart.
set -u

URL="http://127.0.0.1:9077/health"
STATE=/run/hindsight-healthcheck.fails

log() { logger -t hindsight-healthcheck "$*" 2>/dev/null || echo "$*"; }

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true)
if [ "$code" = "200" ]; then
  [ -f "$STATE" ] && rm -f "$STATE"
  exit 0
fi

fails=$(cat "$STATE" 2>/dev/null || echo 0)
fails=$((fails + 1))
echo "$fails" > "$STATE"
log "unhealthy (http=${code:-timeout}), consecutive failure $fails/2"
[ "$fails" -lt 2 ] && exit 0

log "restarting hindsight-daemon.service"
systemctl restart hindsight-daemon.service || log "restart failed"

for _ in $(seq 1 12); do
  sleep 5
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true)
  if [ "$code" = "200" ]; then
    log "recovered after restart"
    rm -f "$STATE"
    exit 0
  fi
done

log "still unhealthy after restart (http=${code:-timeout}); leaving count at $fails"
exit 1
