# AGENTS.md

栏况（LanKuang）是 macOS 菜单栏资源监控：内存、CPU、磁盘、电池。原生 Swift + AppKit（面板内容用 SwiftUI），macOS 13+，通用包。仓库：https://github.com/allen-bot-ctl/lan-kuang 。本文件是 agent 的入口。

## 验证命令（完成标准，必须当轮执行）

```bash
swift test                   # MonitorCore 单测；macOS 与 Linux 都能跑
scripts/build.sh 0.1.0       # macOS：双架构编译 + lipo + .app + dmg/zip
open build/LanKuang.app      # 真启动冒烟：菜单栏出现「13G 9%」与电池项，指向左项能弹出三卡面板
```

- 每次改代码至少跑 `swift test`；改了 `App/` 必须在 macOS 上编译（本地或 CI），Linux 编不了 AppKit。
- **打包成功 ≠ 能运行。** 发布前必须真启动一次，CI 已对 arm64 与 x86_64（Rosetta）各冒烟 8 秒。
- **没有当轮验证输出不算完成。** 交付说明贴出 `swift test` 通过条数、CI 的 `RELEASE:` 行和冒烟观察；只写「应该没问题」视为未完成。

## 红线

1. 只用系统 API（Mach host_statistics、IOKit IOPS、URLResourceValues、SMAppService）；**不调外部命令**（`vm_stat`、`pmset`、`top` 等都不行），不引入 Sparkle 以外的第三方依赖。
2. 计算与格式化放 `Sources/MonitorCore`，不得 import Darwin/AppKit/IOKit，保证 Linux 上 `swift test` 可跑；新逻辑先写测试。
3. 采样只在需要时跑：菜单栏 2 秒；面板打开时 1 秒、关闭即停；磁盘打开时 + 60 秒；电池靠 IOPS 通知 + 60 秒兜底；睡眠/屏幕休眠/锁屏全部暂停。节奏常量只改 `Refresh`。
4. 菜单栏用等宽数字字体，宽度不能随数字跳动；内存只显示整数加 `G`。
5. 两个独立 NSStatusItem，都设 `autosaveName`；无电池时隐藏电池项。不加 Dock 图标（LSUIElement）。
6. 面板是不抢焦点的 NSPanel；不用 MenuBarExtra。
7. 签名只做 ad-hoc，不开 hardened runtime；Sparkle 私钥只在 GitHub Secret，脚本经 stdin 传给 `sign_update`，任何日志不得打印。
8. 产品名、Bundle ID、仓库名、Sparkle 版本与公钥只写在 `project.env`；Swift 代码里不硬编码产品名。
9. 改代码必须同步改相关文档（README、docs/changes 契约）；提交主题用**朴素中文**，不加 `feat:` / `fix:` 前缀。
10. 发布标签一旦有下载就不要重写；修正走新补丁版本。资产命名固定 `LanKuang-<ver>-mac-universal.{dmg,zip,zip.sha256}` + `appcast.xml`。
11. 只改本仓库，不夹带其他仓库的文件。
12. UI / 更新类改动的最终完成标准包含老板真机确认；自动化通过不能替代真机验收。

## 文档地图

| 位置 | 内容 |
| --- | --- |
| [README.md](README.md) | 功能、目录、开发与发布 |
| [docs/changes/](docs/changes/) | 每个版本的需求契约 |
| [release-notes/](release-notes/) | 发版说明（CI 优先使用 `vX.Y.Z.md`） |
