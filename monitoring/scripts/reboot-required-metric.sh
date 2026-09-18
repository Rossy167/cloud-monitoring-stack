#!/bin/bash
# Writes whether the host has an update pending that needs a reboot to take
# effect (typically a kernel or libc security update applied by
# unattended-upgrades) to a Prometheus textfile, picked up by node_exporter's
# --collector.textfile.directory. Run via cron every minute, same pattern as
# fail2ban-metrics.sh.
#
# Ubuntu's update-notifier-common package (a dependency of
# unattended-upgrades) touches /var/run/reboot-required whenever an installed
# package needs a reboot. Since Automatic-Reboot is deliberately "false" (see
# monitoring/unattended-upgrades/50unattended-upgrades — this is a
# single-instance host with no redundancy), that reboot never happens on its
# own; this metric plus the NodeRebootRequired alert
# (monitoring/prometheus/rules/alerts.yml) is what tells a human it's needed.
set -euo pipefail

OUT="/var/lib/node_exporter/textfile_collector/reboot_required.prom"
TMP="${OUT}.$$"

if [ -f /var/run/reboot-required ]; then
  VALUE=1
else
  VALUE=0
fi

cat > "$TMP" <<EOF
# HELP node_reboot_required Whether the host has a pending update that requires a reboot (1 = required, per /var/run/reboot-required)
# TYPE node_reboot_required gauge
node_reboot_required ${VALUE}
EOF

mv "$TMP" "$OUT"
