import AppKit
import SwiftUI
import Combine

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
    // v0.1.12 卡片
    @Published var page = 0
    // v0.1.14 设置卡（隐藏卡，不进翻页和页码点）
    @Published var showSettings = false
    @Published var loginEnabled = false
    @Published var warningThresholds = UsageWarningThresholds()
    var onWarningThresholdChange: ((UsageWarningThresholds) -> Void)?
    var cpuWarning: Bool { warningThresholds.cpuWarning(cpu) }
    var memoryWarning: Bool { warningThresholds.memoryWarning(used: memUsed, total: memTotal) }

    func setWarningThresholds(_ value: UsageWarningThresholds) {
        guard warningThresholds != value else { return }
        warningThresholds = value
        onWarningThresholdChange?(value)
    }
    var version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    var onToggleLogin: ((Bool) -> Void)?
    var onCheckUpdates: (() -> Void)?
    @Published var cpuSplitNow = CPUSplit(system: 0, user: 0, idle: 100)
    @Published var cpuHistory = History<CPUSplit>()
    @Published var memHistory = History<Double>()
    @Published var memCached: UInt64 = 0
    @Published var swapUsed: UInt64 = 0
    var cards: [String] { cardIDs(hasBattery: battery != nil) }
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
    var warning = false
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
                .foregroundColor(warning ? Color(nsColor: .systemRed) : .primary)
                .lineLimit(1)
                .fixedSize()
                .reportFrame(id + ".value")
        }
        .font(.system(size: 13))
        .frame(height: 22)
    }
}

/// 总览标题行右侧的「⚙ 设置」（图标 + 文字，参照栏历）。
/// 胶囊按钮（契约 C1）：22pt 高，左右 9pt，底色白 8%，悬停白 15%，手型光标。
struct CapsuleButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.primary.opacity(hover ? 0.15 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct SettingsEntry: View {
    let action: () -> Void
    var body: some View {
        CapsuleButton(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "gearshape").font(.system(size: 12))
                Text("设置")
            }
        }
    }
}

struct OverviewCard: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("总览").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                SettingsEntry { model.showSettings = true }
            }
            .frame(height: CardLayout.headerHeight)
            .padding(.bottom, CardLayout.headerGap - 4)

            Row(id: "mem", label: "内存",
                value: formatUsageRow(used: model.memUsed, total: model.memTotal, unit: Units.gib),
                percent: percentOf(used: model.memUsed, total: model.memTotal), warning: model.memoryWarning)
            Row(id: "cpu", label: "CPU", value: formatCPUTitle(percent: model.cpu), percent: model.cpu, warning: model.cpuWarning)
            Row(id: "disk", label: "磁盘",
                value: model.disk.map { formatUsageRow(used: $0.used, total: $0.total, unit: Units.gb) } ?? "—",
                percent: model.disk?.percent ?? 0)
            Row(id: "net", label: "网络", value: formatNetRow(model.net), percent: nil, symbol: "arrow.up.arrow.down")
            if let b = model.battery {
                Row(id: "bat", label: "电池", value: batteryPanelValue(b), percent: clampPercent(b.percent))
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, CardLayout.overviewBottomGap)
        .frame(width: PanelLayout.width)
        .coordinateSpace(name: "panel")
        .onPreferenceChange(FrameKey.self) { model.frames = $0 }
    }
}

// MARK: v0.1.12 卡片

/// 卡片标题行：左标题（13pt 中粗），右数值（次要色、等宽数字）。
struct CardHeader: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12).monospacedDigit()).foregroundColor(.secondary).lineLimit(1).fixedSize()
        }
        .frame(height: CardLayout.headerHeight)
    }
}

/// 底行一项：色点 + 标签 + 数值。
struct Legend: View {
    let color: Color?
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 3) {
            if let color { Circle().fill(color).frame(width: 6, height: 6) }
            Text(label).foregroundColor(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 10.5))
        .lineLimit(1)
        .fixedSize()
    }
}

