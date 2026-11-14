#!/bin/sh
# UWE5621DS WiFi soft reset.
# Only touches the WiFi/SD controller (ffe05000.mmc), NEVER the eMMC
# controller (ffe07000) - unbinding the wrong one kills the root fs.
# Uses modprobe so vermagic always matches the running kernel.
set -u
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_PRIMARY_UUID:=}"
: "${UWE_GATEWAY:=192.168.1.1}"

MMC=ffe05000.mmc
DRV=/sys/bus/platform/drivers/meson-gx-mmc
IF="$UWE_WLAN_IF"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "stop BT service"
systemctl stop uwe5621-bt.service 2>/dev/null

log "unload modules"
rmmod sprdbt_tty 2>/dev/null
[ -d /sys/module/skip_inq_mode ] && rmmod skip_inq_mode 2>/dev/null
rmmod sprdwl_ng 2>/dev/null
rmmod uwe5621_bsp_sdio 2>/dev/null

i=0
while [ -d /sys/module/sprdwl_ng ] || [ -d /sys/module/uwe5621_bsp_sdio ]; do
  i=$((i+1)); [ $i -gt 8 ] && { log "modules still loaded, abort"; exit 1; }
  sleep 1
done

log "sdio controller rebind ($MMC)"
[ -e "$DRV/$MMC" ] && { echo -n "$MMC" > "$DRV/unbind"; log "unbound"; }
sleep 2
[ -e "/sys/bus/platform/devices/$MMC" ] && { echo -n "$MMC" > "$DRV/bind"; log "bound"; }
sleep 4

log "load in-kernel modules (matching uname -r)"
modprobe uwe5621_bsp_sdio || { log "BSP modprobe failed"; exit 1; }
sleep 3
modprobe sprdwl_ng || { log "sprdwl_ng modprobe failed"; exit 1; }
sleep 5

ip link show "$IF" >/dev/null 2>&1 || { log "$IF missing"; exit 1; }
iw dev "$IF" set power_save off 2>/dev/null
log "$IF ok: $(cat /sys/class/net/$IF/address)"

if [ "${1:-}" = "--connect" ]; then
  [ -z "$UWE_PRIMARY_UUID" ] && { log "no UWE_PRIMARY_UUID configured"; exit 1; }
  log "activate primary profile"
  nmcli connection up uuid "$UWE_PRIMARY_UUID" 2>&1 | tail -2
  sleep 4
  ping -c2 -W2 -I "$IF" "$UWE_GATEWAY" >/dev/null 2>&1 \
    && log "ping gw OK" || log "ping gw FAILED"
fi
exit 0
