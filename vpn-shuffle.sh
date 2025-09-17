#!/bin/bash
set -euo pipefail

# --- CONFIG (opsional) ---
ONLY_FREE="${ONLY_FREE:-1}"     # 1 = pilih lokasi FREE saja, 0 = semua
COUNTRY_ALLOW="${COUNTRY_ALLOW:-}"  # contoh: "US,DE,SG" (whitelist negara, kosong = semua)
INTERVAL="${INTERVAL:-600}"     # jeda rotasi (detik) untuk mode --rotate
TRIES="${TRIES:-30}"            # percobaan baca lokasi (jaga-jaga CLI lambat)
PIDFILE="${PIDFILE:-/run/vpn-shuffle.pid}"
LOGFILE="${LOGFILE:-/var/log/vpn-shuffle.log}"

# --- Prasyarat ---
command -v windscribe-cli >/dev/null || { echo "windscribe-cli tidak ditemukan."; exit 1; }
systemctl enable --now windscribe-helper.service >/dev/null 2>&1 || true
windscribe-cli firewall on >/dev/null || true

# --- Fungsi: ambil daftar lokasi, filter, acak satu ---
pick_random_location() {
  local out i
  for ((i=1;i<=TRIES;i++)); do
    if out="$(sudo windscribe-cli locations 2>/dev/null)"; then
      [[ -n "$out" ]] && break
    fi
    sleep 1
  done

  echo "$out" | awk 'NF>0' | \
  awk '
    BEGIN{OFS=" "}
    {
      line=$0
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
      cc=$1
      loc=$0
      sub(/^[^ ]+ +/,"",loc)
      if (only_free=="1" && index(toupper(loc),"[FREE]")==0) next
      if (length(allow)>0 && !(cc in WL)) next
      gsub(/\[.*\]/,"",loc)
      sub(/[[:space:]]+$/,"",loc)
      if (length(cc)>0 && length(loc)>0) print cc"|"loc
    }
  ' | shuf -n 1
}

# --- Fungsi: connect ke lokasi "CC|Name" atau fallback ke best ---
connect_random() {
  local choice cc name
  choice="$(pick_random_location || true)"

  if [[ -z "$choice" ]]; then
    echo "[i] Can't find any location (strict filter). Connect to the best."
    sudo windscribe-cli connect
    return
  fi

  cc="${choice%%|*}"
  name="${choice#*|}"

  echo "[i] Connect To Random Location: $cc - $name"
  if ! sudo windscribe-cli connect "$cc $name"; then
    sudo windscribe-cli connect "$cc"
  fi
}

# --- Helper PID/status ---
is_running() {
  local pid="$1"
  if [[ -z "$pid" ]]; then return 1; fi
  if kill -0 "$pid" >/dev/null 2>&1; then return 0; else return 1; fi
}

start_background_rotate() {
  if [[ -f "$PIDFILE" ]]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if is_running "$pid"; then
      echo "rotate already running with PID $pid"
      return 0
    else
      echo "Stale PID file found, removing."
      rm -f "$PIDFILE"
    fi
  fi

  echo "[*] Starting background rotate (interval ${INTERVAL}s). Logs -> ${LOGFILE}"
  # start self in background as new session; redirect stdout/stderr to logfile
  # we call the same script with "rotate" mode (foreground loop) in background
  setsid bash -c "exec \"$0\" rotate" >>"$LOGFILE" 2>&1 &
  pid=$!
  # give it a moment to start
  sleep 1
  if is_running "$pid"; then
    echo "$pid" > "$PIDFILE"
    echo "Started rotate (PID $pid)"
    return 0
  else
    echo "Failed to start rotate; check $LOGFILE"
    return 1
  fi
}

stop_background_rotate() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "rotate not running (no PID file)."
    return 1
  fi
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "PID file empty; removing."
    rm -f "$PIDFILE"
    return 1
  fi
  if ! is_running "$pid"; then
    echo "Process $pid not running; removing stale PID file."
    rm -f "$PIDFILE"
    return 1
  fi

  echo "[*] Stopping rotate (PID $pid)..."
  kill "$pid" || true
  # wait up to 10s for termination
  for i in {1..10}; do
    if ! is_running "$pid"; then
      break
    fi
    sleep 1
  done
  if is_running "$pid"; then
    echo "PID $pid did not stop; sending SIGKILL."
    kill -9 "$pid" || true
  fi
  rm -f "$PIDFILE"
  echo "Stopped."
  return 0
}

status_background_rotate() {
  if [[ -f "$PIDFILE" ]]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if is_running "$pid"; then
      echo "rotate running (PID $pid)."
      return 0
    else
      echo "PID file exists but process $pid not running."
      return 1
    fi
  else
    echo "rotate not running."
    return 3
  fi
}

# --- Trap untuk foreground rotate (cleanup on exit) ---
cleanup() {
  echo
  echo "[*] Memutuskan koneksi Windscribe..."
  sudo windscribe-cli disconnect || true
}
trap cleanup EXIT

# --- Eksekusi modes ---
case "$MODE" in
  once)
    sudo windscribe-cli disconnect >/dev/null 2>&1 || true
    connect_random
    sudo windscribe-cli status
    ;;
  rotate)
    echo "[*] Mode rotate (foreground). Interval: ${INTERVAL}s. Ctrl+C to stop."
    while true; do
      sudo windscribe-cli disconnect >/dev/null 2>&1 || true
      connect_random
      sudo windscribe-cli status || true
      sleep "$INTERVAL"
    done
    ;;
  rotate-start)
    start_background_rotate
    ;;
  rotate-stop)
    stop_background_rotate
    ;;
  rotate-status)
    status_background_rotate
    ;;
  *)
    usage; exit 1;;
esac
