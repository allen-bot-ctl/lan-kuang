import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = 0
    @Published var cpu: Int = 0
    @Published var disk: DiskUsage?
}

struct Ring: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }
}

/// 一行：左标签（次要色），右数值（主色、等宽数字），不截断不换行。
struct Row<Leading: View>: View {
    let label: String
    let value: String
    @ViewBuilder var leading: Leading
    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(label).foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: 13))
        .frame(height: 22)
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 4) {
            Row(label: "内存", value: formatUsageRow(used: model.memUsed, total: model.memTotal, unit: Units.gib)) { EmptyView() }
            Row(label: "CPU", value: formatCPUTitle(percent: model.cpu)) { EmptyView() }
            Row(label: "磁盘", value: model.disk.map { formatUsageRow(used: $0.used, total: $0.total, unit: Units.gb) } ?? "—") {
                Ring(fraction: Double(model.disk?.percent ?? 0) / 100)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(width: 260)
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
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
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
    }
}
