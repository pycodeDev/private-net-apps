#!/bin/bash
set -euo pipefail

echo "[1] Disconnecting Windscribe..."
sudo windscribe-cli disconnect || true

echo "[2] Disabling Windscribe firewall..."
sudo windscribe-cli firewall off || true

echo "[3] Stopping Tor service..."
# stop Tor
systemctl stop tor 2>/dev/null || systemctl stop tor@default 2>/dev/null || pkill -x tor || true

# optional: hapus konfigurasi stealth (biarkan bridges.txt tetap)
rm -f /etc/tor/torrc.d/private-net.conf

echo "[✓] Normal network restored (direct ISP)."