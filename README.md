# UWE5621DS WiFi + Bluetooth for S905L3A / UNT413A (Armbian 6.18.y)

在 **UNT413A（S905L3A / Meson G12A）+ UWE5621DS（Marlin3E，SDIO WiFi + UART BT）** 上，
把 WiFi 和蓝牙**同时**跑起来并在开机后自动恢复的一整套可复现方案。

> 本仓库的 v2 内容来自 2026-11-14 的一轮完整实测修复：冷启动后 WiFi 自动关联、
> 蓝牙自动起、链路稳定。**驱动不用重编，dtb 不用改**。
> v1（6.18.60 预编译 `.ko` 方案）已废弃，见 [legacy/README.md](legacy/README.md)。

---

## 适用环境

| 项 | 值 |
|---|---|
| 板型 | UNT413A / S905L3A（同类 E900V22C、CM311-1a、M401A 可参考） |
| 无线芯片 | UWE5621DS（紫光展锐 Marlin3E） |
| 系统 | Armbian Debian aarch64 |
| 内核 | ophub **6.18.y**（已验证 `6.18.63-ophub`；驱动由上游合入，见 ophub #3727 / #3768） |
| DTB | `meson-g12a-s905l3a-e900v22c-uwe5621ds-tdma.dtb`（含 `wifi@1` / `cap-sdio-irq` / TDMA） |
| 依赖 | `bluez`、`iw`、`network-manager`、`linux-headers-$(uname -r)` |

内核若不是 6.18.y，先升级：

```bash
armbian-update -k 6.18.63 -v stable && reboot
```

---

## 快速开始

```bash
git clone https://github.com/30395597/uwe5621ds-wifi-bt.git
cd uwe5621ds-wifi-bt

sudo bash install.sh                 # 安装脚本/服务，不重启、不改路由
sudo nano /etc/uwe5621.conf          # 填你的 SSID / UUID / BSSID / 网关
sudo bash tools/apply-nm-profiles.sh # 修 NetworkManager profile（密码交互输入，不落库）

sudo reboot
sudo bash tools/verify.sh            # 冷启动验收
```

只做只读体检、不改任何东西：

```bash
sudo bash tools/diagnose.sh          # 报告写到 /root/uwe-diag-<时间戳>.txt
```

> `install.sh` **不会**重启机器、**不会**重启 NetworkManager（避免断掉 eth0 上的 SSH）、
> **不会**改默认路由。备份在 `/root/uwe-v2-backup-<时间戳>/`。

---

## 这套方案到底修了什么

| 问题 | 修复 |
|---|---|
| NM 里 6 个 profile 打架：无密码项触发 WPS PBC、高优先级项绑死一个**已不广播**的 BSSID、正确项反而 `autoconnect=no` | 清理坏 profile，唯一正确项设为主连接，其余 `autoconnect=no`，限制重试次数 |
| 5G AP 开了 802.11r（`RSN: PSK FT/PSK`），Marlin3E 老固件关联失败 | AP 侧降级（[AP-SETTINGS.md](docs/AP-SETTINGS.md)）+ profile 强制纯 WPA2/CCMP、`pmf=1` |
| BT 抢在 WiFi 关联前上电，占用共享 RF 导致 connect 被拒 | `bt-load.sh`：「wlan0 未关联绝不启 BT」+ NM dispatcher 在连上后拉起 |
| v1 的 `/opt` 旧 `.ko` 与 blacklist 可能和内核自带模块混用 | 全部走 `modprobe` 内核自带模块；安装器移除 v1 blacklist；kretprobe 按当前内核现场编译 |
| 偶发掉线 / 失败后反复自动重连把芯片拖死 | 保守自愈：连续 3 分钟无关联才重连 1 次，每小时 ≤3 次，不碰模块、不重启 |
| 开机灌 100MB 的压力脚本干扰链路 | 禁用 `uwe5621-postboot-test.service` |

**实测结果**：WiFi 开机约 2 秒自动连上，100 包 2% 丢包、30 个 1372B 大包 0% 丢包
（修复前 45% 丢包 / 0.98 MB/s）；蓝牙 `hci0 UP RUNNING`、扫描 / 配对 / SDP 全部通过；
`cp_asserted` / `RX no progress` / `Invalid Beacon` / `Oops` 全为 0；eth0 保持默认路由。

