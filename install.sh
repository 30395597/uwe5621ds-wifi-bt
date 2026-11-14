#!/bin/bash
# UWE5621DS WiFi + Bluetooth installer  --  v2 (2026-11-14)
#
# What changed vs v1:
#   * Uses the IN-KERNEL uwe5622 modules shipped by ophub 6.18.y.
#     The old /opt .ko files were built for 6.18.60 and MUST NOT be mixed
#     with a different running kernel (vermagic / ABI mismatch -> Oops).
#   * Removes the old blacklist that blocked those in-kernel modules.
#   * BT is started only AFTER wlan0 has associated (NM dispatcher).
#   * Everything site-specific lives in /etc/uwe5621.conf, not in scripts.
#   * No reboot, no NetworkManager restart, no route changes.
#
# Usage:
#   git clone https://github.com/30395597/uwe5621ds-wifi-bt.git
#   cd uwe5621ds-wifi-bt
#   sudo bash install.sh
#   sudo nano /etc/uwe5621.conf                # fill in your SSID / UUID / BSSID
#   sudo bash tools/apply-nm-profiles.sh       # optional, interactive
#   sudo reboot
#   sudo bash tools/verify.sh                  # cold-start acceptance
#
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONF=/etc/uwe5621.conf
TS="$(date +%Y%m%d-%H%M%S)"
BK="/root/uwe-v2-backup-$TS"
KR="$(uname -r)"

echo "=== UWE5621DS installer v2 ==="
echo "kernel : $KR"
echo "arch   : $(uname -m)"

# ---------- sanity ----------
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }
[ "$(uname -m)" = "aarch64" ] || { echo "ERROR: requires aarch64"; exit 1; }
case "$KR" in
    6.18.*-ophub) : ;;
    *) echo "WARNING: this recipe was validated on 6.18.63-ophub; current is $KR" ;;
esac

MODDIR=/lib/modules/$KR/kernel/drivers/net/wireless/uwe5622
MISSING=0
for m in uwe5621_bsp_sdio.ko sprdwl_ng.ko sprdbt_tty.ko; do
    if ! find "$MODDIR" -name "$m" 2>/dev/null | grep -q .; then
        echo "ERROR: in-kernel module not found: $m"
        MISSING=1
    fi
done
[ "$MISSING" -eq 0 ] || {
    echo "Upgrade first:  armbian-update -k 6.18.63 -v stable"
    exit 1
}

# ---------- backup ----------
echo "[1/8] Backup -> $BK"
mkdir -p "$BK"
cp -a /opt/uwe5621 "$BK/opt-uwe5621" 2>/dev/null || true
cp -a /etc/systemd/system/uwe5621-*.service "$BK/" 2>/dev/null || true
cp -a /etc/systemd/system/uwe5621-*.timer "$BK/" 2>/dev/null || true
cp -a /etc/NetworkManager/dispatcher.d/99-uwe5621-bt.sh "$BK/" 2>/dev/null || true
echo "$BK" > /root/uwe-v2-last-backup

# ---------- packages ----------
echo "[2/8] Packages"
for p in bluez iw network-manager; do
    dpkg -s "$p" >/dev/null 2>&1 || apt-get install -y -qq "$p" 2>/dev/null || true
done

