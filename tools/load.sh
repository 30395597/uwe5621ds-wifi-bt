#!/bin/sh
# Load the UWE5621DS WiFi stack from the RUNNING kernel's own modules.
# ophub/linux-6.18.y already ships the patched driver (CP RX-refusal recovery,
# TX aggregation). Never insmod a .ko from /opt: vermagic must match uname -r.
modprobe cfg80211 2>/dev/null

modprobe uwe5621_bsp_sdio || exit 1
i=0; while [ ! -d /sys/module/uwe5621_bsp_sdio ] && [ $i -lt 15 ]; do i=$((i+1)); sleep 1; done
sleep 3
modprobe sprdwl_ng || exit 1

i=0; while [ ! -e /sys/class/net/wlan0 ] && [ $i -lt 40 ]; do i=$((i+1)); sleep 1; done
if [ -e /sys/class/net/wlan0 ]; then
    iw dev wlan0 set power_save off 2>/dev/null || true
    echo "wlan0 ready, power_save off"
fi
exit 0