/// 曲线：固定 120 个槽，最新的点在最右；纵轴 0–100。layers 由下往上叠。
struct Chart: View {
    let layers: [[Double]]     // 每层同长度，值为该层自身的占比
    let colors: [Color]
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let n = layers.first?.count ?? 0
            let step = chartStep(width: w, count: n)   // 未满时已有点铺满宽度（0.1.16）
            let x0 = w - Double(max(0, n - 1)) * step
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06))
                ForEach(0..<3) { i in
                    Path { p in let y = h * Double(i + 1) / 4; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                if n > 1 {
                    ForEach(Array(layers.indices.reversed()), id: \.self) { li in
                        let top = (0..<n).map { i in (0...li).reduce(0.0) { $0 + layers[$1][i] } }
                        let bottom = (0..<n).map { i in li == 0 ? 0 : (0..<li).reduce(0.0) { $0 + layers[$1][i] } }
                        let pt: (Int, Double) -> CGPoint = { i, v in CGPoint(x: x0 + Double(i) * step, y: h - h * min(100, max(0, v)) / 100) }
                        Path { p in
                            p.move(to: pt(0, top[0]))
                            for i in 1..<n { p.addLine(to: pt(i, top[i])) }
                            for i in stride(from: n - 1, through: 0, by: -1) { p.addLine(to: pt(i, bottom[i])) }
                            p.closeSubpath()
                        }
                        .fill(colors[li].opacity(0.55))
                        Path { p in
                            p.move(to: pt(0, top[0]))
                            for i in 1..<n { p.addLine(to: pt(i, top[i])) }
                        }
                        .stroke(colors[li], lineWidth: 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct MemCard: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 6) {
            CardHeader(title: "内存", value: String(format: "%.1f / %.0f G · %d%%",
                Double(model.memUsed) / Units.gib, Double(model.memTotal) / Units.gib,
                percentOf(used: model.memUsed, total: model.memTotal)))
            Chart(layers: [model.memHistory.values], colors: [.green])
            HStack {
                Legend(color: .green, label: "已使用", value: formatGiB1(model.memUsed))
                Spacer(minLength: 4)
                Legend(color: nil, label: "已缓存", value: formatGiB1(model.memCached))
                Spacer(minLength: 4)
                Legend(color: nil, label: "交换", value: formatGiB1(model.swapUsed))
            }
        }
    }
}

struct CPUCard: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        let s = model.cpuSplitNow
        VStack(spacing: 6) {
            CardHeader(title: "CPU", value: formatCPUTitle(percent: model.cpu))
            Chart(layers: [model.cpuHistory.values.map(\.system), model.cpuHistory.values.map(\.user)], colors: [.red, .blue])
            HStack {
                Legend(color: .red, label: "系统", value: String(format: "%.1f%%", s.system))
                Spacer(minLength: 4)
                Legend(color: .blue, label: "用户", value: String(format: "%.1f%%", s.user))
                Spacer(minLength: 4)
                Legend(color: nil, label: "闲置", value: String(format: "%.1f%%", s.idle))
            }
        }
    }
}

struct BigLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Text(value).monospacedDigit()
        }
        .lineLimit(1)
    }
}

struct DiskCard: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        let d = model.disk
        VStack(spacing: 6) {
            CardHeader(title: "磁盘", value: d.map { "\($0.percent)%" } ?? "—")
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 9)
                    Circle().trim(from: 0, to: Double(d?.percent ?? 0) / 100)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                    Text(d.map { "\($0.percent)%" } ?? "—").font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
                .padding(4.5)
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    BigLine(label: "已用", value: d.map { formatGB1($0.used) } ?? "—")
                    BigLine(label: "可用", value: d.map { formatGB1($0.available) } ?? "—")
                    BigLine(label: "共", value: d.map { formatGB1($0.total) } ?? "—")
                }
                .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 网络卡（契约 092b11e，参考 Clash Verge）：上传橙、下载蓝两块等宽小卡。
