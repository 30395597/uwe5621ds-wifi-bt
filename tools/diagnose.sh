#!/bin/bash
# UWE5621DS read-only health check. Safe to run at any time; changes nothing.
# Report is also written to /root/uwe-diag-<timestamp>.txt
set -u
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_GATEWAY:=192.168.1.1}"

OUT="/root/uwe-diag-$(date +%Y%m%d-%H%M%S).txt"
KR="$(uname -r)"
IF="$UWE_WLAN_IF"

{
echo "########## UWE5621DS DIAGNOSTIC $(date '+%F %T') ##########"
echo "kernel : $KR"
echo "arch   : $(uname -m)   uptime: $(uptime -p)"
echo "dtb    : $(grep -hE '^FDT=' /boot/uEnv.txt /boot/armbianEnv.txt 2>/dev/null | head -1)"

echo
echo "===== 1. MODULE VERMAGIC (the #1 cause of Oops) ====="
for m in sprdwl_ng uwe5621_bsp_sdio sprdbt_tty skip_inq_mode hci_uart; do
    printf '%-22s %s\n' "$m" "$(modinfo -F vermagic "$m" 2>/dev/null || echo '(not loaded / built-in)')"
done
echo "-- module files under /lib/modules/$KR --"
find "/lib/modules/$KR" \( -iname '*sprdwl*' -o -iname '*uwe562*' -o -iname '*sprdbt*' \) 2>/dev/null
echo "-- stray .ko in /opt (should NOT be insmod'ed if vermagic differs) --"
for f in /opt/uwe5621/*.ko; do
    [ -f "$f" ] && printf '%-46s %s\n' "$f" "$(modinfo -F vermagic "$f" 2>/dev/null | awk '{print $1}')"
done
echo "-- blacklist / options --"
grep -rniE 'sprdwl|uwe56|sprdbt' /etc/modprobe.d/ 2>/dev/null || echo "(none)"

echo
echo "===== 2. FIRMWARE ====="
for d in /lib/firmware/uwe5621ds /lib/firmware/uwe5622; do
    echo "-- $d --"; ls -la "$d" 2>/dev/null | head -25
done
for f in /lib/firmware/uwe5621ds/wcnmodem.bin /lib/firmware/uwe5622/wcnmodem.bin; do
    [ -f "$f" ] && printf '%s  size=%s  magic=%s\n' "$f" "$(stat -c%s "$f")" "$(head -c4 "$f" | tr -d '\0')"
done
echo "NOTE: a bare 947KB image without the WCNE wrapper never starts CP2 (SDIO -19)."

echo
echo "===== 3. LINKS / ROUTES ====="
ip -br link; ip -br addr; ip route
echo "-- wifi link --"; iw dev "$IF" link 2>&1 | head -12
echo -n "MTU: "; cat "/sys/class/net/$IF/mtu" 2>/dev/null
echo -n "power_save: "; iw dev "$IF" get power_save 2>/dev/null

echo
echo "===== 4. NETWORKMANAGER PROFILE AUDIT ====="
nmcli -f NAME,UUID,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show 2>/dev/null
echo "-- per-profile key settings --"
for f in /etc/NetworkManager/system-connections/*.nmconnection; do
    [ -f "$f" ] || continue
    echo "## $(basename "$f")"
    grep -E '^(id|uuid|autoconnect|autoconnect-priority|autoconnect-retries|ssid|bssid|band|mtu|powersave|key-mgmt|proto|pairwise|group|pmf|route-metric|method)=' "$f" 2>/dev/null
done
echo "RED FLAGS: passwordless profile + autoconnect=yes (WPS PBC), duplicate SSIDs,"
echo "           priority pinned to a BSSID that is not on air."

echo
echo "===== 5. AP SCAN / 802.11r DETECTION ====="
echo "-- BSSID / signal / channel --"
nmcli -f SSID,BSSID,SIGNAL,CHAN,FREQ dev wifi list ifname "$IF" 2>/dev/null | head -25
echo "-- RSN information elements (look for FT/PSK, MDE, SAE/OWE, 802.11w) --"
iw dev "$IF" scan 2>/dev/null | grep -iE '^BSS |SSID:|RSN:|Authentication suites|Mobility Domain|FT|SAE|OWE|PMF|WPA:' | head -80
echo "If a target AP shows 'Authentication suites: PSK FT/PSK', Marlin3E firmware"
echo "will NOT associate -> 'association took too long' / status code 54."

echo
echo "===== 6. KERNEL HEALTH COUNTERS ====="
for k in "cp_asserted" "RX no progress" "Invalid Beacon" "Oops" "sdio.*error" "status code 54"; do
    printf '%-20s %s\n' "$k" "$(dmesg 2>/dev/null | grep -ci "$k")"
done
echo -n "debug_level: "; cat /sys/module/sprdwl_ng/parameters/debug_level 2>/dev/null || echo "n/a"
echo "-- last 30 WiFi-related kernel lines --"
dmesg -T 2>/dev/null | grep -iE 'sprdwl|marlin|sdiohal|WIFI_CMD|WIFI_EVENT|cp_asserted|no progress' | tail -30

echo
echo "===== 7. SERVICES / TIMERS ====="
for s in uwe5621-wifi.service uwe5621-bt.service uwe5621-wifi-guard.service \
         uwe5621-postboot-test.service uwe5621-keepalive.timer bluetooth.service; do
    printf '%-42s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null)"
done
echo "-- keepalive log --"; tail -8 /var/log/uwe5621-keepalive.log 2>/dev/null || echo "(empty)"

echo
echo "===== 8. BLUETOOTH ====="
hciconfig -a 2>/dev/null | head -12
echo "-- modules --"; lsmod 2>/dev/null | grep -iE 'sprdbt|skip_inq|hci_uart|bluetooth'
echo "-- hciattach --"; ps aux 2>/dev/null | grep '[h]ciattach' | head -3
echo "-- controllers --"; bluetoothctl list 2>&1
echo "NOTE: never 'kill hciattach' (sprdbt_tty sitm_cleanup refcount bug)."
echo "      Use 'systemctl stop uwe5621-bt' or a cold boot."

echo
echo "===== 9. QUICK LINK TEST ====="
ping -I "$IF" -c 10 -i 0.3 -W 2 "$UWE_GATEWAY" 2>&1 | tail -3
echo "########## END ##########"
} | tee "$OUT"
echo
echo "Report saved: $OUT"
