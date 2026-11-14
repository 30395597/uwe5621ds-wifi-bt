#!/bin/bash
# UWE5621DS WiFi + Bluetooth installer
# Target: Amlogic S905L3A boxes with UWE5621DS chip, kernel 6.18.60-ophub aarch64
#
# Usage:
#   git clone <repo-url> && cd uwe5621ds-wifi-bt
#   sudo bash install.sh && sudo reboot
#
set -e

PKG="$(cd "$(dirname "$0")" && pwd)/uwe5621ds"

echo "=== UWE5621DS WiFi+BT Installer ==="
echo "Kernel: $(uname -r)"

# Sanity checks
[ "$(uname -m)" = "aarch64" ] || { echo "ERROR: requires aarch64"; exit 1; }
dpkg -s bluez >/dev/null 2>&1 || { echo "Installing bluez..."; apt-get update -qq && apt-get install -y -qq bluez; }

# 1. Firmware
echo "[1/5] Firmware..."
mkdir -p /lib/firmware/uwe5621ds
cp -v "$PKG"/firmware/uwe5621ds/* /lib/firmware/uwe5621ds/

# 2. Kernel modules
echo "[2/5] Modules..."
mkdir -p /opt/uwe5621
cp -v "$PKG"/modules/sprdwl_ng.ko "$PKG"/modules/uwe5621_bsp_sdio.ko "$PKG"/modules/skip_inq_mode.ko /opt/uwe5621/

# 3. Load scripts
echo "[3/5] Scripts..."
cp -v "$PKG"/scripts/wifi-load.sh /opt/uwe5621/load.sh
cp -v "$PKG"/scripts/bt-load.sh /opt/uwe5621/bt-load.sh
chmod +x /opt/uwe5621/load.sh /opt/uwe5621/bt-load.sh

# 4. Systemd services
echo "[4/5] Services..."
cp -v "$PKG"/services/uwe5621-wifi.service "$PKG"/services/uwe5621-bt.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable uwe5621-wifi.service uwe5621-bt.service bluetooth.service

# 5. Blacklist stock modules
echo "[5/5] Blacklist..."
BLK=/etc/modprobe.d/uwe5621-blacklist.conf
[ -f "$BLK" ] && grep -q sprdwl_ng "$BLK" || cat > "$BLK" << 'BL'
blacklist uwe5622_bsp_sdio
blacklist sprdwl_ng
blacklist sprdbt_tty
BL

echo ""
echo "=== Done! Reboot to apply ==="
echo "  systemctl reboot"
