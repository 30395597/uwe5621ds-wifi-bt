# UWE5621DS WiFi + Bluetooth for S905L3A (Armbian)

Enables both WiFi and Bluetooth on Amlogic S905L3A TV boxes with the **UWE5621DS** (Marlin3E) SDIO chip running Armbian with **kernel 6.18.60-ophub** (aarch64).

## What's inside

| Component | Description |
|-----------|-------------|
| `sprdwl_ng.ko` | WiFi driver (from [LanceMoe/sl905l3a-uwe5621ds](https://github.com/LanceMoe/sl905l3a-uwe5621ds)) |
| `uwe5621_bsp_sdio.ko` | SDIO BSP transport for WiFi+BT |
| `skip_inq_mode.ko` | kretprobe patch: skips 2 unsupported HCI commands for BT |
| Firmware | Marlin3E wcnmodem + BT pskey/rf calibration + WiFi INI |
| `install.sh` | One-shot installer |

## Why this exists

Mainline `sprdbt_tty` fails on this chip because the Marlin3E BT controller doesn't respond to `HCI_OP_WRITE_INQUIRY_MODE` (0x0C45) and returns an error for `HCI_OP_WRITE_DEF_LINK_POLICY` (0x080F). Kernel 6.18 removed the relevant quirks (`HCI_QUIRK_NO_PARK_LINK_POLICY`) and `CONFIG_BT_DEBUGFS` is disabled in ophub builds — no userspace quirk setting available.

**Solution:** a 2KB out-of-tree kretprobe module intercepts the return values of `hci_write_inquiry_mode_sync` and `hci_setup_link_policy_sync`, forcing them to return 0 (success) so the init sequence completes.

## Requirements

- Device: S905L3A (Meson G12A) with UWE5621DS WiFi/BT module
- OS: Armbian Debian bookworm aarch64
- Kernel: **6.18.60-ophub** (`.ko` vermagic must match; rebuild from `src/` for other versions)
- DTB: `meson-g12a-s905l3a-e900v22c.dtb` with TDMA overlay (`e900v22c-uwe5621ds-tdma.dtb`)
- Package: `bluez` (for `hciattach`, `bluetoothctl`)

## Install

```bash
git clone https://github.com/YOURNAME/uwe5621ds-wifi-bt.git
cd uwe5621ds-wifi-bt
sudo bash install.sh
sudo systemctl reboot
```

## Verify

```bash
# WiFi
nmcli con show --active
ping -c 3 8.8.8.8

# Bluetooth
hciconfig hci0           # expect: UP RUNNING, BT 5.0
bluetoothctl scan on     # discover nearby devices
bluetoothctl pair <MAC>  # pair a device
```

## Build skip_inq_mode for a different kernel

The kretprobe module is pure GPL C code — rebuild on-device:

```bash
cd src
make
sudo cp skip_inq_mode.ko /opt/uwe5621/
```

Requires `linux-headers-$(uname -r)` installed.

## Uninstall

```bash
sudo systemctl disable --now uwe5621-bt uwe5621-wifi
sudo rm -f /etc/systemd/system/uwe5621-{wifi,bt}.service
sudo rm -f /etc/modprobe.d/uwe5621-blacklist.conf
sudo rm -rf /opt/uwe5621
sudo systemctl daemon-reload
```

## Known limitations

- **BT reliability**: the shared WiFi/BT co-processor has firmware-level power management that can cause intermittent BT disconnections (same as WiFi RX glitches). Cold reboot recovers a stuck BT core.
- **Do not kill hciattach**: `sprdbt_tty` has a `sitm_cleanup` bug — killing the hciattach process can corrupt the module's internal state (refcount leak). Only stop via systemd (`systemctl stop uwe5621-bt`) or reboot.
- **WiFi autoconnect**: after install, create a WiFi profile manually (`nmcli con add ...`) or use NetworkManager GUI.

## Credits

- WiFi driver: [LanceMoe/sl905l3a-uwe5621ds](https://github.com/LanceMoe/sl905l3a-uwe5621ds)
- Rockchip UWE5621 patches (reference for BT commands): [rlee10529/uwe5621](https://github.com/rlee10529/uwe5621)
- Firmware: extracted from Skyworth/coocaa factory Android update.zip

## License

Driver source (`src/skip_inq_mode.c`) and scripts: **GPL-2.0**  
Precompiled `.ko` binaries: inherit GPL from their respective drivers  
Firmware blobs: proprietary Unisoc/Sprd binaries redistributed for interoperability only
