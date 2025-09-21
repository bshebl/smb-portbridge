#!/usr/bin/env bash
set -euo pipefail

: "${A_LISTEN_PORT:?missing}"; : "${B_IP:?missing}"; : "${B_PORT:?missing}"
: "${LAN_IF:?missing}"; : "${WAN_IF:?missing}"; : "${ALLOW_SOURCES_CSV:?missing}"

IFS=',' read -r -a ALLOW_SOURCES <<< "$ALLOW_SOURCES_CSV"
add() { local t=$1; shift; iptables -t "$t" -C "$@" &>/dev/null || iptables -t "$t" -A "$@"; }

for SRC in "${ALLOW_SOURCES[@]}"; do
  add filter INPUT -i "$LAN_IF" -p tcp -s "$SRC" --dport "$A_LISTEN_PORT" -j ACCEPT
done
add filter INPUT -i "$LAN_IF" -p tcp --dport "$A_LISTEN_PORT" -j DROP

add filter FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
add filter FORWARD -o "$WAN_IF" -p tcp -d "$B_IP" --dport "$B_PORT" -j ACCEPT

add nat PREROUTING -i "$LAN_IF" -p tcp --dport "$A_LISTEN_PORT" -j DNAT --to-destination "$B_IP:$B_PORT"
add nat POSTROUTING -o "$WAN_IF" -j MASQUERADE
