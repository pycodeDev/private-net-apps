#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run as root (uid 0)."
  exit 1
fi

usage() {
  cat <<'EOF'
Run private-net-apps as root.

-h | --help
  Show this help

Usage:
  sudo private-net-apps <start|shut|shuffle> [options]

Options: 
  - start mode:
    -if | --iface <name>        Physical interface (default: wlan0)
    -l | --level <basic|1>      Protection Level:
                                - basic : VPN + Tor (default)
                                - 1     : VPN + Tor via obfs4 bridges (stealth)
    -as | -auto_snowflake <0|1> SnowFlake Protection (if obfs4 bridges failed):
                                - 1     : VPN + Tor via Snowflake Proxy
                                - 0     : VPN + Tor
  
  - shuffle mode:
    sudo private-net-apps shuffle [command] [option]

    command:
      --rotate-stop              Stop Rotation
      --rotate-status            Status Rotation
      --rotate-start             Start Rotation in Background Mode

    option
      -r | --rotate              Rotation Mode in Foreground, need Ctrl + C to stop
      -o | --once                Make Once Shuffle Location
      -f | --free                Free Location (default: 1(Free))
      -c | --country <code>      Filter by Country (default: all)
      -i | --interval <seconds>  Interval Rotation (default: 600s)

EOF
}

# ====== Colors & Icons ======
COL_RESET='\033[0m'
COL_YELLOW='\033[33m'
COL_GREEN='\033[32m'
COL_RED='\033[31m'
COL_DIM='\033[2m'
ICON_SPIN='-\|/\'   # simple spinner (portable)
ICON_OK="${COL_GREEN}✓${COL_RESET}"
ICON_FAIL="${COL_RED}✗${COL_RESET}"
ICON_RUN="${COL_YELLOW}⟳${COL_RESET}"

# ====== TTY detect (kalau bukan TTY, matikan animasi) ======
IS_TTY=1
[ -t 1 ] || IS_TTY=0

# ====== Cursor helpers ======
cursor_up()   { (( IS_TTY )) && printf "\033[%dA" "${1:-1}"; }
cursor_down() { (( IS_TTY )) && printf "\033[%dB" "${1:-1}"; }
clear_line()  { (( IS_TTY )) && printf "\033[2K\r"; }

# ====== Progress bar header ======
# draw_bar step total
draw_bar() {
  local step="$1" total="$2" len=10 fill empty
  (( step < 0 )) && step=0
  (( step > total )) && step="$total"
  # skala ke 0..10
  local fills=$(( step * len / total ))
  fill=$(printf "%${fills}s" | tr ' ' '=')
  empty=$(printf "%$((len - fills))s" | tr ' ' '_')
  printf "[%s%s]" "$fill" "$empty"
}

