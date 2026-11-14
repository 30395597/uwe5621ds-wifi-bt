#!/bin/sh
# UWE5621DS conservative WiFi keepalive.
# Reconnect ONLY after 3 consecutive minutes with no association at all.
# Never unloads modules, never rebinds SDIO, never reboots, never kills hciattach.
set -u
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_PRIMARY_UUID:=}"

STATE=/run/uwe5621-keepalive.state
MARK=/run/uwe5621-keepalive.hour
LOG=/var/log/uwe5621-keepalive.log

exec 9>/run/uwe5621-keepalive.lock
flock -n 9 || exit 0
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

[ -n "$UWE_PRIMARY_UUID" ] || { log "no UWE_PRIMARY_UUID configured - skip"; exit 0; }
[ -e "/sys/class/net/$UWE_WLAN_IF" ] || { log "$UWE_WLAN_IF absent - skip (needs manual attention)"; exit 0; }

if iw dev "$UWE_WLAN_IF" link 2>/dev/null | grep -q "Connected"; then
    [ -f "$STATE" ] && { log "link recovered"; rm -f "$STATE"; }
    exit 0
fi

n=0
[ -f "$STATE" ] && n=$(cat "$STATE" 2>/dev/null)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
n=$((n+1))
echo "$n" > "$STATE"

if [ "$n" -lt 3 ]; then
    log "unassociated ($n/3) - watching"
    exit 0
fi

HOUR=$(date +%Y%m%d%H)
cnt=0
if [ -f "$MARK" ]; then
    h=$(sed -n 1p "$MARK"); c=$(sed -n 2p "$MARK")
    [ "$h" = "$HOUR" ] && [ -n "$c" ] && cnt="$c"
fi
case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
if [ "$cnt" -ge 3 ]; then
    log "reconnect budget exhausted this hour - backing off"
    rm -f "$STATE"
    exit 0
fi
printf '%s\n%s\n' "$HOUR" "$((cnt+1))" > "$MARK"
log "unassociated 3x -> nmcli connection up (attempt $((cnt+1))/3 this hour)"
nmcli connection up uuid "$UWE_PRIMARY_UUID" >> "$LOG" 2>&1
rm -f "$STATE"
exit 0
