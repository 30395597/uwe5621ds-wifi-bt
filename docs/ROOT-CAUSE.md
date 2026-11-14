# 根因分析：为什么 UWE5621DS 的 WiFi "时好时坏"

> 适用：UNT413A / S905L3A（Meson G12A）+ UWE5621DS（Marlin3E，SDIO WiFi + UART BT）
> 内核：ophub `6.18.63-ophub`（驱动已由上游合入）
> 实测日期：2026-11-14

## 一句话结论

**驱动本身没有坏。真正让 WiFi 连不上的是 NetworkManager 里一堆互相冲突的 profile，加上目标 AP 开启了 802.11r 快速漫游，以及 BT 在 WiFi 关联之前就抢先上电。**
"路由器 MAC 过滤"、"1536 字节 CMD53 限制"、"失败一次必须断电" 这三条流传很广的说法，在本机实测中都不成立。

---

## 症状

- 开机后 `wlan0` 有 IP 但 `iw dev wlan0 link` 显示 Not Connected，或反复 `association took too long`
- 打开驱动调试后看到 `WIFI_CMD_CONNECT` 正常下发、约 2.4s 后固件回 `WIFI_EVENT_CONNECT` 且 `status code 54`
- 换 MAC 地址（`b0` → `b1`）结果完全一样
- 中继 AP 能连，但约 45% 丢包、0.98 MB/s
- 蓝牙 `hci0` 有时 "No default controller / I/O error"

---

## 被实测推翻的假设

| 假设 | 机上证据 | 结论 |
|---|---|---|
| 路由器开了 MAC 黑/白名单 | 换 MAC 后结果完全一致；黑名单会回 explicit reject，而不是静默超时 | ❌ 排除 |
| `dram-access-quirk` 导致 1536 字节 CMD53 上限，超长入站帧堵死 RX 队列 | 本机 dmesg 明确是 `no dram-access quirk, rx xfer max 32768` | ❌ 该 dtb 不适用 |
| 失败一次后本次开机再也连不上任何 AP，必须断电重载芯片 | 5G 自动连接失败后**未断电**，仍成功连上了 2.4G | ❌ 不是必然 |
| 6.18.63 内核混用了 6.18.60 的 `.ko` | 三个模块全部来自 `/lib/modules/6.18.63-ophub/...`，vermagic 一致；`/opt` 里的 6.18.60 `.ko` 只是残留 | ❌ 不是本次故障点（但仍是隐患） |
| 需要重编 LanceMoe v0.8.1 驱动 | 内核自带驱动已含 CP RX-refusal 恢复与 TX 聚合，`modprobe` 即可 | ❌ 不需要 |

> 上游 `LanceMoe/sl905l3a-uwe5621ds` 的 PORTING.md / CHANGELOG v0.8.1 确实记录了 1536 字节 SRAM 上限下的超长入站帧问题，但那是**另一套 dtb/移植分支**的结论，不能无条件套到 ophub 6.18.y。诊断时先看 `dmesg | grep -i dram`，别照抄结论。

---

## 真正的四个根因（按影响排序）

### 1. NetworkManager profile 内战 —— 主因

盒子上同时存在 6 个 WiFi profile：

| profile | 问题 |
|---|---|
| `wx_test` | **没有 PSK** 却 `autoconnect=yes`，开机就触发 WPS PBC |
| `<SSID-2.4G> 1` | 优先级 200，绑定一个**当前根本不广播**的 BSSID |
| `<SSID-2.4G> 2` | 重复项，无 BSSID、默认 MTU、省电开着 |
| `<SSID-2.4G>` | 唯一配置正确的那个，反而 `autoconnect=no` |
| `<SSID-5G>` | RSN 带 FT/PSK（见下） |
| 邻居 AP | 无关，但也在自动连接候选里 |

结果：每次开机 NM 都在按优先级反复撞墙，而正确的 profile 永远轮不到。

**修复**：删掉 3 个坏 profile；唯一正确的设为 `autoconnect=yes` + 优先级 200；其他一律 `autoconnect=no`；失败重试次数限制为 1–2 次（**自动反复重试会把芯片拖进坏状态**）。

### 2. 5G AP 开了 802.11r / FT-PSK

`iw dev wlan0 scan` 拿到决定性证据，信号最强的 5G AP（约 -24 dBm）RSN 里写着：

```
Authentication suites: PSK FT/PSK
```

Marlin3E 老固件处理不了 Fast BSS Transition 的 AKM/MDIE，于是 `association took too long`，固件回报 `status code 54`。

> 关于 54 的解读要谨慎：802.11 里 54 与 Mobility Domain / FT 相关（MDIE 的 Element ID 也恰好是 54），厂商驱动也可能用它表示"认证请求超时、AP 未回应"。**不要把状态码数字本身当作证据**——真正决定性的是上面这行 RSN IE：只要出现 `FT/PSK`，这颗固件就大概率关联失败。