struct RateTile: View {
    let arrow: String
    let label: String
    let rate: Double
    let color: Color
    var body: some View {
        let r = splitRate(rate)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(color)
                    Text(arrow).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                }
                .frame(width: 22, height: 22)
                Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(r.number).font(.system(size: 20, weight: .semibold).monospacedDigit())
                Text(r.unit).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

struct NetCard: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 6) {
            CardHeader(title: "网络", value: "")
            HStack(spacing: 8) {
                RateTile(arrow: "↑", label: "上传", rate: model.net.up, color: Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255))
                RateTile(arrow: "↓", label: "下载", rate: model.net.down, color: .accentColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 大电池：填充按电量，充电时中间一个闪电，低电量红色（同菜单栏规则）。
struct BigBattery: View {
    let state: BatteryState
    var body: some View {
        let spec = batteryIconSpec(state)
        let w: CGFloat = 64, h: CGFloat = 30
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.55), lineWidth: 2)
                RoundedRectangle(cornerRadius: 3)
                    .fill(spec.isLowRed ? Color.red : (state.isCharging || state.onAC ? Color.green : Color.primary.opacity(0.75)))
                    .frame(width: max(0, (w - 8) * spec.fillFraction))
                    .padding(4)
                if state.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white).shadow(radius: 1)
                        .frame(width: w, height: h)
                }
            }
            .frame(width: w, height: h)
            RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.55)).frame(width: 3, height: 10)
        }
    }
}

struct BatCard: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(spacing: 6) {
            CardHeader(title: "电池", value: model.battery.map(batteryStatusText) ?? "")
            HStack(spacing: 16) {
                if let b = model.battery {
                    BigBattery(state: b)
                    Text("\(clampPercent(b.percent))%").font(.system(size: 24, weight: .medium).monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: CardLayout.dotSpacing) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(Color.primary.opacity(i == index ? 0.9 : 0.25))
                    .frame(width: CardLayout.dotSize, height: CardLayout.dotSize)
            }
        }
        .frame(height: CardLayout.dotAreaHeight)
        .padding(.bottom, CardLayout.dotBottomPadding)
    }
}

/// v0.1.12 面板：同尺寸卡片横排，按 page 平移；底部页码点只做指示。
struct PanelView: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        let cards = model.cards
        let h = CardLayout.overviewHeight(rows: cards.count - 1)
        let w = PanelLayout.width
        VStack(spacing: 0) {
            if model.showSettings {
                SettingsCard(model: model).frame(width: w, height: h, alignment: .top)
                PageDots(count: cards.count, index: model.page).hidden()   // 设置卡不算页，只占位保持面板尺寸
            } else {
                HStack(spacing: 0) {
                    ForEach(cards, id: \.self) { id in
                        card(id).frame(width: w, height: h, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(min(model.page, cards.count - 1)) * w)
                .animation(.easeInOut(duration: CardLayout.animation), value: model.page)
                .frame(width: w, height: h, alignment: .leading)
                .clipped()
                PageDots(count: cards.count, index: model.page)
            }
        }
        .frame(width: w)
    }

    @ViewBuilder private func card(_ id: String) -> some View {
        switch id {
        case "overview": OverviewCard(model: model)
        case "mem": MemCard(model: model).padding(.horizontal, PanelLayout.horizontalPadding).padding(.vertical, 10)
        case "cpu": CPUCard(model: model).padding(.horizontal, PanelLayout.horizontalPadding).padding(.vertical, 10)
        case "disk": DiskCard(model: model).padding(.horizontal, PanelLayout.horizontalPadding).padding(.vertical, 10)
        case "net": NetCard(model: model).padding(.horizontal, PanelLayout.horizontalPadding).padding(.vertical, 10)
        default: BatCard(model: model).padding(.horizontal, PanelLayout.horizontalPadding).padding(.vertical, 10)
        }
    }
}

/// 设置卡：左上「‹ 返回」，内容可垂直滚动。
struct SettingsCard: View {
    @ObservedObject var model: PanelModel

