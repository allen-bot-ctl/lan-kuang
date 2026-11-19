import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = 0
    @Published var cpu: Int = 0
    @Published var disk: DiskUsage?
}

struct CardShell<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

struct Ring: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 40, height: 40)
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 8) {
            CardShell(title: "内存") {
                HStack(alignment: .firstTextBaseline) {
                    Text(formatIntG(used: model.memUsed, total: model.memTotal, unit: Units.gib))
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    Spacer()
                    Text("\(percentOf(used: model.memUsed, total: model.memTotal))%")
                        .font(.system(size: 13).monospacedDigit()).foregroundColor(.secondary)
                }
                ProgressView(value: Double(percentOf(used: model.memUsed, total: model.memTotal)), total: 100)
            }
            CardShell(title: "CPU") {
                Text("\(clampPercent(model.cpu))%").font(.system(size: 18, weight: .semibold).monospacedDigit())
                ProgressView(value: Double(clampPercent(model.cpu)), total: 100)
            }
            CardShell(title: "磁盘（启动盘）") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.disk.map { formatIntG(used: $0.used, total: $0.total, unit: Units.gb) } ?? "—")
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        Text(model.disk.map { "已用 \($0.percent)%" } ?? "")
                            .font(.system(size: 12).monospacedDigit()).foregroundColor(.secondary)
                    }
                    Spacer()
                    Ring(fraction: Double(model.disk?.percent ?? 0) / 100)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
    }
}

/// 不抢焦点的悬浮面板（NSPanel + SwiftUI 内容）。
final class HoverPanel: NSPanel {
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
