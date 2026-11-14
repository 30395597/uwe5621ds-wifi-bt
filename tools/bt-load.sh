#!/bin/sh
# UWE5621DS Bluetooth starter.
#
# HARD RULE: once BT powers up the shared Marlin RF, sprdwl's connect path is
# rejected by firmware and does not recover until the chip is reloaded.
# Therefore BT MUST NOT start unless wlan0 has ALREADY associated.
# If WiFi is down, defer to the NetworkManager dispatcher instead.
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_SKIP_KO:=/opt/uwe5621/skip_inq_mode.ko}"
: "${UWE_BT_KO:=/lib/modules/$(uname -r)/kernel/drivers/net/wireless/uwe5622/tty-sdio/sprdbt_tty.ko}"

# Wait for the WiFi BSP (up to 40s)
i=0
while [ $i -lt 20 ]; do
    [ -d /sys/module/uwe5621_bsp_sdio ] && break
    sleep 2; i=$((i+1))
done
[ -d /sys/module/uwe5621_bsp_sdio ] || { echo "BSP not loaded - abort"; exit 1; }

# Wait for association (up to 150s), otherwise do NOT power the BT RF.
i=0
while [ $i -lt 75 ]; do
    if [ -e "/sys/class/net/$UWE_WLAN_IF" ] && \
       iw dev "$UWE_WLAN_IF" link 2>/dev/null | grep -q "Connected"; then
        echo "$UWE_WLAN_IF associated - BT may start"
        break
    fi
    sleep 2; i=$((i+1))
done
if ! iw dev "$UWE_WLAN_IF" link 2>/dev/null | grep -q "Connected"; then
    echo "$UWE_WLAN_IF NOT associated after 150s - BT DEFERRED (no RF power-up)"
    logger -t uwe5621 "BT deferred: WiFi not associated"
    exit 0
fi

modprobe bluetooth
modprobe hci_uart
[ -d /sys/module/sprdbt_tty ] || insmod "$UWE_BT_KO"
[ -d /sys/module/skip_inq_mode ] || {
    [ -f "$UWE_SKIP_KO" ] && insmod "$UWE_SKIP_KO" || \
        echo "WARNING: skip_inq_mode.ko missing - BT init will likely fail"
}

# NEVER kill a live hciattach: sprdbt_tty's release path Oopses the kernel.
if [ -e /sys/class/bluetooth/hci0 ]; then
    echo "hci0 already present - skip attach"
else
    setsid hciattach -n -s 1500000 /dev/ttyBT0 any >/var/log/uwe-bt-hci.log 2>&1 < /dev/null &
    sleep 5
fi
hciconfig hci0 up 2>/dev/null
sleep 1
echo "bt ready: $(hciconfig hci0 2>/dev/null | sed -n 3p | tr -d '\t')"
exit 0
