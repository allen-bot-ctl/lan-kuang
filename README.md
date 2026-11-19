# 栏况 LanKuang

macOS 菜单栏资源监控（原生 Swift / AppKit，macOS 13+，Intel 与 Apple 芯片通用包）。

- 左侧菜单栏项：`13G 9%`（已用内存整数 G + 整机 CPU 整数 %，等宽数字），每 2 秒刷新。
- 右侧菜单栏项：自绘电池图标 + `87%`；充电叠 ⚡，接电源未充电叠插头，用电池且 ≤20% 填充变红；无电池时隐藏。
- 鼠标指向左侧项弹出面板：内存（已用/总量 G 与 %）、CPU、启动盘（已用/总量与环形图）。面板打开时每秒刷新，关闭即停；磁盘打开时取一次、之后每 60 秒。
- 右键菜单：检查更新…（Sparkle 2）/ 开机自启动（SMAppService）/ 退出。
- 睡眠、屏幕休眠、锁屏时暂停采样。只用系统 API，不调外部命令。

## 目录

```
project.env            产品名 / Bundle ID / 仓库名 / Sparkle 版本与公钥（改名只改这里）
Package.swift          纯逻辑模块 MonitorCore + 单测（Linux 也能 swift test）
Sources/MonitorCore/   格式化、CPU 差值、电池图标参数、磁盘、刷新节奏
Tests/MonitorCoreTests/
App/                   AppKit/SwiftUI 界面与 Darwin 采样（scripts/build.sh 用 swiftc 编译）
scripts/build.sh       VERSION -> 双架构编译、lipo、.app、ad-hoc 签名、dmg/zip/sha256
scripts/appcast.sh     sign_update 签 zip，生成 appcast.xml
docs/changes/          需求契约
release-notes/         vX.Y.Z.md 发版说明（CI 优先使用）
```

## 开发

```bash
swift test                    # 单测（macOS 或 Linux）
scripts/build.sh 0.1.0        # 仅 macOS，产物在 dist/
open build/LanKuang.app
```

## 发布

推 `vX.Y.Z` 标签，`.github/workflows/release.yml` 在 macOS 上跑单测、构建、校验双架构与签名、双架构冒烟、签名 zip 生成 `appcast.xml`，再上传：

- `LanKuang-X.Y.Z-mac-universal.dmg`（主下载）
- `LanKuang-X.Y.Z-mac-universal.zip` / `.zip.sha256` / `appcast.xml`（应用内更新）

需要仓库 Secret `SPARKLE_ED_PRIVATE_KEY`（Sparkle EdDSA 私钥：32 字节种子的 base64），公钥写在 `project.env`。

安装包为 ad-hoc 签名、未公证：首次打开在 Finder 中右键「打开」，或到「系统设置 → 隐私与安全性」选「仍要打开」。
