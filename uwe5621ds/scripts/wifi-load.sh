#!/bin/sh
K=/opt/uwe5621
[ -d /sys/module/cfg80211 ] || modprobe cfg80211
[ -d /sys/module/uwe5621_bsp_sdio ] || insmod "$K/uwe5621_bsp_sdio.ko"
sleep 2
[ -d /sys/module/sprdwl_ng ] || insmod "$K/sprdwl_ng.ko"
exit 0
