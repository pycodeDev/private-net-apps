#!/bin/bash
set -euo pipefail

# ========== CONFIG ==========
IFACE="${IFACE:-wlan0}"                           # interface wifi/lan kamu
PROXYCHAINS_CONF="/etc/proxychains4.conf"
# OPSIONAL: pilih negara default (kosongkan untuk server terbaik otomatis)
WS_COUNTRY="${WS_COUNTRY:-}"            # contoh: "US" / "DE" / "SG"

# Pastikan root
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

echo "[1] Spoofing MAC on $IFACE..."
ip link set "$IFACE" down
macchanger -r "$IFACE"
ip link set "$IFACE" up

echo "[2] Enable Windscribe firewall (killswitch)..."
# ini akan blok semua trafik non-VPN, dan mengizinkan koneksi ke server Windscribe saja
systemctl enable --now windscribe-helper.service >/dev/null 2>&1 || true
windscribe-cli firewall on

echo "[3] Connecting Windscribe..."
if [[ -n "$WS_COUNTRY" ]]; then
  windscribe-cli connect "$WS_COUNTRY"
else
  windscribe-cli connect
fi

# deteksi interface VPN (WireGuard = wg0, OpenVPN = tun0)
VPN_IF=""
if ip link show wg0 >/dev/null 2>&1; then
  VPN_IF="wg0"
elif ip link show tun0 >/dev/null 2>&1; then
  VPN_IF="tun0"
else
  # fallback: cari dev default route
  VPN_IF="$(ip route | awk '/default/ {print $5; exit}')"
fi
echo "[i] VPN interface detected: ${VPN_IF:-unknown}"

echo "[4] Start Tor service..."
systemctl start tor
sleep 2

echo "[5] Configure proxychains4..."
cat > "$PROXYCHAINS_CONF" <<'EOF'
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 127.0.0.1 9050
EOF

echo "[6] Quick tests"
echo " - Your VPN IP:"
curl -s https://ifconfig.me || true
echo
echo " - Via Tor (proxychains):"
proxychains4 curl -s https://ifconfig.me || true
echo
proxychains4 curl -s https://check.torproject.org/ || true

echo "[✓] Done. All traffic is protected by Windscribe; apps via proxychains4 go through Tor."
echo "Usage examples:"
echo "  - Normal (VPN only):   curl https://example.com"
echo "  - Through Tor:         proxychains4 curl https://example.com"
