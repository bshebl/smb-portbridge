#!/usr/bin/env bash
set -euo pipefail

: "${ROLE:?ROLE env required (A or B)}"

BEFORE=/etc/ufw/before.rules
DEFAULTS=/etc/default/ufw

if [[ "$ROLE" == "A" ]]; then
  : "${A_LISTEN_PORT:?}"; : "${LAN_IF:?}"; : "${ALLOW_SOURCES_CSV:?}"
  : "${B_IP:?}"; : "${B_PORT:?}"
  IFS=',' read -r -a ALLOW <<< "$ALLOW_SOURCES_CSV"
  for SRC in "${ALLOW[@]}"; do sudo ufw delete allow in on "$LAN_IF" proto tcp from "$SRC" to any port "$A_LISTEN_PORT" || true; done
  sudo ufw delete deny in on "$LAN_IF" proto tcp to any port "$A_LISTEN_PORT" || true
  sudo ufw delete route allow proto tcp from any to "$B_IP" port "$B_PORT" || true
  sudo sed -i '/# SMB_PORTBRIDGE_A BEGIN/,/# SMB_PORTBRIDGE_A END/d' "$BEFORE"
else
  : "${B_LISTEN_PORT:?}"; : "${PUB_IF:?}"; : "${ALLOW_FROM_A_CSV:?}"
  : "${TARGET_IP:?}"; : "${TARGET_PORT:?}"
  IFS=',' read -r -a ALLOW <<< "$ALLOW_FROM_A_CSV"
  for SRC in "${ALLOW[@]}"; do sudo ufw delete allow in on "$PUB_IF" proto tcp from "$SRC" to any port "$B_LISTEN_PORT" || true; done
  sudo ufw delete deny in on "$PUB_IF" proto tcp to any port "$B_LISTEN_PORT" || true
  sudo ufw delete route allow proto tcp from any to "$TARGET_IP" port "$TARGET_PORT" || true
  sudo sed -i '/# SMB_PORTBRIDGE_B BEGIN/,/# SMB_PORTBRIDGE_B END/d' "$BEFORE"
fi

sudo ufw --force reload
echo "UFW rules removed."
