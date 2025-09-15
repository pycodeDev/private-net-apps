#!/bin/bash
set -euo pipefail

# --- CONFIG (opsional) ---
ONLY_FREE="${ONLY_FREE:-1}"     # 1 = pilih lokasi FREE saja, 0 = semua
COUNTRY_ALLOW="${COUNTRY_ALLOW:-}"  # contoh: "US,DE,SG" (whitelist negara, kosong = semua)
INTERVAL="${INTERVAL:-600}"     # jeda rotasi (detik) untuk mode --rotate
TRIES="${TRIES:-30}"            # percobaan baca lokasi (jaga-jaga CLI lambat)

# --- HELP ---
usage() {
  cat <<EOF
Usage:
  sudo ./vpn_shuffle.sh once            # connect sekali ke server acak
  sudo ./vpn_shuffle.sh rotate          # rotate (ganti server) tiap \$INTERVAL detik

Env vars (opsional):
  ONLY_FREE=1           pilih lokasi FREE saja (default 1)
  COUNTRY_ALLOW="US,DE" whitelist negara (kode 2 huruf), kosong = semua
  INTERVAL=600          jeda rotasi untuk mode rotate (detik)

Contoh:
  sudo ONLY_FREE=1 ./vpn_shuffle.sh once
  sudo COUNTRY_ALLOW="SG,JP" INTERVAL=900 ./vpn_shuffle.sh rotate
EOF
}

[[ $# -lt 1 ]] && { usage; exit 1; }
MODE="$1"

# --- Prasyarat ---
command -v windscribe-cli >/dev/null || { echo "windscribe-cli tidak ditemukan."; exit 1; }
systemctl enable --now windscribe-helper.service >/dev/null 2>&1 || true
windscribe-cli firewall on >/dev/null || true

# --- Fungsi: ambil daftar lokasi, filter, acak satu ---
pick_random_location() {
  # Ambil lokasi (kadang butuh retry karena CLI ngambil daftar dari API)
  local out="" i
  for ((i=1;i<=TRIES;i++)); do
    if out="$(sudo windscribe-cli locations 2>/dev/null)"; then
      [[ -n "$out" ]] && break
    fi
    sleep 1
  done

  # Normalisasi: ambil baris yang mengandung kode negara + nama lokasi
  # Contoh output umum: "US  New York  [FREE]" atau "DE  Frankfurt"
  # Kita bentuk list: "US New York [FREE]" → lalu filter
  echo "$out" | awk 'NF>0' | \
  awk '
    BEGIN{OFS=" "}
    {
      line=$0
      # buang garis, header dsb
      if (line ~ /Locations|----|Country|City/){next}
      gsub(/\t+/," ",line)
      sub(/^[[:space:]]+/,"",line)
      if (length(line)>0) print line
    }' | \
  awk -v only_free="$ONLY_FREE" -v allow="$COUNTRY_ALLOW" '
    BEGIN{
      split(allow, A, /,/)
      for (i in A){ if (A[i]!="") WL[A[i]]=1 }
    }
    {
      # Ambil token pertama sebagai country code (2 huruf)
      cc=$1
      # Sisa jadi nama lokasi
      loc=$0
      sub(/^[^ ]+ +/,"",loc)

      # Filter FREE jika diminta
      if (only_free=="1" && index(toupper(loc),"[FREE]")==0) next

      # Whitelist negara jika diset
      if (length(allow)>0 && !(cc in WL)) next

      # Buang tag [FREE]/[PREMIUM] dari nama lokasi
      gsub(/\[.*\]/,"",loc)
      sub(/[[:space:]]+$/,"",loc)

      # Cetak dalam format "cc|loc"
      if (length(cc)>0 && length(loc)>0) print cc"|"loc
    }
  ' | shuf -n 1
}

# --- Fungsi: connect ke lokasi "CC|Name" atau fallback ke best ---
connect_random() {
  local choice
  choice="$(pick_random_location || true)"

  if [[ -z "$choice" ]]; then
    echo "[i] Tidak dapat memilih lokasi (mungkin filter terlalu ketat). Connect best saja."
    sudo windscribe-cli connect
    return
  fi

  local cc="${choice%%|*}"
  local name="${choice#*|}"

  echo "[i] Menghubungkan ke lokasi acak: $cc - $name"
  # Banyak CLI Windscribe menerima "negara" saja,
  # tetapi untuk spesifik kota/cluster biasanya cukup pakai negara,
  # atau gabungan string: "US New York"
  # Coba kota dulu, fallback ke negara.
  if ! sudo windscribe-cli connect "$cc $name"; then
    sudo windscribe-cli connect "$cc"
  fi
}

# --- Trap: putuskan saat script dihentikan (mode rotate) ---
cleanup() {
  echo
  echo "[*] Memutuskan koneksi Windscribe..."
  sudo windscribe-cli disconnect || true
}
if [[ "$MODE" == "rotate" ]]; then
  trap cleanup EXIT
fi

# --- Eksekusi ---
case "$MODE" in
  once)
    sudo windscribe-cli disconnect >/dev/null 2>&1 || true
    connect_random
    sudo windscribe-cli status
    ;;
  rotate)
    echo "[*] Mode rotate aktif. Interval: ${INTERVAL}s. Tekan Ctrl+C untuk berhenti."
    while true; do
      sudo windscribe-cli disconnect >/dev/null 2>&1 || true
      connect_random
      sudo windscribe-cli status || true
      sleep "$INTERVAL"
    done
    ;;
  *)
    usage; exit 1;;
esac
