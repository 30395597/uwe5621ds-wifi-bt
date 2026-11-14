# 2026-11-14 修复实录（脱敏）

> 机器：UNT413A / S905L3A（Meson G12A），UWE5621DS
> 系统：Armbian aarch64，内核 `6.18.63-ophub`
> DTB：`meson-g12a-s905l3a-e900v22c-uwe5621ds-tdma.dtb`
> 所有个人网络信息（SSID / BSSID / UUID / IP / MAC / 密码）已用占位符替换。

## 起始状态

- 蓝牙「系统层可用」：`hci0` 已识别、`bluetoothctl` 扫描能发现设备；此前用千问 + kretprobe 打通
- WiFi 不稳定，且"最近一折腾又不行"
- 豆包的前一轮结论是「AP 侧 MAC 过滤 / 黑名单」，证据是 `WIFI_EVENT_CONNECT` 回 `status code 54`、主 AP 各 BSSID 全部被静默丢弃、换 MAC 无效、中继可连但 45% 丢包

## 诊断（全部只读）

通过 SSH（有线 `<ETH-IP>`）执行了 5 轮体检：

1. **模块来源**：`lsmod` + `modinfo -F vermagic` → 三个模块全部来自 `/lib/modules/6.18.63-ophub/kernel/drivers/net/wireless/uwe5622/...`，vermagic 一致；`/opt/uwe5621/` 里的 6.18.60 `.ko` 只是残留，没被加载
2. **dmesg**：`no dram-access quirk, rx xfer max 32768` → 1536 字节 CMD53 限制不适用
3. **NM profile 导出**：6 个 WiFi profile，发现无密码 + `autoconnect=yes`、绑死不存在的 BSSID、重复项、正确项反而 `autoconnect=no`
4. **AP 扫描**：5G AP 的 RSN 里 `Authentication suites: PSK FT/PSK`；主路由 2.4G 两个 BSSID 均不在广播，只剩中继
5. **BT 启动脚本**：等 150s 后无条件启 BT，注释自己就写着会阻塞 WiFi connect

## 修复动作

| # | 动作 | 说明 |
|---|---|---|
| 1 | 备份 | `/etc/NetworkManager/system-connections/`、`/opt/uwe5621/*.sh`、systemd units → `/root/uwe-fix-backup-<TS>/` |
| 2 | 删 3 个坏 profile | 无密码 WPS 项、绑死 BSSID 项、重复项 |
| 3 | 清理 profile 参数 | 主连接：纯 WPA2/CCMP、`pmf=1`(disable)、MTU 1400、关省电、`ipv6 disabled`、`route-metric 500`（保证 eth0 仍是默认路由，SSH 不掉） |
| 4 | 重写 `bt-load.sh` | `wlan0` 未关联 → 绝不启 BT；已关联才加载 BT 模块并 attach |
| 5 | 新增 NM dispatcher | `99-uwe5621-bt.sh`，`wlan0` up 事件后才 `restart uwe5621-bt.service`，`flock` 串行化、幂等 |
| 6 | 重写 `recover-wifi.sh` | 改用 `modprobe` 内核自带模块，杜绝 6.18.60 混用；只 rebind `ffe05000.mmc`，绝不碰 eMMC 的 `ffe07000` |
| 7 | 禁用 `postboot-test` | 原来开机灌 100MB，既污染 eMMC 又干扰刚建立的链路 |
| 8 | 5G 降级为备用 | 只重试 1 次、优先级 20，避免反复失败把芯片拖死 |
| 9 | 保守自愈 | 连续 3 分钟完全无关联才重连 1 次，每小时 ≤3 次；不卸载模块、不 rebind、不重启、不 kill hciattach |
| 10 | 关驱动 debug | 避免 dmesg 高频写盘 |

**全程没有重启 NetworkManager**（会断掉 eth0 上的 SSH），只做 `nmcli connection reload`。
**全程没有重编驱动**，也没有换 dtb。

## 冷启动验收（重启后实测）

| 项目 | 结果 |
|---|---|
| 开机自动关联 | 约 2 秒内连上 |
| `wlan0` | 有 IP、173.4 MBit/s（协商值）、MTU 1400、power_save off |
| 100 个普通包 | **2% 丢包** |
| 30 个 1372B 大包 | **0% 丢包** |
| `eth0` | `<ETH-IP>` 保持默认路由，SSH 全程未断 |
| 蓝牙 | `hci0 UP RUNNING`、BT5.0、`skip_inq_mode` / `sprdbt_tty` / `hci_uart` 全加载、hciattach 存活、bluetoothd active、扫描发现设备 |
| 健康计数器 | `cp_asserted` / `RX no progress` / `Invalid Beacon` / `Oops` **全部 0** |
| 服务 | wifi / bt / bluetooth active，keepalive.timer active，postboot-test 与 guard 保持 inactive |

对比修复前：中继链路 45% 丢包 / 0.98 MB/s → 2% 丢包 / 大包 0%。

## 结论与遗留

- 结论与根因链路见 [ROOT-CAUSE.md](ROOT-CAUSE.md)
- **遗留**：当前连的是约 -77 dBm 的中继，2% 丢包就来自弱信号。待路由器侧关闭 5G 的 802.11r / FT-PSK（或恢复主路由 2.4G 射频）后，把信号约 -24 dBm 的 AP 调回主连接，即可跑满速
- **备份位置**（盒子上）：`/root/uwe-fix-backup-20261114-192351/`、`/root/uwe-v2-last-backup`

## 复现

```bash
git clone https://github.com/30395597/uwe5621ds-wifi-bt.git
cd uwe5621ds-wifi-bt
sudo bash install.sh
sudo nano /etc/uwe5621.conf
sudo bash tools/apply-nm-profiles.sh
sudo reboot
sudo bash tools/verify.sh
```
