#!/bin/sh
# Bring up BT only once wlan0 has associated (idempotent, serialized).
[ "$1" = "wlan0" ] || exit 0
case "$2" in up|dhcp4-change|dhcp6-change) ;; *) exit 0 ;; esac
exec 9>/run/uwe5621-bt-dispatcher.lock
flock -n 9 || exit 0
[ -e /sys/class/bluetooth/hci0 ] && exit 0
iw dev wlan0 link 2>/dev/null | grep -q "Connected" || exit 0
logger -t uwe5621 "wlan0 connected -> starting BT"
/usr/bin/systemctl restart uwe5621-bt.service
exit 0
