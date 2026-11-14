#!/bin/bash
# Cold-start acceptance test. READ ONLY - changes nothing.
# Run after a fresh boot:  sudo bash tools/verify.sh
set -u
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_GATEWAY:=192.168.1.1}"
IF="$UWE_WLAN_IF"

echo "############ UWE5621DS COLD-START ACCEPTANCE $(date '+%F %T') ############"
echo "kernel : $(uname -r)"
echo "uptime : $(uptime -p)"

echo
echo "===== A. AUTOMATIC WIFI ASSOCIATION (max 90s) ====="
i=0
while [ $i -lt 45 ]; do
    if iw dev "$IF" link 2>/dev/null | grep -q "Connected"; then
        echo "auto-associated after ~$((i*2))s"
        break
    fi
    sleep 2; i=$((i+1))
done
iw dev "$IF" link 2>&1 | head -12
echo "--- active connections ---"; nmcli -f NAME,TYPE,DEVICE connection show --active 2>&1
echo "--- addr / mtu ---"; ip -br addr show "$IF" 2>&1
echo -n "MTU: "; cat "/sys/class/net/$IF/mtu" 2>/dev/null
iw dev "$IF" get power_save 2>&1

echo
echo "===== B. STABILITY ====="
echo "--- 100 small pings ---"
ping -I "$IF" -c 100 -i 0.2 -W 2 "$UWE_GATEWAY" 2>&1 | tail -4
echo "--- 30 large packets (1372B) ---"
ping -I "$IF" -c 30 -i 0.2 -W 2 -s 1372 "$UWE_GATEWAY" 2>&1 | tail -4

echo
echo "===== C. ROUTES (eth0 MUST stay default so SSH never drops) ====="
ip route show

echo
echo "===== D. BLUETOOTH ====="
hciconfig -a 2>&1 | head -10
echo "--- modules ---"; lsmod 2>/dev/null | grep -iE 'sprdwl|uwe56|sprdbt|skip_inq|hci_uart'
echo "--- hciattach ---"; ps aux 2>/dev/null | grep '[h]ciattach' | head -3
echo "--- controllers ---"; bluetoothctl list 2>&1
echo "--- 16s scan ---"
timeout 18 bluetoothctl scan on > /tmp/uwe-final-btscan.txt 2>&1
sed 's/\x1b\[[0-9;]*m//g' /tmp/uwe-final-btscan.txt 2>/dev/null | grep -iE 'Device|Discovery|Controller' | head -25

echo
echo "===== E. SERVICES / TIMERS ====="
for s in uwe5621-wifi.service uwe5621-bt.service bluetooth.service \
         uwe5621-postboot-test.service uwe5621-wifi-guard.service; do
    printf '%-40s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null)"
done
echo -n "uwe5621-keepalive.timer: "; systemctl is-active uwe5621-keepalive.timer 2>/dev/null
tail -6 /var/log/uwe5621-keepalive.log 2>/dev/null || echo "(no keepalive entries - normal)"

echo
echo "===== F. HEALTH COUNTERS (all should be 0) ====="
for k in "cp_asserted" "no progress" "Invalid Beacon" "Oops"; do
    printf '%-16s %s\n' "$k" "$(dmesg 2>/dev/null | grep -ci "$k")"
done
echo -n "debug_level: "; cat /sys/module/sprdwl_ng/parameters/debug_level 2>/dev/null || echo "n/a"
echo "--- NM activation log ---"
journalctl -b -u NetworkManager --no-pager 2>/dev/null | grep -iE 'association|activated|failed|no-secrets' | tail -16

echo
echo "############ END - $(date '+%F %T') ############"
