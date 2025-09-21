#!/usr/bin/env bash
set -euo pipefail

: "${B_LISTEN_PORT:?missing}"; : "${TARGET_IP:?missing}"; : "${TARGET_PORT:?missing}"
: "${PUB_IF:?missing}"; : "${EGRESS_IF:?missing}"; : "${ALLOW_FROM_A_CSV:?missing}"

BACKUP=/etc/ufw/before.rules.smbportbridge.bak
BEFORE=/etc/ufw/before.rules
DEFAULTS=/etc/default/ufw

if [[ ! -f "$BACKUP" ]]; then sudo cp -a "$BEFORE" "$BACKUP"; fi
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$DEFAULTS"

MARK="# SMB_PORTBRIDGE_B"
if ! grep -q "$MARK" "$BEFORE"; then
  sudo awk -v pub="$PUB_IF" -v egr="$EGRESS_IF" -v blp="$B_LISTEN_PORT" -v tip="$TARGET_IP" -v tport="$TARGET_PORT" -v mark="$MARK" '
    BEGIN{printed=0}
    {print}
    END{
      print "";
      print mark" BEGIN";
      print "*nat";
      print ":PREROUTING ACCEPT [0:0]";
      print ":POSTROUTING ACCEPT [0:0]";
      printf("-A PREROUTING -i %s -p tcp --dport %s -j DNAT --to-destination %s:%s\n", pub, blp, tip, tport);
      printf("-A POSTROUTING -o %s -j MASQUERADE\n", egr);
      print "COMMIT";
      print mark" END";
    }
  ' "$BEFORE" | sudo tee "$BEFORE" >/dev/null
fi

IFS=',' read -r -a ALLOW <<< "$ALLOW_FROM_A_CSV"
for SRC in "${ALLOW[@]}"; do
  sudo ufw allow in on "$PUB_IF" proto tcp from "$SRC" to any port "$B_LISTEN_PORT"
done
sudo ufw deny in on "$PUB_IF" proto tcp to any port "$B_LISTEN_PORT"

sudo ufw route allow proto tcp from any to "$TARGET_IP" port "$TARGET_PORT"

sudo ufw --force reload
sudo ufw status verbose
