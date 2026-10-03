# 重启到 Windows

macOS 与 Windows 双系统（Windows 装在独立硬盘上）时，一键把**仅下一次启动**设为 Windows 并正常重启；从 Windows 再次重启后自动回到 macOS。

在 Intel 机型 + OpenCore、macOS 26 上使用。

## 内容

| 文件 | 说明 |
| --- | --- |
| `重启到 Windows.command` | 主脚本：查找 Windows 的 EFI 分区、只读挂载、`bless --nextonly`、核对 NVRAM、重启 |
| `app/main.applescript` | App 外壳：确认对话框 → 以管理员权限运行脚本 `--prepare` → 以当前用户身份发起重启 |
| `app/make-icon.swift` | 生成 App 图标 |
| `build.sh` | 构建 `重启到 Windows.app`，加 `--install` 安装到 `/Applications` |

## 用法

```bash
./build.sh --install                          # 构建并安装 App
"./重启到 Windows.command"                     # 终端里直接运行（会询问确认）
"./重启到 Windows.command" --check             # 只检查，不改启动项、不重启
"./重启到 Windows.command" --cancel            # 撤销尚未生效的一次性启动设置
```

日志：`~/Library/Logs/reboot-to-windows.log`

## 工作方式

1. 在物理硬盘中找同时含有 EFI 分区和 Microsoft 数据分区的硬盘，不依赖 Windows 分区是否挂载、卷名或磁盘编号。
2. 只读挂载该 EFI 分区，确认存在 `EFI/Microsoft/Boot/bootmgfw.efi`。
3. `bless --setBoot --nextonly` 写入 `efi-boot-next`，并核对它确实指向这块 EFI 分区。
4. 通过 `loginwindow` 正常重启（等同苹果菜单“重新启动…”，应用可以提示保存文档）。