完整证据链与「被推翻的几个旧判断」见 [docs/ROOT-CAUSE.md](docs/ROOT-CAUSE.md)。

---

## 仓库结构

```
install.sh                        v2 幂等安装器（备份 → 固件 → 编译 kretprobe → 装脚本/服务）
uwe5621.conf.example              站点参数模板，复制成 /etc/uwe5621.conf 后填写
src/
  skip_inq_mode.c                 kretprobe：强制两条 HCI init 函数返回 0
  Makefile
  FIRMWARE.md                    固件清单与 WCNE 打包头检查
tools/
  load.sh                        WiFi：modprobe 内核自带 uwe5621_bsp_sdio → sprdwl_ng
  bt-load.sh                     BT：等 WiFi 关联后才上电、加载、hciattach
  apply-nm-profiles.sh           创建/修正主 profile，密码交互输入
  diagnose.sh                    只读体检（模块/固件/profile/RSN IE/计数器/BT）
  verify.sh                      冷启动验收（关联、丢包、路由、BT、计数器）
  uwe5621-keepalive.sh           保守自愈（默认启用）
  recover-wifi.sh                SDIO 软复位（只 rebind ffe05000.mmc）
  wifi-guard.sh                  RX-stall 守卫（可选，默认禁用）
  remote-run.py                  SSH 远程执行助手（凭据全走环境变量）
config/
  uwe5621-*.service / .timer     systemd 单元
  99-uwe5621-bt.sh               NetworkManager dispatcher
  nm-profile.nmconnection.example  主连接参数参考（无真实密码）
docs/
  ROOT-CAUSE.md                  根因分析、诊断方法、被推翻的假设
  BLUETOOTH.md                   HCI opcode 纠正、为什么 quirk 不可行、kretprobe 原理
  AP-SETTINGS.md                 路由器侧必改项与 5 分钟决定性实验
  REPAIR-LOG.md                  2026-11-14 修复实录
legacy/                           v1 安装器（勿运行）
uwe5621ds/                        v1 遗留 .ko / 固件 / 脚本（DEPRECATED）
```

---

## 配置 `/etc/uwe5621.conf`

所有站点相关值都集中在这里，**脚本里不含任何真实 SSID / BSSID / UUID / 密码 / IP**。

```bash
sudo cp uwe5621.conf.example /etc/uwe5621.conf
sudo chmod 600 /etc/uwe5621.conf
sudo nano /etc/uwe5621.conf
```

关键项：

| 变量 | 说明 |
|---|---|
| `UWE_PRIMARY_SSID` | 主连接 SSID（建议 2.4G 兼容 SSID） |
| `UWE_PRIMARY_UUID` | `nmcli -f NAME,UUID connection show` 查到；新建 profile 后由 `apply-nm-profiles.sh` 打印 |
| `UWE_PRIMARY_BSSID` | 绑定的 AP MAC，避免连到弱信号中继 |
| `UWE_FALLBACK_UUID` | 可选备用（如修好 802.11r 后的 5G），留空即禁用 |
| `UWE_GATEWAY` | 仅用于链路探测，不用于改路由 |
| `UWE_WIFI_ROUTE_METRIC` | 默认 500，必须大于 eth0（通常 100），保证 SSH 不断 |

⚠️ **`/etc/uwe5621.conf`、`*.nmconnection` 已被 `.gitignore` 排除，永远不要提交真实密码。**

---

## 蓝牙要点（重要纠正）

- `0x0C45` = **HCI Write Inquiry Mode**；`0x080F` = **HCI Write Default Link Policy Settings**。
  （`opcode = (OGF << 10) | OCF`，别搞反）
- 6.18 移除了 `HCI_QUIRK_NO_PARK_LINK_POLICY`，且 `CONFIG_BT_DEBUGFS` 未编入，
  `hci_uart` 的 `quirk_flags` 只在 `hci_register_dev()` 前由驱动设置——**userspace 设 quirk 这条路完全走不通**。
- 正解是 `src/skip_inq_mode.c`：用 kretprobe 拦 `hci_write_inquiry_mode_sync` /
  `hci_setup_link_policy_sync` 的返回值，强制为 0，让 BlueZ 的 init 序列走完。