# ====== Spinner thread ======
# spin_while pid lines_to_cover msg_prefix step total
spin_while() {
  local pid="$1" cover="$2" msg="$3" step="$4" total="$5"
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    local c=${ICON_SPIN:i++%${#ICON_SPIN}:1}
    if (( IS_TTY )); then
      cursor_up "$cover"
      clear_line; printf "%s %s %s\n" "$(draw_bar "$step" "$total")" "${COL_YELLOW}${c}${COL_RESET}" "$msg"
      cursor_down $((cover-1))
      sleep 0.1
    else
      sleep 0.2
    fi
  done
}

# ====== Run command with UI ======
# run_step "judul" "perintah..."
run_step() {
  local title="$1"; shift
  local cmd=( "$@" )

  # Cetak heading + placeholder 3 baris status (nanti ditimpa)
  printf "%s %s\n" "$(draw_bar 0 4)" "${ICON_RUN} ${COL_YELLOW}${title}${COL_RESET}"
  printf "  %b Proses Update\n"    "${COL_DIM}•${COL_RESET}"
  printf "  %b Download Packages\n" "${COL_DIM}•${COL_RESET}"
  printf "  %b Install Packages\n"  "${COL_DIM}•${COL_RESET}"
}

# ====== Paket sudah terpasang? ======
pkg_installed() {
  dpkg -l | awk '{print $1,$2}' | grep -qE "^ii $1$"
}

# ====== Jalankan apt sub-step dengan UI per tahap ======
# apt_flow pkgname
apt_flow() {
  local pkg="$1"
  local cover=4  # header + 3 baris status
  local step=0 total=4

  # initial print
  run_step "Mengelola paket: ${pkg}"

  # STEP 1: update
  step=1
  if (( IS_TTY )); then cursor_up "$cover"; fi
  clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_RUN" "${COL_YELLOW}${pkg}${COL_RESET}"
  printf "  %b Proses Update\n"    "$ICON_RUN"
  printf "  %b Download Packages\n" "${COL_DIM}•${COL_RESET}"
  printf "  %b Install Packages\n"  "${COL_DIM}•${COL_RESET}"

  (apt-get update -y >/dev/null 2>&1) & pid=$!
  spin_while "$pid" "$cover" "Proses Update..." "$step" "$total"
  if wait "$pid"; then
    # mark OK
    cursor_up "$cover"
    clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_RUN" "${COL_YELLOW}${pkg}${COL_RESET}"
    printf "  %b Proses Update\n"    "$ICON_OK"
    printf "  %b Download Packages\n" "${COL_DIM}•${COL_RESET}"
    printf "  %b Install Packages\n"  "${COL_DIM}•${COL_RESET}"
  else
    cursor_up "$cover"
    clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_FAIL" "${COL_YELLOW}${pkg}${COL_RESET}"
    printf "  %b Proses Update\n"    "$ICON_FAIL"
    printf "  %b Download Packages\n" "${ICON_FAIL}"
    printf "  %b Install Packages\n"  "$ICON_FAIL"
    printf "%b Gagal apt-get update untuk %s\n" "$ICON_FAIL" "$pkg"
    return 1
  fi

  # STEP 2: download-only
  step=2
  cursor_up "$cover"
  clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_RUN" "${COL_YELLOW}${pkg}${COL_RESET}"
  printf "  %b Proses Update\n"     "$ICON_OK"
  printf "  %b Download Packages\n" "$ICON_RUN"
  printf "  %b Install Packages\n"  "${COL_DIM}•${COL_RESET}"

  (apt-get install -y --download-only "$pkg" >/dev/null 2>&1) & pid=$!
  spin_while "$pid" "$cover" "Download Packages..." "$step" "$total"
  if wait "$pid"; then
    cursor_up "$cover"
    clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_RUN" "${COL_YELLOW}${pkg}${COL_RESET}"
    printf "  %b Proses Update\n"     "$ICON_OK"
    printf "  %b Download Packages\n" "$ICON_OK"
    printf "  %b Install Packages\n"  "${COL_DIM}•${COL_RESET}"
  else
    cursor_up "$cover"
    clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_FAIL" "${COL_YELLOW}${pkg}${COL_RESET}"
    printf "  %b Proses Update\n"     "$ICON_OK"
    printf "  %b Download Packages\n" "$ICON_FAIL"
    printf "  %b Install Packages\n"  "$ICON_FAIL"
    printf "%b Gagal download paket %s\n" "$ICON_FAIL" "$pkg"
    return 1
  fi

  # STEP 3: install
  step=3
  cursor_up "$cover"
  clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_RUN" "${COL_YELLOW}${pkg}${COL_RESET}"
  printf "  %b Proses Update\n"     "$ICON_OK"
  printf "  %b Download Packages\n" "$ICON_OK"
  printf "  %b Install Packages\n"  "$ICON_RUN"

  (apt-get install -y "$pkg" >/dev/null 2>&1) & pid=$!
  spin_while "$pid" "$cover" "Install Packages..." "$step" "$total"
  if wait "$pid"; then
    step=4
    cursor_up "$cover"
    clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_OK" "${COL_YELLOW}${pkg}${COL_RESET}"
    printf "  %b Proses Update\n"     "$ICON_OK"
    printf "  %b Download Packages\n" "$ICON_OK"
    printf "  %b Install Packages\n"  "$ICON_OK"
    printf "%b Packages Installed\n"   "$ICON_OK"
  else
    cursor_up "$cover"
    clear_line; printf "%s %s Mengelola paket: %s\n" "$(draw_bar "$step" "$total")" "$ICON_FAIL" "${COL_YELLOW}${pkg}${COL_RESET}"
    printf "  %b Proses Update\n"     "$ICON_OK"
    printf "  %b Download Packages\n" "$ICON_OK"
    printf "  %b Install Packages\n"  "$ICON_FAIL"
    printf "%b Gagal install paket %s\n" "$ICON_FAIL" "$pkg"
    return 1
  fi
}

# ====== Public API: ui_install pkg1 [pkg2 ...] ======
ui_install() {
  for pkg in "$@"; do
    if pkg_installed "$pkg"; then
      printf "%b %s sudah terpasang\n" "$ICON_OK" "$pkg"
      continue
    fi
    apt_flow "$pkg" || return 1
    echo
  done
}

ui_install tor obfs4proxy snowflake-client

# copy semua komponen ke /usr/local/bin
cp ./vpn-on.sh /usr/local/bin/vpn-on.sh
cp ./vpn-off.sh /usr/local/bin/vpn-off.sh
cp ./vpn-shuffle.sh /usr/local/bin/vpn-shuffle.sh
cp ./private-net-apps /usr/local/bin/private-net-apps

# pastikan executable
chmod +x /usr/local/bin/vpn-on.sh
chmod +x /usr/local/bin/vpn-off.sh
chmod +x /usr/local/bin/vpn-shuffle.sh
chmod +x /usr/local/bin/private-net-apps

echo "Installasi Selesai."
usage
