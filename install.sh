#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run as root (uid 0)."
  exit 1
fi

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

echo "Installation complete."
echo "Usage:"
echo "  private-net-apps start       # jalankan vpn-on.sh"
echo "  private-net-apps shut        # jalankan vpn-off.sh"
echo "  private-net-apps shuffle ... # jalankan vpn-shuffle.sh"