Armbian 论坛 Orange Pi Zero 3（同为 `unisoc_wifi` / UWE5622）有相同案例：`FT: Invalid key management type` → `Association request to the driver failed` → 重启 NetworkManager 无效，只能 reboot。

**修复**：AP 侧关 802.11r/k/v、WPA3/SAE、PMF，改纯 WPA2-PSK/AES；或退而连 2.4G。详见 [AP-SETTINGS.md](AP-SETTINGS.md)。

### 3. 主 AP 的 2.4G 射频消失了

扫描里主路由的两个 2.4G BSSID 都不广播，只剩一个约 -77 dBm 的中继节点。
11-08 那次 "0% 丢包" 连的是主路由，现在它没了——这解释了"最近一折腾又不行"的**外部变化**，不是软件回归。

### 4. BT 抢在 WiFi 关联之前上电

UWE5621DS 的 WiFi 与 BT 共用 Marlin 射频与同一个 `uwe5621_bsp_sdio` BSP。原 `bt-load.sh` 等 150 秒后**无条件**启 BT，而它自己的注释就写着：BT 上电占用共享 RF 后，`sprdwl` 的 connect 会被固件拒绝。

**修复**：`bt-load.sh` 改为「`wlan0` 未关联就绝不启 BT」，同时加一个 NM dispatcher 在 `wlan0` 连上后才拉起蓝牙。顺序反了，前面所有配置都白做。

---

## 可复现的诊断顺序

```bash
sudo bash tools/diagnose.sh          # 只读体检，报告写到 /root/uwe-diag-*.txt
```

人工核对这 5 项，比换驱动有用得多：

1. `modinfo -F vermagic` 三个模块是否都等于 `uname -r`
2. `nmcli -f NAME,UUID,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show` 有没有无密码/重复/绑死 BSSID 的项
3. `iw dev wlan0 scan | grep -A6 'RSN:'` 目标 AP 是不是 `PSK FT/PSK`
4. `dmesg | grep -ciE 'cp_asserted|RX no progress|Oops'` 是否全为 0
5. `dmesg | grep -i dram` 判断 `dram-access-quirk` 到底在不在

**决定性实验（不用登录路由器）**：手机开一个仅 2.4G、纯 WPA2-PSK/AES、关双频合一/WPA3 的热点。手机热点能连且丢包正常 → 100% 是主 AP 的高级特性；连热点也挂 → 才是盒子侧固件/RX 队列问题。

---

## 修复与根因的对应关系

| 根因 | 对应改动 |
|---|---|
| NM profile 内战 | `tools/apply-nm-profiles.sh`、`config/nm-profile.nmconnection.example` |
| 802.11r / 帧过大 | AP 侧降级 + profile 强制 `wpa-psk`/`rsn`/`ccmp`/`pmf=1` |
| BT 抢跑 | `tools/bt-load.sh` + `config/99-uwe5621-bt.sh` |
| 内核版本混用风险 | `tools/load.sh` 全部走 `modprobe`；`install.sh` 移除 v1 blacklist |
| 偶发掉线 | `tools/uwe5621-keepalive.sh`（保守自愈，3 分钟无关联才重连 1 次，每小时 ≤3 次） |
| SDIO RX stall（可选） | `tools/recover-wifi.sh` + `tools/wifi-guard.sh`（默认不启用） |

---

## 仍然存在的硬限制（诚实清单）

- **内核强绑定**：`skip_inq_mode.ko` 与内核模块 vermagic 必须精确等于 `uname -r`；升内核要重编 kretprobe 模块。
- **蓝牙靠 kretprobe hack**，不是正式 quirk；Armbian 官方 `btattach` 方案（armbian/build PR #11345）面向全志 AW859A，不适用于 Amlogic。
- **不要 `kill hciattach`**：`sprdbt_tty` 有 `sitm_cleanup` refcount bug，会 Oops；只能 `systemctl stop uwe5621-bt` 或冷启动。
- **普通 `reboot` 不掉 SDIO 的电**；芯片真锁死时（持续 `cp_asserted`）必须**拔电源 ≥10 秒**。
- 当前稳定链路连的是弱信号中继（约 -77 dBm），100 包约 2% 丢包、1372B 大包 0% 丢包。要跑满速得把 5G 的 FT 关掉或恢复主路由 2.4G。
- 真正"完美解"仍是**换 RTL8822CS 模块（内核自带驱动）或插 USB 无线网卡**。

---

## 参考

- ophub/amlogic-s9xxx-armbian issue #3727（UWE5621/5622 驱动移植到 6.18）、#3768（3 个连环 Bug 修复，合入 commit `9bcb8ea5064a`，实测 5GHz 332.64 Mbps）、#1205 / #3019 / #636（历史"无无线"结论）
- `armbian/uwe5622`（官方驱动源）、`LanceMoe/sl905l3a-uwe5621ds`（CHANGELOG / PORTING / INBOUND-LATENCY）
- `Calmact/e900v22c`（板型资料库）、`hanjiang2022/fnos_arm64_uwe5621ds-aml-6.18`
