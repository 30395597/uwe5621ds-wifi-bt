# 蓝牙：HCI opcode 纠正与 kretprobe 方案

## 先纠正几个容易搞反的 opcode

| Opcode | 命令 | 说明 |
|---|---|---|
| `0x0C45` | **HCI Write Inquiry Mode** | OGF `0x03`(HCB) / OCF `0x0045`。Marlin3E 不响应，导致 init 超时 |
| `0x080F` | **HCI Write Default Link Policy Settings** | OGF `0x02`(Link Control) / OCF `0x000F`。芯片返回 EINVAL |

推算方式：`opcode = (OGF << 10) | OCF`。
`0x0C45 = (0x03 << 10) | 0x0045`，`0x080F = (0x02 << 10) | 0x000F`。

> 曾有一种说法把 `0x0C45` 当成 Write Default Link Policy，那是错的。本仓库 `src/skip_inq_mode.c` 的注释是对的。

## 为什么"设 quirk"这条路走不通

在 6.18 内核上，以下三条 userspace 方案**全部无效**（已实测确认）：

1. **`HCI_QUIRK_NO_PARK_LINK_POLICY` 这个 enum 在 6.18 已被移除**，根本没有可设的位。
2. **`CONFIG_BT_DEBUGFS` 没有编进 ophub 内核**，所以 `/sys/kernel/debug/bluetooth/hci0/quirk_flags` 不存在，userspace 无从下手。
3. `hci_uart` 里确实有 `DECLARE_BITMAP(quirk_flags, ...)`，但**只在 `hci_register_dev()` 之前由驱动自己设置**，注册完成后 userspace 改不到。
4. 用 `hciattach any` + quirk 参数绕过同样不行——协议选择不经过 quirk 设置路径。

## 可行解：kretprobe 拦截内核函数返回值

`src/skip_inq_mode.c` 是一个 2KB 的 GPL 内核模块，注册两个 kretprobe：

```c
rp_inquiry.kp.symbol_name     = "hci_write_inquiry_mode_sync";
rp_link_policy.kp.symbol_name = "hci_setup_link_policy_sync";
```

handler 里把返回值强制改成 0：

```c
static int rp_handler(struct kretprobe_instance *ri, struct pt_regs *regs)
{
    regs_set_return_value(regs, 0);
    return 0;
}
```

于是 BlueZ 认为这两条不支持的命令执行成功，init 序列能走完，`hci0` 正常注册。**不改内核、不需要 debugfs、不需要重编 bluetooth.ko**。

### 编译（必须针对当前运行的内核）

```bash
sudo apt install -y "linux-headers-$(uname -r)"
cd src
make                                # KDIR 默认 /lib/modules/$(uname -r)/build
sudo cp skip_inq_mode.ko /opt/uwe5621/
```

`install.sh` 会自动尝试编译；若 headers 缺失，会校验仓库内预编译 `.ko` 的 vermagic，**不匹配就明确报错**（vermagic 不匹配时 `insmod` 会直接 Oops）。

### 加载顺序（顺序不能反）

```bash
modprobe bluetooth
modprobe hci_uart
modprobe sprdbt_tty                 # 必须来自 /lib/modules/$(uname -r)
insmod /opt/uwe5621/skip_inq_mode.ko
hciattach -n -s 1500000 /dev/ttyBT0 any
hciconfig hci0 up
```

本仓库由 `tools/bt-load.sh` 完成，且**只在 `wlan0` 已关联之后执行**——BT 上电会占用共享 Marlin RF，抢跑会让 WiFi 的 connect 被固件拒绝（见 [ROOT-CAUSE.md](ROOT-CAUSE.md)）。

## 验证

```bash
hciconfig -a hci0              # 期望 UP RUNNING、Bus: UART、BT 5.0 双模
bluetoothctl list
bluetoothctl scan on           # 经典 + BLE 都能发现设备
bluetoothctl pair <MAC>
bluetoothctl trust <MAC>
bluetoothctl connect <MAC>
sdptool browse <MAC>           # SDP / UUID 解析
```

2026-11-08 与 11-14 两轮实测均通过：hci0 UP RUNNING、扫描发现多台设备（含手机）、`Pairing successful`、`Trusted: yes`、`Connected: yes`、SDP 完整解析出 A2DP / AVRCP / Phonebook / OBEX / PAN / BLE GATT 等 UUID。

## 已知限制 / 别踩的坑

- `br-connection-profile-unavailable` 不是蓝牙链路故障，只是**没装 PipeWire/PulseAudio**，缺少 A2DP 的上层音频服务。需要播放音频时：`apt install -y pipewire pipewire-pulse wireplumber`。
- **不要 `kill hciattach`**：`sprdbt_tty` 的 `sitm_cleanup` 有 refcount bug，会 Oops。只使用 `systemctl stop uwe5621-bt` 或冷启动。
- 之前遇到的 "No default controller / I/O error" 全部是**上一次内核 Oops 之后的脏状态**，冷启动后消失；排查时先看 `dmesg | grep -i Oops`，别急着改配置。
- BT 偶发掉线同样是共享协处理器的固件级电源管理问题，冷启动可恢复。
- 蓝牙与 WiFi 的 SDIO 路径共享，`sprdbt_tty` 与 `sprdwl_ng` 必须**来自同一个内核版本**，不能一个用 `/opt` 的旧 `.ko`、一个用内核自带模块。

## 参考

- Armbian 官方 `armbian/build` PR #11345（UWE5622 BT via `btattach`）——至今仍 open 且面向全志 AW859A，不是 Amlogic 方案
- `rlee10529/uwe5621`（Rockchip 平台 UWE5621 HCI 命令参考）
- `hanjiang2022/fnos_arm64_uwe5621ds-aml-6.18`（含 `btattach` 服务写法）
