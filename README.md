# smb-portbridge

Bridge SMB (port 445) through networks that block outbound 445 by chaining two Linux hosts:

```
Client → Server A:445  →(tcp/4450)→  Server B:4450  → Target:445
```

- **Server A** (inside network): listens on TCP/445 and forwards to Server B on TCP/4450.
- **Server B** (internet): listens on TCP/4450 and forwards to Target on TCP/445.

This repo lets you set up the above with **either** `iptables` **or** `UFW` (UFW edits include NAT rules in `before.rules`), selected at install time.  
All setups are **tight** (allowlists, interface pinning, conntrack) and **idempotent**.

> ⚠️ SMB/445 is high risk to expose publicly. Use strict allowlists, consider VPN/SSH tunnels when possible.

---

## Best use cases

`smb-portbridge` is designed for scenarios where:

- **Transparent SMB access is required**  
  Clients expect to connect directly to TCP/445 without being reconfigured (e.g., legacy systems, embedded devices, or large networks where client reconfiguration isn’t feasible).

- **ISP or upstream network blocks outbound 445**  
  Many ISPs block SMB for security reasons. This tool allows routing SMB traffic through alternate ports.

- **Control is at the network level**  
  You want to solve the problem with two Linux servers acting as a bridge/proxy, not by touching client configurations.

- **Quick workaround for testing, migration, or special cases**  
  Useful for short-term projects, labs, or controlled internal use where deploying a full VPN might be overkill.

---

## Current limitations & considerations

- **Security risks of SMB exposure**  
  SMB is a high-value attack target. Even with allowlists, exposing it on the internet is dangerous.  
  → Always use strict source IP restrictions, rate limiting, and monitoring.

- **No encryption of SMB traffic**  
  Packets between Server A and Server B are plain TCP (except for NAT). If your network is untrusted, add a secure tunnel (VPN, SSH, stunnel) between A and B.

- **Client IP is not preserved**  
  Because of MASQUERADE, the target only sees Server B’s IP, not the original client’s IP. This simplifies routing but loses end-to-end visibility.  
  Future enhancement could add TPROXY or a userland proxy to preserve client IPs.

- **Maintenance with UFW**  
  UFW-based installs work by editing `before.rules`. Distro updates or manual UFW resets can overwrite these rules. After updates, re-run the installer if rules are lost.

- **Single protocol focus**  
  Currently designed only for TCP/445 (SMB). Extending to other ports is possible but not included yet.

- **No automatic health checks**  
  If Server B or the target goes down, Server A just drops traffic. A future feature could include watchdogs or failover.

---

## Future development ideas

- **WireGuard or SSH tunnel mode**  
  Option to run the A–B hop over an encrypted tunnel automatically.

- **Client IP preservation**  
  Replace MASQUERADE with a proxy method that passes through real client addresses.

- **Multi-port support**  
  Extend configuration for other protocols commonly blocked by ISPs.

- **Improved UFW integration**  
  Safer UFW rule injection with diff/merge logic rather than direct `awk` edits.

- **System health integration**  
  Add systemd watchdog or monitoring scripts to alert if forwarding breaks.

---

## Quick start

On **each server**:

```bash
sudo ./install.sh
```

- Choose **Server A** or **Server B**.
- Choose **iptables** or **UFW**.
- Provide required parameters (IPs, ports, interfaces, allowlists).
- The installer writes `/etc/smb-portbridge.env`, installs the proper script, and enables a systemd unit to apply rules on boot.

To **remove**:

```bash
sudo /usr/local/sbin/smb-portbridge-cleanup
sudo systemctl disable --now smb-portbridge.service
```

---

## Files

- `install.sh` – interactive installer (both servers, iptables/UFW)
- `server-a-iptables.sh`, `server-b-iptables.sh` – iptables setup
- `server-a-ufw.sh`, `server-b-ufw.sh` – UFW setup (edits `before.rules`, uses `ufw route allow`)
- `cleanup-iptables.sh`, `cleanup-ufw.sh` – remove rules cleanly
- `LICENSE` – MIT

---

## Parameters

- **Server A**
  - `A_LISTEN_PORT` (default 445) – port clients hit on A
  - `B_IP`, `B_PORT` (default 4450) – where A forwards to (Server B)
  - `LAN_IF`, `WAN_IF` – inbound/outbound interfaces on A
  - `ALLOW_SOURCES_CSV` – comma-separated allowlist CIDRs for who may hit A:port

- **Server B**
  - `B_LISTEN_PORT` (default 4450) – port A hits on B
  - `TARGET_IP`, `TARGET_PORT` (default 445) – final SMB target
  - `PUB_IF`, `EGRESS_IF` – inbound/outbound interfaces on B
  - `ALLOW_FROM_A_CSV` – comma-separated allowlist CIDRs (Server A IPs)

---

### Persistence & conflicts

- Installer enables `net.ipv4.ip_forward=1` (persisted in `/etc/sysctl.conf`).
- If your distro defaults to `nftables`, these scripts call classic `iptables` (often `iptables-legacy`). For UFW, we edit its rules files directly.
- If you run other firewalls, ensure they don’t override these chains.

---

## Security notes

- Strict allowlists at the listening edge (A:445 from client CIDRs; B:4450 from A only).
- Pin rules to specific interfaces.
- Allow `ESTABLISHED,RELATED` only, and minimal explicit forward rules.
- MASQUERADE on egress to keep return path symmetric.
- Consider rate limits and logging if appropriate.

---

## Troubleshooting

- Check applied rules:
  - `sudo iptables -S && sudo iptables -t nat -S`
  - `sudo ufw status verbose`
  - `sudo iptables-save | sed -n '1,200p'`
- Verify conntrack: `sudo conntrack -L | grep 445`
- Logs: `/var/log/syslog` (UFW/iptables logs if enabled)