# ---------- firmware ----------
echo "[3/8] Firmware"
if [ -d "$ROOT/uwe5621ds/firmware/uwe5621ds" ]; then
    mkdir -p /lib/firmware/uwe5621ds /lib/firmware/uwe5622
    cp -n "$ROOT"/uwe5621ds/firmware/uwe5621ds/* /lib/firmware/uwe5621ds/ 2>/dev/null || true
    [ -f /lib/firmware/uwe5622/wcnmodem.bin ] || \
        cp -n /lib/firmware/uwe5621ds/wcnmodem.bin /lib/firmware/uwe5622/ 2>/dev/null || true
fi
# wcnmodem.bin MUST be the WCNE-wrapped image, not a bare 947KB blob.
if [ -f /lib/firmware/uwe5621ds/wcnmodem.bin ]; then
    printf '  wcnmodem.bin header: '; head -c 4 /lib/firmware/uwe5621ds/wcnmodem.bin | tr -d '\0'; echo
fi
[ -d /lib/firmware/uwe5621ds ] || { echo "ERROR: firmware missing, see src/FIRMWARE.md"; exit 1; }

# ---------- remove the harmful v1 blacklist ----------
echo "[4/8] Retire v1 blacklist (it blocked the in-kernel modules)"
for f in /etc/modprobe.d/uwe5621-blacklist.conf /etc/modprobe.d/sprdwl_ng.conf; do
    if [ -f "$f" ]; then mv "$f" "$f.disabled-by-v2"; echo "  disabled $f"; fi
done

# ---------- build / install kretprobe module ----------
echo "[5/8] kretprobe module (skip_inq_mode)"
mkdir -p /opt/uwe5621 /opt/uwe5621/tools
BUILT=0
if [ -d "/lib/modules/$KR/build" ]; then
    if make -C "$ROOT/src" KDIR="/lib/modules/$KR/build" clean >/dev/null 2>&1 && \
       make -C "$ROOT/src" KDIR="/lib/modules/$KR/build" >/tmp/uwe-kretprobe-build.log 2>&1; then
        cp "$ROOT/src/skip_inq_mode.ko" /opt/uwe5621/skip_inq_mode.ko
        echo "  built for $KR"
        BUILT=1
    else
        echo "  build failed (see /tmp/uwe-kretprobe-build.log)"
    fi
else
    echo "  no kernel headers at /lib/modules/$KR/build"
fi
if [ "$BUILT" -eq 0 ]; then
    CAND="$ROOT/uwe5621ds/modules/skip_inq_mode.ko"
    VM="$(modinfo -F vermagic "$CAND" 2>/dev/null | awk '{print $1}')"
    if [ "$VM" = "$KR" ]; then
        cp "$CAND" /opt/uwe5621/skip_inq_mode.ko
        echo "  used bundled .ko (vermagic matches)"
    else
        echo "  WARNING: bundled .ko vermagic='$VM' != '$KR'."
        echo "  Install linux-headers-$KR and re-run, or build on device:"
        echo "    cd src && make && sudo cp skip_inq_mode.ko /opt/uwe5621/"
        echo "  Bluetooth will NOT work until this is fixed (WiFi is unaffected)."
    fi
fi

# ---------- scripts ----------
echo "[6/8] Scripts -> /opt/uwe5621"
cp "$ROOT"/tools/load.sh              /opt/uwe5621/load.sh
cp "$ROOT"/tools/bt-load.sh           /opt/uwe5621/bt-load.sh
cp "$ROOT"/tools/recover-wifi.sh      /opt/uwe5621/recover-wifi.sh
cp "$ROOT"/tools/wifi-guard.sh        /opt/uwe5621/wifi-guard.sh
cp "$ROOT"/tools/diagnose.sh          /opt/uwe5621/tools/diagnose.sh
cp "$ROOT"/tools/verify.sh            /opt/uwe5621/tools/verify.sh
cp "$ROOT"/tools/apply-nm-profiles.sh /opt/uwe5621/tools/apply-nm-profiles.sh
cp "$ROOT"/tools/uwe5621-keepalive.sh /usr/local/sbin/uwe5621-keepalive.sh
chmod 755 /opt/uwe5621/*.sh /opt/uwe5621/tools/*.sh /usr/local/sbin/uwe5621-keepalive.sh
cp "$ROOT"/config/99-uwe5621-bt.sh /etc/NetworkManager/dispatcher.d/99-uwe5621-bt.sh
chmod 755 /etc/NetworkManager/dispatcher.d/99-uwe5621-bt.sh

# ---------- systemd ----------
echo "[7/8] systemd units"
cp "$ROOT"/config/*.service "$ROOT"/config/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable uwe5621-wifi.service uwe5621-bt.service bluetooth.service 2>&1 | tail -3
systemctl enable --now uwe5621-keepalive.timer 2>&1 | tail -2
# The RX-stall guard unloads modules: opt-in only.
systemctl disable uwe5621-wifi-guard.service 2>/dev/null || true
# The old v1 stress probe pushes 100MB right after link-up: keep it off.
systemctl disable --now uwe5621-postboot-test.service 2>/dev/null || true

# ---------- site config ----------
echo "[8/8] Site config"
if [ ! -f "$CONF" ]; then
    cp "$ROOT/uwe5621.conf.example" "$CONF"
    chmod 600 "$CONF"
    echo "  created $CONF -- EDIT IT NOW (SSID / UUID / BSSID / gateway)"
else
    echo "  kept existing $CONF"
fi

for f in /opt/uwe5621/*.sh /opt/uwe5621/tools/*.sh /usr/local/sbin/uwe5621-keepalive.sh \
         /etc/NetworkManager/dispatcher.d/99-uwe5621-bt.sh; do
    bash -n "$f" 2>/dev/null || echo "  SYNTAX WARNING: $f"
done

echo
echo "=== install done (NO reboot performed) ==="
echo "Next:"
echo "  1) sudo nano $CONF"
echo "  2) sudo bash $ROOT/tools/apply-nm-profiles.sh   # optional, sets up WiFi profiles"
echo "  3) sudo reboot"
echo "  4) sudo bash $ROOT/tools/verify.sh"
echo "Backup: $BK"
