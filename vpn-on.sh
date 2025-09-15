#!/bin/bash
set -euo pipefail

# ========== CONFIG ==========
IFACE="${IFACE:-wlan0}" # interface wifi/lan kamu
PRIVNET_LEVEL="${PRIVNET_LEVEL:-basic}"
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

start_tor_basic() {
  # Tor standar (tanpa bridges)
  systemctl enable --now tor 2>/dev/null || systemctl enable --now tor@default 2>/dev/null || {
    tor -f /etc/tor/torrc & disown
  }
}

start_tor_level1() {
  # Stealth: Tor via obfs4 bridges
  mkdir -p /etc/tor/torrc.d
  BRCONF="/etc/tor/torrc.d/private-net.conf"
  BRLIST="/etc/tor/bridges.txt"

  if [[ ! -s "$BRLIST" ]]; then
    cat > "$BRLIST" <<'EOT'
# Isi dengan bridge lines obfs4 dari https://bridges.torproject.org/
# Contoh:
# Bridge obfs4 1.2.3.4:9001 0123456789ABCDEF... cert=XXXX iat-mode=0
EOT
    echo "[!] No bridges at $BRLIST."
    echo "    Get obfs4 bridges from https://bridges.torproject.org/ then add to that file."
    echo "    Falling back to basic Tor for now."
    start_tor_basic
    return
  fi

  cat > "$BRCONF" <<EOF
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
# load all user bridges
%include $BRLIST
SocksPort 9050
EOF

  systemctl enable --now tor 2>/dev/null || systemctl enable --now tor@default 2>/dev/null || {
    tor -f /etc/tor/torrc & disown
  }
}

case "$PRIVNET_LEVEL" in
  basic)  echo "[i] Tor mode: basic";  start_tor_basic ;;
  1)      echo "[i] Tor mode: stealth (obfs4 bridges)"; start_tor_level1 ;;
  *)      echo "[!] Unknown level '$PRIVNET_LEVEL' → using basic"; start_tor_basic ;;
esac

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