- **不要 `kill hciattach`**（`sprdbt_tty` 的 `sitm_cleanup` refcount bug 会 Oops），
  用 `systemctl stop uwe5621-bt` 或冷启动。
- 蓝牙音频需要额外装 `pipewire pipewire-pulse wireplumber`；否则
  `br-connection-profile-unavailable` 只是缺上层音频服务，蓝牙链路本身没问题。

详见 [docs/BLUETOOTH.md](docs/BLUETOOTH.md)。

---

## 故障排查速查

| 现象 | 先查 |
|---|---|
| 开机连不上 | `nmcli -f NAME,UUID,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show`；有没有无密码项 / 绑死 BSSID |
| `association took too long` / `status code 54` | `iw dev wlan0 scan \| grep -A6 'RSN:'`，看是不是 `PSK FT/PSK` → 关 802.11r |
| 内核 Oops / 模块加载失败 | `modinfo -F vermagic` 三个模块是否都等于 `uname -r`；`/opt` 有没有旧 `.ko` 被 insmod |
| SDIO `-19` / 完全没有 wlan0 | `head -c4 wcnmodem.bin` 是否为 `WCNE`；见 [src/FIRMWARE.md](src/FIRMWARE.md) |
| BT "No default controller / I/O error" | 多半是上次 Oops 的脏状态：`dmesg \| grep -i Oops`，然后**拔电源 ≥10 秒**冷启动 |
| 丢包高 / 速率低 | 看 `iw dev wlan0 link` 的信号强度；连到弱中继就改 BSSID 或修主 AP |
| SSH 断了 | 检查 `ip route`：`route-metric` 是否让 wlan0 抢了默认路由 |

完整检查项：`sudo bash tools/diagnose.sh`。

---

## 已知限制（诚实清单）

- `skip_inq_mode.ko` 与内核模块 vermagic 必须精确匹配 `uname -r`，**升内核要重编 kretprobe 模块**。
- 蓝牙靠 kretprobe hack，不是正式 quirk；Armbian 官方 `btattach` PR #11345 面向全志 AW859A，不适用 Amlogic。
- 普通 `reboot` 不掉 SDIO 的电；芯片真锁死（持续 `cp_asserted`）必须**拔电源 ≥10 秒**。
- 当前稳定链路连的是弱信号中继（约 -77 dBm），2% 丢包来自这里。要跑满速，需按
  [AP-SETTINGS.md](docs/AP-SETTINGS.md) 关掉 5G 的 FT/PSK 或恢复主路由 2.4G 射频。
- **真正的"完美解"**仍是换 **RTL8822CS** 模块（内核自带驱动，WiFi+BT 开箱即用）或插 USB 无线网卡。

---

## 致谢与参考

- [ophub/amlogic-s9xxx-armbian](https://github.com/ophub/amlogic-s9xxx-armbian) #3727（UWE5621/5622 驱动移植 6.18）、
  #3768（3 个连环 Bug 修复，合入 commit `9bcb8ea5064a`，实测 5GHz 332.64 Mbps）、#1205 / #3019 / #636
- [armbian/uwe5622](https://github.com/armbian/uwe5622)、
  [LanceMoe/sl905l3a-uwe5621ds](https://github.com/LanceMoe/sl905l3a-uwe5621ds)（CHANGELOG / PORTING / INBOUND-LATENCY）
- [Calmact/e900v22c](https://github.com/Calmact/e900v22c)、
  [hanjiang2022/fnos_arm64_uwe5621ds-aml-6.18](https://github.com/hanjiang2022/fnos_arm64_uwe5621ds-aml-6.18)、
  [rlee10529/uwe5621](https://github.com/rlee10529/uwe5621)
- 固件提取自原厂 Android `update.zip`（专有二进制，仅用于互操作）
- v1 蓝牙方案由 QwenWork agent 完成，v2 修复与文档整理于 2026-11-14

## License

脚本与 `src/skip_inq_mode.c`：**GPL-2.0**（见 [LICENSE](LICENSE)）。
预编译 `.ko` 继承各自驱动的 GPL；固件为展锐专有二进制。
