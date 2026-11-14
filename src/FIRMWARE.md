# 固件说明

UWE5621DS 需要 `/lib/firmware/uwe5621ds/`（Marlin3E）下的固件与校准文件。
部分驱动版本还会读 `/lib/firmware/uwe5622/wcnmodem.bin`。

本仓库 `uwe5621ds/firmware/uwe5621ds/` 里保留了少量必要文件，**完整清单请从设备或原厂 Android `update.zip` 提取**（固件是展锐/紫光专有二进制，本仓库不主动再分发全套）。

## 实测清单（盒子上）

```
/lib/firmware/uwe5621ds/
  wcnmodem.bin                        # CP2 主固件，813056 字节（WCNE 打包格式）
  bt_configure_pskey.ini
  bt_configure_rf_marlin3_2.ini
  bt_configure_rf_marlin3_3.ini
  bt_configure_rf_marlin3e_2.ini
  bt_configure_rf_marlin3e_3.ini
  bt_configure_rf_marlin.ini
  wifi_23550001_2ant.ini ... wifi_56630001_3ant.ini   # 按 chip id / 天线数选择

/lib/firmware/uwe5622/
  wcnmodem.bin                        # 同上，813056 字节
  wcnmodem-38222.bin                  # 另一个版本（1753088 字节），非必需
  wifi_2355b001_1ant.ini
```

## 最常见的固件坑（ophub issue #3768）

`wcnmodem.bin` 被软链接到 **947KB 的裸固件**、缺少 `WCNE` 打包头 →
CP2 从未启动 → SDIO 报 `-19`（No such device）→ WiFi 完全不出现。

检查：

```bash
ls -l /lib/firmware/uwe5621ds/wcnmodem.bin /lib/firmware/uwe5622/wcnmodem.bin
head -c 4 /lib/firmware/uwe5621ds/wcnmodem.bin | tr -d '\0'   # 期望 WCNE
stat -c '%s %n' /lib/firmware/uwe5621ds/wcnmodem.bin
```

另一坑：驱动查找校准 INI 时路径宏未导出，导致 `cali_ini` 找不到；6.18.63 的 ophub 内核已修复（commit `9bcb8ea5064a` 之一）。

## 安装

`install.sh` 会把仓库里的固件复制到 `/lib/firmware/uwe5621ds/`（`-n`，不覆盖已有文件），
并在 `/lib/firmware/uwe5622/wcnmodem.bin` 缺失时补一份。若提示固件不全，从原厂包或同类盒子的 Armbian 镜像里补齐上表文件。

## 校验

```bash
sudo bash tools/diagnose.sh | sed -n '/FIRMWARE/,/LINKS/p'
dmesg | grep -iE 'wcnmodem|marlin|firmware|WCNE'
```
