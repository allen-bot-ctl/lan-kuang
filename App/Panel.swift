import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = 0
    @Published var cpu: Int = 0
    @Published var disk: DiskUsage?
    @Published var net = NetRate(up: 0, down: 0)
    /// v0.1.11：电池行；nil = 无电池（台式机），不显示该行。
    @Published var battery: BatteryState?
    /// 布局自检用，不触发重绘。
    var frames: [String: CGRect] = [:]
    /// 调试：固定最长文案（C4 截图与布局自检）。
    var debugLongest = false
}

struct Ring: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color(nsColor: .separatorColor), lineWidth: PanelLayout.ringLineWidth)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: PanelLayout.ringLineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(PanelLayout.ringLineWidth / 2)
        .frame(width: PanelLayout.ringDiameter, height: PanelLayout.ringDiameter)
    }
}

/// 收集各行标签与数值在面板坐标里的 frame（CI 布局自检用）。
struct FrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func reportFrame(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: FrameKey.self, value: [id: g.frame(in: .named("panel"))])
        })
    }
}

/// 一行：环 · 8pt · 标签（次要色） · 弹性空白 · 数值（主色、等宽数字，不截断不换行）。
struct Row: View {
    let id: String
    let label: String
    let value: String
    let percent: Int?   // nil：不画环，改画静态图标（symbol），保证标签对齐
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 0) {
            if let percent { Ring(fraction: ringFraction(percent: percent)) }
            else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: PanelLayout.ringDiameter, height: PanelLayout.ringDiameter)
            }
            else { Color.clear.frame(width: PanelLayout.ringDiameter, height: PanelLayout.ringDiameter) }
            Spacer().frame(width: PanelLayout.ringLabelGap)
            Text(label).foregroundColor(.secondary).lineLimit(1).fixedSize().reportFrame(id + ".label")
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .reportFrame(id + ".value")
        }
        .font(.system(size: 13))
        .frame(height: 22)
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 4) {
            Row(id: "mem", label: "内存",
                value: formatUsageRow(used: model.memUsed, total: model.memTotal, unit: Units.gib),
                percent: percentOf(used: model.memUsed, total: model.memTotal))
            Row(id: "cpu", label: "CPU", value: formatCPUTitle(percent: model.cpu), percent: model.cpu)
            Row(id: "disk", label: "磁盘",
                value: model.disk.map { formatUsageRow(used: $0.used, total: $0.total, unit: Units.gb) } ?? "—",
                percent: model.disk?.percent ?? 0)
            Row(id: "net", label: "网络", value: formatNetRow(model.net), percent: nil, symbol: "arrow.up.arrow.down")
            if let b = model.battery {
                Row(id: "bat", label: "电池", value: batteryPanelValue(b), percent: clampPercent(b.percent))
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 10)
        .frame(width: PanelLayout.width)
        .coordinateSpace(name: "panel")
        .onPreferenceChange(FrameKey.self) { model.frames = $0 }
    }
}

/// 鼠标进出转发器（状态栏按钮与面板各一个）。
final class HoverTracker: NSResponder {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// 不抢焦点的悬浮面板（NSPanel + SwiftUI 内容）。
final class HoverPanel: NSPanel {
    /// 面板自身的鼠标进出，交给 HoverDebouncer。
    let tracker = HoverTracker()

    init(model: PanelModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 300),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        // v0.1.11：用 maskImage 裁圆角（窗口阴影与背景都跟着圆角走）。
        // 旧版只给 layer 设 cornerRadius，窗口本身仍是方的，左下/右下角会露出方形底。
        effect.maskImage = HoverPanel.roundedMask(radius: 10)
        let host = NSHostingView(rootView: PanelView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        effect.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                              owner: tracker, userInfo: nil))
        contentView = effect
        setContentSize(host.fittingSize)
    }
    override var canBecomeKey: Bool { false }

    /// 可拉伸的圆角蒙版（capInsets 保证任意尺寸下圆角不变形）。
    static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    /// 放在状态栏按钮正下方，水平居中并夹在屏幕可见区域内。
    func show(below button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        if let host = contentView?.subviews.first { setContentSize(host.fittingSize) }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        var x = b.midX - frame.width / 2
        let y = b.minY - frame.height - 4
        if let vf = (bw.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vf.minX + 4), vf.maxX - frame.width - 4)
        }
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
        invalidateShadow()   // 阴影按圆角遮罩重算
    }
}
