# 栏况 LanKuang

macOS 菜单栏资源监控（原生 Swift / AppKit，macOS 13+，Intel 与 Apple 芯片通用包）。

- 只有一个菜单栏项（v0.1.2 起）：左边电池图形（不写数字；充电叠 ⚡，接电源未充电叠插头，用电池且 ≤20% 填充变红；无电池不画），右边两行 9pt 等宽数字：上内存「12G」、下 CPU「18%」，宽度固定 ≤52pt。菜单栏每 2 秒刷新。
- 鼠标指向菜单栏项弹出面板：内存（已用/总量 G 与 %）、CPU、启动盘（已用/总量与环形图）。面板打开时每秒刷新，关闭即停；磁盘打开时取一次、之后每 60 秒。
- 右键菜单：灰色状态行「电池 87% · 充电中/已接电源/使用电池」（无电池不显示）/ 检查更新…（Sparkle 2）/ 开机自启动（SMAppService）/ 退出栏况。
- CPU 默认以 80%、内存默认以 90% 为警戒阈值，可在设置中心分别调为 0–100%；严格超过时仅对应数值标红，等于阈值保持普通颜色。内存按面板显示的整数百分比判断。
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


### 由已连接的 GitHub 发起云端发布

`release-requests` 是只提交发布请求的公共分支。先确认目标是最新 `master`、同一完整 SHA 已通过本仓库的 CI，再只改该分支的 `.github/release-request.json`（不要把该分支合并回 `master`）。格式：`{"mode":"dry-run","tag":"v0.1.18","commit":"完整的 40 位提交 SHA"}`。只有仓库所有者的推送会被接受。`dry-run` 不创建标签、不调用发布工作流，到 **Release request** 查看核验结果。它不会验证正式签名或实际安装。

仅在用户明确要求发版或已有覆盖本次发版的授权时，才可提交 `publish`：自动化将核验新版本和 CI、创建新标签并触发既有 **Release**；最终以 Release 任务、四个资产及生产更新源检查为准。若标签已创建但触发失败，先找对应标签的已有运行，确认没有后再手动运行 **Release**，不要移动、重建标签。不应把密钥写入此分支。
