#!/bin/sh
K=/opt/uwe5621
BT_KO=/lib/modules/$(uname -r)/kernel/drivers/net/wireless/uwe5622/tty-sdio/sprdbt_tty.ko

# Wait for WiFi service to have loaded uwe5621_bsp_sdio (up to 10s)
for i in $(seq 1 10); do
    [ -d /sys/module/uwe5621_bsp_sdio ] && break
    sleep 1
done
[ -d /sys/module/uwe5621_bsp_sdio ] || { echo "BSP not loaded — abort"; exit 1; }

# Ensure bluetooth+hci_uart kernel modules are loaded (needed for kretprobe target)
modprobe bluetooth
modprobe hci_uart

# Load BT modules
[ -d /sys/module/sprdbt_tty ] || insmod "$BT_KO"
[ -d /sys/module/skip_inq_mode ] || insmod "$K/skip_inq_mode.ko"

# Attach HCI — -n keeps foreground for systemd
exec hciattach -n -s 1500000 /dev/ttyBT0 any
