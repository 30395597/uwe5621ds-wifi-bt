> **DEPRECATED** — 这是 2026-11-08 的 v1 内容，仅供历史回溯。
>
> 当前方案请用根目录的 `install.sh`、`tools/`、`config/`、`docs/`。
> 特别是这里的 `modules/*.ko` 是针对 `6.18.60-ophub` 编译的预二进制，
> **不要在其它内核上 `insmod`**（vermagic / ABI 不匹配会 Oops）。
> 详见 [legacy/README.md](../legacy/README.md) 与 [src/FIRMWARE.md](../src/FIRMWARE.md)。
