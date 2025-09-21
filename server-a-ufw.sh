#!/usr/bin/env bash
set -euo pipefail

: "${A_LISTEN_PORT:?missing}"; : "${B_IP:?missing}"; : "${B_PORT:?missing}"
: "${LAN_IF:?missing}"; : "${WAN_IF:?missing}"; : "${ALLOW_SOURCES_CSV:?missing}"

BACKUP=/etc/ufw/before.rules.smbportbridge.bak
BEFORE=/etc/ufw/before.rules
DEFAULTS=/etc/default/ufw

if [[ ! -f "$BACKUP" ]]; then sudo cp -a "$BEFORE" "$BACKUP"; fi

sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$DEFAULTS"

MARK="# SMB_PORTBRIDGE_A"
if ! grep -q "$MARK" "$BEFORE"; then
  sudo awk -v lan="$LAN_IF" -v wan="$WAN_IF" -v lport="$A_LISTEN_PORT" -v bip="$B_IP" -v bport="$B_PORT" -v mark="$MARK" '
    BEGIN{printed=0}
    {print}
    END{
      print "";
      print mark" BEGIN";
      print "*nat";
      print ":PREROUTING ACCEPT [0:0]";
      print ":POSTROUTING ACCEPT [0:0]";
      printf("-A PREROUTING -i %s -p tcp --dport %s -j DNAT --to-destination %s:%s\n", lan, lport, bip, bport);
      printf("-A POSTROUTING -o %s -j MASQUERADE\n", wan);
      print "COMMIT";
      print mark" END";
    }
  ' "$BEFORE" | sudo tee "$BEFORE" >/dev/null
fi

IFS=',' read -r -a ALLOW <<< "$ALLOW_SOURCES_CSV"
for SRC in "${ALLOW[@]}"; do
  sudo ufw allow in on "$LAN_IF" proto tcp from "$SRC" to any port "$A_LISTEN_PORT"
done
sudo ufw deny in on "$LAN_IF" proto tcp to any port "$A_LISTEN_PORT"

sudo ufw route allow proto tcp from any to "$B_IP" port "$B_PORT"

sudo ufw --force reload
sudo ufw status verbose
