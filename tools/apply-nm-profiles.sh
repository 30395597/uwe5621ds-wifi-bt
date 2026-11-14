#!/bin/bash
# Set up / fix the NetworkManager WiFi profiles for UWE5621DS.
#
# This is the single most important part of the fix: on the affected box the
# WiFi failure was caused by SIX conflicting NM profiles, not by the driver.
# A passwordless profile with autoconnect=yes kept triggering WPS PBC, and a
# high-priority profile was pinned to a BSSID that was no longer on air.
#
# This script is intentionally conservative: it does NOT delete anything and
# does NOT restart NetworkManager (that would risk dropping SSH over eth0).
set -u
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_PRIMARY_SSID:=}"
: "${UWE_PRIMARY_UUID:=}"
: "${UWE_PRIMARY_BSSID:=}"
: "${UWE_FALLBACK_UUID:=}"
: "${UWE_MTU:=1400}"
: "${UWE_WIFI_ROUTE_METRIC:=500}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }
if [ -z "$UWE_PRIMARY_SSID" ] || [ "$UWE_PRIMARY_SSID" = "YOUR_2G_SSID" ]; then
    echo "ERROR: edit $CONF first (UWE_PRIMARY_SSID / UWE_PRIMARY_UUID / UWE_PRIMARY_BSSID)"
    exit 1
fi

echo "=== Current WiFi profiles ==="
nmcli -f NAME,UUID,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show

echo
echo "=== Audit: profiles that should NOT autoconnect ==="
nmcli -f NAME,UUID,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show 2>/dev/null |
while read -r line; do
    printf '%s\n' "$line"
done
echo "Check manually for: no PSK + autoconnect=yes, duplicate SSIDs, or a BSSID"
echo "that does not appear in:  nmcli dev wifi list ifname $UWE_WLAN_IF"
echo "Delete a bad one with:    nmcli connection delete uuid <UUID>"

echo
echo "=== Create / update the PRIMARY profile ==="
if [ -n "$UWE_PRIMARY_UUID" ] && \
   [ "$UWE_PRIMARY_UUID" != "00000000-0000-0000-0000-000000000000" ] && \
   nmcli connection show uuid "$UWE_PRIMARY_UUID" >/dev/null 2>&1; then
    P="$UWE_PRIMARY_UUID"
    echo "  reusing existing profile $P"
else
    if [ -z "${UWE_PSK:-}" ]; then
        read -rsp "WiFi passphrase for '$UWE_PRIMARY_SSID' (not echoed, not stored in repo): " UWE_PSK
        echo
    fi
    nmcli connection add type wifi ifname "$UWE_WLAN_IF" con-name "$UWE_PRIMARY_SSID" \
        ssid "$UWE_PRIMARY_SSID" 802-11-wireless-security.psk "$UWE_PSK" \
        >/dev/null || { echo "ERROR: could not create profile"; exit 1; }
    P="$(nmcli -f UUID connection show "$UWE_PRIMARY_SSID" | awk 'NR==2{print $1}')"
    echo "  created UUID=$P  -- WRITE THIS INTO $CONF AS UWE_PRIMARY_UUID"
fi

setp() { nmcli connection modify "$P" "$@" 2>&1 || echo "  WARN: failed: $*"; }
setp connection.id "$UWE_PRIMARY_SSID"
setp connection.interface-name "$UWE_WLAN_IF"
setp connection.autoconnect yes
setp connection.autoconnect-priority 200
setp connection.autoconnect-retries 2
setp 802-11-wireless.mode infrastructure
setp 802-11-wireless.band bg
[ -n "$UWE_PRIMARY_BSSID" ] && [ "$UWE_PRIMARY_BSSID" != "AA:BB:CC:DD:EE:FF" ] && \
    setp 802-11-wireless.bssid "$UWE_PRIMARY_BSSID"
setp 802-11-wireless.mtu "$UWE_MTU"
setp 802-11-wireless.powersave 2                 # 2 = disable
setp 802-11-wireless-security.key-mgmt wpa-psk
setp 802-11-wireless-security.auth-alg open
setp 802-11-wireless-security.proto rsn
setp 802-11-wireless-security.pairwise ccmp
setp 802-11-wireless-security.group ccmp
setp 802-11-wireless-security.pmf 1               # 1 = disable PMF (802.11w)
setp ipv4.method auto
setp ipv4.route-metric "$UWE_WIFI_ROUTE_METRIC"
setp ipv6.method disabled

echo
echo "=== Optional fallback (5G with 802.11r disabled on the AP) ==="
if [ -n "$UWE_FALLBACK_UUID" ]; then
    setf() { nmcli connection modify uuid "$UWE_FALLBACK_UUID" "$@" 2>&1 || echo "  WARN: $*"; }
    setf connection.autoconnect yes
    setf connection.autoconnect-priority 20
    setf connection.autoconnect-retries 1         # do NOT retry: a failed connect poisons the chip
    setf 802-11-wireless.mtu "$UWE_MTU"
    setf 802-11-wireless.powersave 2
    setf 802-11-wireless-security.key-mgmt wpa-psk
    setf 802-11-wireless-security.pmf 1
    setf ipv4.route-metric "$UWE_WIFI_ROUTE_METRIC"
    setf ipv6.method disabled
else
    echo "  (none configured)"
fi

echo
echo "=== Disable autoconnect on every OTHER wifi profile ==="
nmcli -f UUID,TYPE connection show 2>/dev/null | awk '$2=="wifi"{print $1}' |
while read -r u; do
    [ "$u" = "$P" ] && continue
    [ "$u" = "$UWE_FALLBACK_UUID" ] && continue
    nmcli connection modify uuid "$u" connection.autoconnect no 2>/dev/null && \
        echo "  autoconnect=no : $u"
done

echo
echo "=== Reload (NO NetworkManager restart) ==="
nmcli connection reload 2>/dev/null
nmcli -f NAME,UUID,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
echo
echo "Done. Verify with:  sudo bash tools/verify.sh"
