#!/usr/bin/env bash
set -euo pipefail

needs() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }

echo "=== smb-portbridge installer ==="

read -rp "Install on (a) Server A or (b) Server B? [a/b]: " ROLE
ROLE=${ROLE,,}
[[ "$ROLE" == "a" || "$ROLE" == "b" ]] || { echo "Choose 'a' or 'b'"; exit 1; }

read -rp "Use (i) iptables or (u) UFW? [i/u]: " BACKEND
BACKEND=${BACKEND,,}
[[ "$BACKEND" == "i" || "$BACKEND" == "u" ]] || { echo "Choose 'i' or 'u'"; exit 1; }

if [[ "$ROLE" == "a" ]]; then
  read -rp "A_LISTEN_PORT [445]: " A_LISTEN_PORT; A_LISTEN_PORT=${A_LISTEN_PORT:-445}
  read -rp "B_IP (Server B public IP): " B_IP
  read -rp "B_PORT [4450]: " B_PORT; B_PORT=${B_PORT:-4450}
  read -rp "LAN_IF (incoming from clients) [eth0]: " LAN_IF; LAN_IF=${LAN_IF:-eth0}
  read -rp "WAN_IF (outgoing to internet) [eth1]: " WAN_IF; WAN_IF=${WAN_IF:-eth1}
  read -rp "ALLOW_SOURCES_CSV (client CIDRs) [1.2.3.4/32]: " ALLOW_SOURCES_CSV; ALLOW_SOURCES_CSV=${ALLOW_SOURCES_CSV:-1.2.3.4/32}
else
  read -rp "B_LISTEN_PORT [4450]: " B_LISTEN_PORT; B_LISTEN_PORT=${B_LISTEN_PORT:-4450}
  read -rp "TARGET_IP (final SMB server): " TARGET_IP
  read -rp "TARGET_PORT [445]: " TARGET_PORT; TARGET_PORT=${TARGET_PORT:-445}
  read -rp "PUB_IF (incoming from A) [eth0]: " PUB_IF; PUB_IF=${PUB_IF:-eth0}
  read -rp "EGRESS_IF (out to target) [eth0]: " EGRESS_IF; EGRESS_IF=${EGRESS_IF:-eth0}
  read -rp "ALLOW_FROM_A_CSV (Server A IP/CIDR) [5.6.7.8/32]: " ALLOW_FROM_A_CSV; ALLOW_FROM_A_CSV=${ALLOW_FROM_A_CSV:-5.6.7.8/32}
fi

if [[ "$BACKEND" == "i" ]]; then
  needs iptables
else
  needs ufw
  needs iptables
fi

sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null; then
  echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf >/dev/null
fi

sudo install -d -m 0755 /usr/local/sbin

ENV_FILE=/etc/smb-portbridge.env
if [[ "$ROLE" == "a" ]]; then
  sudo bash -c "cat > $ENV_FILE" <<EOF
ROLE=A
A_LISTEN_PORT=$A_LISTEN_PORT
B_IP=$B_IP
B_PORT=$B_PORT
LAN_IF=$LAN_IF
WAN_IF=$WAN_IF
ALLOW_SOURCES_CSV=$ALLOW_SOURCES_CSV
EOF
else
  sudo bash -c "cat > $ENV_FILE" <<EOF
ROLE=B
B_LISTEN_PORT=$B_LISTEN_PORT
TARGET_IP=$TARGET_IP
TARGET_PORT=$TARGET_PORT
PUB_IF=$PUB_IF
EGRESS_IF=$EGRESS_IF
ALLOW_FROM_A_CSV=$ALLOW_FROM_A_CSV
EOF
fi
sudo chmod 0644 "$ENV_FILE"
echo "Wrote $ENV_FILE"

if [[ "$BACKEND" == "i" && "$ROLE" == "a" ]]; then
  SRC=server-a-iptables.sh
elif [[ "$BACKEND" == "i" && "$ROLE" == "b" ]]; then
  SRC=server-b-iptables.sh
elif [[ "$BACKEND" == "u" && "$ROLE" == "a" ]]; then
  SRC=server-a-ufw.sh
else
  SRC=server-b-ufw.sh
fi

sudo install -m 0755 "$SRC" /usr/local/sbin/smb-portbridge-apply

if [[ "$BACKEND" == "i" ]]; then
  sudo install -m 0755 cleanup-iptables.sh /usr/local/sbin/smb-portbridge-cleanup
else
  sudo install -m 0755 cleanup-ufw.sh /usr/local/sbin/smb-portbridge-cleanup
fi

UNIT=/etc/systemd/system/smb-portbridge.service
sudo bash -c "cat > $UNIT" <<'EOF'
[Unit]
Description=SMB Port Bridge (NAT forwarder)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/smb-portbridge.env
ExecStart=/usr/local/sbin/smb-portbridge-apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now smb-portbridge.service

echo "Installed. Current status:"
sudo systemctl status --no-pager smb-portbridge.service || true