    private func thresholdRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value.wrappedValue)%").monospacedDigit().foregroundColor(.secondary)
            Stepper(label, value: value, in: UsageWarningThresholds.range, step: 1)
                .labelsHidden().controlSize(.small)
                .accessibilityValue(Text("\(value.wrappedValue)%"))
        }
        .frame(height: 30)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Text("设置").font(.system(size: 13, weight: .semibold))   // 按整张卡宽度居中（契约 17dcf41）
                HStack {
                    CapsuleButton(action: { model.showSettings = false }) { Text("‹ 返回") }
                    Spacer()
                }
            }
            .frame(height: CardLayout.headerHeight)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack {
                        Text("开机自启动")
                        Spacer()
                        Toggle("", isOn: Binding(get: { model.loginEnabled },
                                                 set: { model.loginEnabled = $0; model.onToggleLogin?($0) }))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    }
                    .frame(height: 30)
                    Divider()
                    thresholdRow("CPU 警戒阈值", value: Binding(get: { model.warningThresholds.cpu }, set: {
                        model.setWarningThresholds(UsageWarningThresholds(cpu: $0, memory: model.warningThresholds.memory))
                    }))
                    Divider()
                    thresholdRow("内存警戒阈值", value: Binding(get: { model.warningThresholds.memory }, set: {
                        model.setWarningThresholds(UsageWarningThresholds(cpu: model.warningThresholds.cpu, memory: $0))
                    }))
                    Divider()
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(model.version).monospacedDigit().foregroundColor(.secondary)
                    }
                    .frame(height: 30)
                    Divider()
                    HStack {
                        Text("更新")
                        Spacer()
                        CapsuleButton(action: { model.onCheckUpdates?() }) { Text("检查更新") }
                    }
                    .frame(height: 30)
                }
                .font(.system(size: 13))
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 10)
    }
}

/// 吃掉面板上的滚动事件（不传给下面），交给翻页逻辑。
final class PanelHostingView: NSHostingView<PanelView> {
    var onScroll: ((NSEvent) -> Void)?
    var passThroughScroll: (() -> Bool)?
    override func scrollWheel(with event: NSEvent) {
        if passThroughScroll?() == true { super.scrollWheel(with: event) }   // 设置卡：交给 ScrollView 垂直滚动
        else { onScroll?(event) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // 不抢焦点的面板里按钮一次点中
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
    let model: PanelModel
    private(set) var pager = CardPager(count: 5)
    private var hostView: PanelHostingView!
    private var settingsSink: AnyCancellable?

    init(model: PanelModel) {
        self.model = model
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
        let host = PanelHostingView(rootView: PanelView(model: model))
        hostView = host
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
        host.onScroll = { [weak self] e in self?.handleScroll(e) }
        host.passThroughScroll = { [weak model] in model?.showSettings == true }
        // 设置卡开关同步给翻页：打开时锁翻页；「返回」回到总览。
        settingsSink = model.$showSettings.removeDuplicates().dropFirst().sink { [weak self] open in
            guard let self else { return }
            if open { self.pager.openSettings() }
            else {
                self.pager.closeSettings()
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { self.model.page = 0 }
            }
        }
    }

    /// 翻页：触控板横滑（有 phase）、鼠标滚轮竖滚（无 phase）。scrollingDelta 取反后正数 = 下一张。
    func handleScroll(_ e: NSEvent) {
        let phase: CardPager.Phase
        if e.momentumPhase != [] { phase = .momentum }
        else if e.phase.contains(.began) || e.phase.contains(.mayBegin) { phase = .began }
        else if e.phase.contains(.changed) { phase = .changed }
        else if e.phase.contains(.ended) || e.phase.contains(.cancelled) { phase = .ended }
        else { phase = .none }
        scroll(dx: -Double(e.scrollingDeltaX), dy: -Double(e.scrollingDeltaY), phase: phase, now: ProcessInfo.processInfo.systemUptime)  // 合成事件的 timestamp 为 0，统一用当前时钟
    }

    /// 合成事件走真实入口：托管视图的 scrollWheel。
    func hostScroll(_ e: NSEvent) { hostView.scrollWheel(with: e) }

    func scroll(dx: Double, dy: Double, phase: CardPager.Phase, now: Double) {
        pager.setCount(model.cards.count)
        if pager.scroll(dx: dx, dy: dy, phase: phase, now: now) { model.page = pager.index }
    }

    func resetPage(to i: Int = 0) {
        if model.showSettings { model.showSettings = false }
        pager.setCount(model.cards.count)
        pager.reset()
        for _ in 0..<i { _ = pager.scroll(dx: 0, dy: 1, phase: .none, now: Double(pager.index) * 10) }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { model.page = pager.index; model.showSettings = false }
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
