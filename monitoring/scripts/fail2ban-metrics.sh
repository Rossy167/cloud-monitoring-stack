#!/bin/bash
# Writes fail2ban's sshd jail stats to a Prometheus textfile, picked up by
# node_exporter's --collector.textfile.directory. Run via cron every minute.
set -euo pipefail

OUT="/var/lib/node_exporter/textfile_collector/fail2ban.prom"
TMP="${OUT}.$$"

STATUS="$(fail2ban-client status sshd 2>/dev/null || true)"

CURRENT="$(echo "$STATUS" | grep -i 'Currently banned' | awk -F':' '{print $2}' | tr -d ' ' || true)"
TOTAL="$(echo "$STATUS" | grep -i 'Total banned' | awk -F':' '{print $2}' | tr -d ' ' || true)"

CURRENT="${CURRENT:-0}"
TOTAL="${TOTAL:-0}"

cat > "$TMP" <<EOF
# HELP fail2ban_banned_current Currently banned IPs in the sshd jail
# TYPE fail2ban_banned_current gauge
fail2ban_banned_current ${CURRENT}
# HELP fail2ban_banned_total Total IPs banned since fail2ban started
# TYPE fail2ban_banned_total counter
fail2ban_banned_total ${TOTAL}
EOF

mv "$TMP" "$OUT"
