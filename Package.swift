// swift-tools-version:5.9
// 只包含纯逻辑模块与单测（可在 Linux 跑 `swift test`）。AppKit 界面在 App/，由 scripts/build.sh 用 swiftc 编译。
import PackageDescription

let package = Package(
    name: "MonitorCore",
    targets: [
        .target(name: "MonitorCore", path: "Sources/MonitorCore"),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"], path: "Tests/MonitorCoreTests"),
    ]
)
