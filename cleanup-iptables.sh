#!/usr/bin/env bash
set -euo pipefail

: "${ROLE:?ROLE env required (A or B)}"

del() { local t=$1; shift; while iptables -t "$t" -C "$@" &>/dev/null; do iptables -t "$t" -D "$@"; done; }

if [[ "$ROLE" == "A" ]]; then
  : "${A_LISTEN_PORT:?}"; : "${B_IP:?}"; : "${B_PORT:?}"; : "${LAN_IF:?}"; : "${WAN_IF:?}"; : "${ALLOW_SOURCES_CSV:?}"
  IFS=',' read -r -a ALLOW <<< "$ALLOW_SOURCES_CSV"
  for SRC in "${ALLOW[@]}"; do del filter INPUT -i "$LAN_IF" -p tcp -s "$SRC" --dport "$A_LISTEN_PORT" -j ACCEPT; done
  del filter INPUT -i "$LAN_IF" -p tcp --dport "$A_LISTEN_PORT" -j DROP
  del filter FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  del filter FORWARD -o "$WAN_IF" -p tcp -d "$B_IP" --dport "$B_PORT" -j ACCEPT
  del nat PREROUTING -i "$LAN_IF" -p tcp --dport "$A_LISTEN_PORT" -j DNAT --to-destination "$B_IP:$B_PORT"
  del nat POSTROUTING -o "$WAN_IF" -j MASQUERADE
else
  : "${B_LISTEN_PORT:?}"; : "${TARGET_IP:?}"; : "${TARGET_PORT:?}"; : "${PUB_IF:?}"; : "${EGRESS_IF:?}"; : "${ALLOW_FROM_A_CSV:?}"
  IFS=',' read -r -a ALLOW <<< "$ALLOW_FROM_A_CSV"
  for SRC in "${ALLOW[@]}"; do del filter INPUT -i "$PUB_IF" -p tcp -s "$SRC" --dport "$B_LISTEN_PORT" -j ACCEPT; done
  del filter INPUT -i "$PUB_IF" -p tcp --dport "$B_LISTEN_PORT" -j DROP
  del filter FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  del filter FORWARD -o "$EGRESS_IF" -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
  del nat PREROUTING -i "$PUB_IF" -p tcp --dport "$B_LISTEN_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
  del nat POSTROUTING -o "$EGRESS_IF" -j MASQUERADE
fi

echo "iptables rules removed."
