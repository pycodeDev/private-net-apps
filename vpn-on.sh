#!/bin/bash
set -euo pipefail

# ========== CONFIG ==========
IFACE="${IFACE:-wlan0}" # interface wifi/lan kamu
PRIVNET_LEVEL="${PRIVNET_LEVEL:-0}"
PROXYCHAINS_CONF="/etc/proxychains4.conf"

# OPSIONAL: pilih negara default (kosongkan untuk server terbaik otomatis)
WS_COUNTRY="${WS_COUNTRY:-}"            # contoh: "US" / "DE" / "SG"

# Pastikan root
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

echo "[1] Spoofing MAC on $IFACE..."
ip link set "$IFACE" down
macchanger -r "$IFACE"
ip link set "$IFACE" up

echo "[2] Aktifkan Windscribe firewall (killswitch)..."
# ini akan blok semua trafik non-VPN, dan mengizinkan koneksi ke server Windscribe saja
systemctl enable --now windscribe-helper.service >/dev/null 2>&1 || true
windscribe-cli firewall on

echo "[3] Koneksi Windscribe..."
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

fetch_obfs4_bridges() {
  local tmp="$(mktemp)"
  # coba beberapa varian query
  local urls=(
    "https://bridges.torproject.org/bridges?transport=obfs4"
    "https://bridges.torproject.org/bridges?transport=obfs4&ipv6=false"
    "https://bridges.torproject.org/bridges?transport=obfs4&country=ID"
  )

  local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari"
  : > "$tmp"
  local u
  for u in "${urls[@]}"; do
    curl -fsSL --max-time 15 -A "$ua" "$u" 2>/dev/null | \
      sed -n 's/^[[:space:]]*//; /^Bridge obfs4 /p' >> "$tmp" || true
    # stop kalau sudah dapat minimal 2 baris
    if [ "$(grep -c '^Bridge obfs4 ' "$tmp" || true)" -ge 2 ]; then
      break
    fi
    sleep 1
  done

  # tulis unik maksimal 5 baris
  if grep -q '^Bridge obfs4 ' "$tmp"; then
    sort -u "$tmp" | head -n 5 > "$BRLIST"
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

enable_snowflake_fallback() {
  # butuh paket snowflake-client (Debian/Kali)
  ensure_pkg snowflake-client
  cat > "$BRCONF" <<'EOF'
UseBridges 1
ClientTransportPlugin snowflake exec /usr/bin/snowflake-client -url https://snowflake.torproject.org/ -broker https://snowflake-broker.torproject.net/ -front cdn.sstatic.net -ice stun:stun.stunprotocol.org:3478
# SocksPort default 9050
EOF
  echo "[i] Snowflake fallback enabled."
}

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

  # kalau belum ada bridges.txt atau kosong, coba ambil otomatis
  if [ ! -s "$BRLIST" ]; then
    echo "[i] Mencoba mendapatkan obfs4 bridges dari BridgeDB..."
    if ! fetch_obfs4_bridges; then
      echo "[!] Tidak bisa mendapatkan obfs4 bridges [CAPTCHA Protected]."
      echo "    Silahkan Isi Manual Bridges Dari https://bridges.torproject.org/ dan simpan di $BRLIST."
      if [ "${AUTO_SNOWFLAKE:-0}" = "1" ]; then
        enable_snowflake_fallback
        systemctl restart tor 2>/dev/null || tor -f /etc/tor/torrc & disown
        return
      else
        echo "[i] Dialihkan ke mode basic."
        echo "    Silahkan Isi Manual Bridges Dari https://bridges.torproject.org/ dan simpan di $BRLIST."
        start_tor_basic
        return
      fi
    fi
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
  0)  echo "[i] Tor mode: basic";  start_tor_basic ;;
  1)      echo "[i] Tor mode: stealth (obfs4 bridges)"; start_tor_level1 ;;
  *)      echo "[!] Level Tidak Diketahui '$PRIVNET_LEVEL' → Gunakan basic"; start_tor_basic ;;
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
echo " - VPN IP:"
curl -s https://ifconfig.me || true
echo
echo " - Via Tor (proxychains):"
proxychains4 curl -s https://ifconfig.me || true
echo
proxychains4 curl -s https://check.torproject.org/ || true

echo "[✓] Selesai. Semua trafik dilindungi oleh Windscribe; aplikasi melalui proxychains4 melalui Tor."
echo "Contoh Penggunan:"
echo "  - Normal (VPN only):   curl https://example.com"
echo "  - Through Tor:         proxychains4 curl https://example.com"