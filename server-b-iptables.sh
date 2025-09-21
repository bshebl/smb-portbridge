#!/usr/bin/env bash
set -euo pipefail

: "${B_LISTEN_PORT:?missing}"; : "${TARGET_IP:?missing}"; : "${TARGET_PORT:?missing}"
: "${PUB_IF:?missing}"; : "${EGRESS_IF:?missing}"; : "${ALLOW_FROM_A_CSV:?missing}"

IFS=',' read -r -a ALLOW_FROM_A <<< "$ALLOW_FROM_A_CSV"
add() { local t=$1; shift; iptables -t "$t" -C "$@" &>/dev/null || iptables -t "$t" -A "$@"; }

for SRC in "${ALLOW_FROM_A[@]}"; do
  add filter INPUT -i "$PUB_IF" -p tcp -s "$SRC" --dport "$B_LISTEN_PORT" -j ACCEPT
done
add filter INPUT -i "$PUB_IF" -p tcp --dport "$B_LISTEN_PORT" -j DROP

add filter FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
add filter FORWARD -o "$EGRESS_IF" -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT

add nat PREROUTING -i "$PUB_IF" -p tcp --dport "$B_LISTEN_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
add nat POSTROUTING -o "$EGRESS_IF" -j MASQUERADE
