#!/bin/bash
set -euo pipefail

echo "[1] Disconnecting Windscribe..."
sudo windscribe-cli disconnect || true

echo "[2] Disabling Windscribe firewall..."
sudo windscribe-cli firewall off || true

echo "[3] Stopping Tor service..."
sudo systemctl stop tor || true

echo "[✓] Normal network restored (direct ISP)."
