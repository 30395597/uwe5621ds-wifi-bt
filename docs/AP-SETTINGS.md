# 路由器 / AP 侧建议（让 Marlin3E 固件能连上）

> 这是让 UWE5621DS 从"能用"走到"跑满速"的唯一剩余步骤。盒子侧已经修完。
> 建议**单独开一个兼容 SSID** 给这台盒子，不要改动家里其他设备用的主 SSID。

## 必做

| 设置 | 改成 | 原因 |
|---|---|---|
| **802.11r / FT-PSK / 快速漫游** | **关闭** | 决定性因素。RSN 里出现 `Authentication suites: PSK FT/PSK` 会让 Marlin3E 关联失败，回报 `status code 54` / `association took too long` |
| 加密 | **WPA2-PSK + AES/CCMP 纯模式** | 老固件对混合模式解析不稳 |
| WPA3 / SAE / OWE / 过渡模式 | 关闭 | 同上 |
| PMF (802.11w) | 关闭（或"可选"） | 盒子 profile 里已设 `pmf=1` disable，AP 侧也要一致 |
| 频段 | 2.4G only，固定 20MHz，信道 1/6/11 | 避开 5G 的复杂 IE |
| 双频合一 / Smart Connect | 关闭，2.4G 与 5G 分开命名 | 减少 beacon 体积与频段切换 |
| 802.11k / 802.11v / BTM / Mesh 漫游 | 关闭 | 同类案例用 `wpa_cli set disable_btm 1` 才解决 |
| WiFi6 (ax) / HE 相关 IE | 关闭（用 802.11n/ac） | 缩短 beacon / Probe Response 帧 |

## 建议顺手关掉

- WMM-PS / U-APSD（省电协商，易与 `powersave=2` 冲突）
- AP 隔离 / 访客网络（会影响盒子到网关的连通性判断）
- 无线 MAC 过滤 / 黑白名单（**注意：本次故障与它无关**，换 MAC 结果完全一样；但开着也没好处）

## 必查

- 主路由的 **2.4G 射频是否被关掉了**。11-14 实测两个主路由 2.4G BSSID 都不广播，盒子只能连到约 -77 dBm 的中继，这是 2% 丢包的来源。恢复后盒子能连到约 -24 dBm 的 AP。
- 中继节点也要关 802.11r/k/v，Mesh 回程同样会带 MDIE。

## 验证步骤

改完后在盒子上：

```bash
nmcli dev wifi list ifname wlan0          # 确认兼容 SSID 在列表里
iw dev wlan0 scan | grep -A6 'RSN:'       # 确认不再出现 FT/PSK、SAE、OWE
sudo nmcli --ask dev wifi connect '<兼容SSID>' ifname wlan0
ping -I wlan0 -c 50 <网关IP>              # 期望 0~2% 丢包
```

确认稳定后，把这个 AP 的 BSSID / UUID 写进 `/etc/uwe5621.conf` 的
`UWE_PRIMARY_BSSID` / `UWE_PRIMARY_UUID`，再跑一次 `tools/apply-nm-profiles.sh`
把它设回优先级 200 的主连接。

## 5 分钟决定性实验（不用登录路由器）

手机开热点：**仅 2.4G、WPA2-PSK/AES、关双频合一、关 WPA3**。

- 手机热点能连且丢包正常 → 100% 是主 AP 的高级特性，按上表改路由器
- 连手机热点也挂 → 才是盒子侧固件 / RX 队列问题，跑 `tools/diagnose.sh` 看计数器

## 如果不想折腾路由器

硬件换 **RTL8822CS** 模块（内核自带驱动，WiFi + BT 开箱即用，社区 issue #3019 有人实测"一切正常"），或直接插 USB 无线网卡。这是唯一真正"完美"的解。
