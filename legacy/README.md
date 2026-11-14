# legacy/ — v1（6.18.60 时代）方案，已废弃

`install-6.18.60.sh` 是 2026-11-08 的初版安装器，仅作历史留档，**不要再运行**。

## 为什么废弃

| v1 做法 | 问题 |
|---|---|
| 把 `sprdwl_ng.ko` / `uwe5621_bsp_sdio.ko` / `skip_inq_mode.ko` 从仓库复制到 `/opt/uwe5621/` 并 `insmod` | 预编译 `.ko` 锁死 `6.18.60-ophub` 的 vermagic；升级到 6.18.63 后 ABI 不同源，混用会 Oops |
| 写 `/etc/modprobe.d/uwe5621-blacklist.conf` 屏蔽 `uwe5622_bsp_sdio` / `sprdwl_ng` / `sprdbt_tty` | ophub 6.18.y 已经把修好的驱动合进内核，blacklist 反而把内核自带模块挡在门外 |
| `bt-load.sh` 等 150 秒后**无条件**启 BT | BT 上电占用共享 Marlin RF，会让 WiFi 的 connect 被固件拒绝 |
| `wifi-load.sh` 无 `sleep` 就连续 `insmod` | BSP 与 WiFi 之间必须有间隔，否则枚举不到 SDIO 设备 |
| `install.sh` 引用 `$PKG/firmware/uwe5621ds/*` | 仓库里固件不全，脚本会 `cp` 失败 |
| README 里 `git clone` 地址还是未替换的占位符 | 照抄会 clone 失败 |

## v2 的对应关系

| v1 | v2 |
|---|---|
| `install.sh` | 根目录 `install.sh`（重写） |
| `uwe5621ds/scripts/wifi-load.sh` | `tools/load.sh`（全部 `modprobe` 内核自带模块） |
| `uwe5621ds/scripts/bt-load.sh` | `tools/bt-load.sh`（等 WiFi 关联） |
| `uwe5621ds/services/*` | `config/*` |
| 硬编码内核版本 | `/etc/uwe5621.conf` + 按 `uname -r` 现场编译 kretprobe |

`uwe5621ds/` 目录整体保留（含预编译 `.ko` 与固件）仅用于历史回溯；
**请勿 `insmod` 其中的 `.ko`**，除非确认 vermagic 与 `uname -r` 完全一致。
