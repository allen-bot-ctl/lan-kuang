import AppKit
import SwiftUI
import ServiceManagement
import IOKit.ps
#if canImport(Sparkle)
import Sparkle
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statsItem: NSStatusItem!
    private let model = PanelModel()
    private lazy var panel = HoverPanel(model: model)
    private let hover = HoverTracker()
    private let debouncer = HoverDebouncer(now: { ProcessInfo.processInfo.systemUptime })
    private let debugOpenPanel = CommandLine.arguments.contains("--debug-open-panel")
    private let debugLongest = CommandLine.arguments.contains("--debug-longest")
    /// `--debug-battery=<状态,电量>`：CI 无电池时模拟 5 种状态。nil = 不覆盖。
    private let debugBattery: BatteryState?? = CommandLine.arguments
        .first { $0.hasPrefix("--debug-battery=") }
        .flatMap { parseDebugBattery(String($0.dropFirst("--debug-battery=".count))) }
    private var battery: BatteryState?
    private var memTitle = "0G"
    private var cpuTitle = "0%"
    private var netLines = ("↑0B", "↓0B")
    private var memSticky = StickyWidth(hold: 10), netSticky = StickyWidth(hold: 10)
    private var lastDrawKey = ""
    private var prevNet: [String: InterfaceCounters]?
    private var prevNetAt: TimeInterval = 0
    private let batteryLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let batteryLineSeparator = NSMenuItem.separator()

    private var gate = RefreshGate()
    private var prevTicks: CPUTicks?
    private var panelPrevTicks: CPUTicks?
    // v0.1.12：跟菜单栏同一节奏（2 秒）攒历史，面板没打开也在攒；只在面板可见时推给视图。
    private var cpuHistory = History<CPUSplit>()
    private var memHistory = History<Double>()
    private let debugPage = CommandLine.arguments.first { $0.hasPrefix("--debug-page=") }
        .flatMap { Int($0.dropFirst("--debug-page=".count)) }
    private var menuBarTimer: Timer?
    private var batteryTimer: Timer?
    private var panelTimer: Timer?
    private var diskTimer: Timer?
    private var graceTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private let contextMenu = NSMenu()
    private let loginItem = NSMenuItem(title: "开机自启动", action: #selector(toggleLoginItem), keyEquivalent: "")

    #if canImport(Sparkle)
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    func applicationDidFinishLaunching(_ n: Notification) {
        // `--debug-appearance=light|dark`：CI 截深浅两套卡片。
        if let a = CommandLine.arguments.first(where: { $0.hasPrefix("--debug-appearance=") }) {
            NSApp.appearance = NSAppearance(named: a.hasSuffix("light") ? .aqua : .darkAqua)
        }
        // `--debug-render-cards=<目录>`：离屏渲染每张卡片（深/浅各一套 2x）后退出，CI 与本机核对用。
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--debug-render-cards=") }) {
            let dir = URL(fileURLWithPath: String(arg.dropFirst("--debug-render-cards=".count)))
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let m = PanelModel()
            m.memUsed = UInt64(13.4 * Units.gib); m.memTotal = UInt64(16 * Units.gib); m.memCached = UInt64(4.2 * Units.gib)
            m.swapUsed = UInt64(1.1 * Units.gib); m.cpu = 23; m.cpuSplitNow = CPUSplit(system: 8.5, user: 14.5, idle: 77)
            m.disk = DiskUsage(total: 500_000_000_000, available: 180_000_000_000)
            m.net = NetRate(up: 6.4 * 1024, down: 999 * 1024)
            m.battery = parseDebugBattery("charging,62") ?? nil
            var ch = History<CPUSplit>(), mh = History<Double>()
            for i in 0..<120 { let t = Double(i) / 9
                ch.append(CPUSplit(system: 6 + 4 * sin(t), user: 14 + 10 * sin(t * 1.7 + 1), idle: 0)); mh.append(80 + 3 * sin(t / 2)) }
            m.cpuHistory = ch; m.memHistory = mh
            for ap in ["dark", "light"] {
                let appearance = NSAppearance(named: ap == "dark" ? .darkAqua : .aqua)!
                for pg in 0..<m.cards.count {
                    m.page = pg
                    appearance.performAsCurrentDrawingAppearance {
                        let v = PanelView(model: m).background(Color(nsColor: .windowBackgroundColor))
                            .environment(\.colorScheme, ap == "dark" ? .dark : .light)
                        let r = ImageRenderer(content: v); r.scale = 2
                        if let cg = r.cgImage {
                            let rep = NSBitmapImageRep(cgImage: cg)
                            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("card\(pg)-\(ap).png"))
                        }
                    }
                }
            }
            print("DEBUG_CARDS rendered=\(m.cards.count * 2)")
            exit(0)
        }
        // `--debug-render-icons=<目录>`：离屏 2x 渲染五种电池状态的菜单栏图像后退出（CI V1）。
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--debug-render-icons=") }) {
            let dir = URL(fileURLWithPath: String(arg.dropFirst("--debug-render-icons=".count)))
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let cases = ["ac,100", "charging,18", "battery,62", "battery,15", "none"]
            for c in cases {
                guard let st = parseDebugBattery(c) else { continue }
                let img = StatusRenderer.image(battery: batteryGlyphSpec(st), top: "13G", bottom: "25%", height: 24, net: ("↑2.1K", "↓205K"))
                let name = "icon2x-" + c.replacingOccurrences(of: ",", with: "-") + ".png"
                try? StatusRenderer.renderPNG(img, scale: 2, to: dir.appendingPathComponent(name))
                try? StatusRenderer.renderPNG(img, scale: 1, to: dir.appendingPathComponent(name.replacingOccurrences(of: "icon2x", with: "icon1x")))
                print("DEBUG_ICON \(name) width=\(img.size.width)")
            }
            // v0.1.7 S1/S2/S3：最长与短值各一组，打印实际间距和整项宽
            for (tag, t, b, n) in [("longest", "128G", "100%", netWidestLines), ("short", "13G", "73%", ("↑9.5K", "↓39K")),
                                    ("k205", "13G", "73%", ("↑2.1K", "↓205K"))] {
                let cols = (StatusRenderer.memActualWidth(top: t, bottom: b),
                            max(StatusRenderer.netActualWidth(up: n.0, down: n.1), StatusRenderer.netMinimumWidth))
                let img = StatusRenderer.image(battery: batteryGlyphSpec(parseDebugBattery("charging,18")!), top: t, bottom: b, height: 24, net: n, columns: cols)
                try? StatusRenderer.renderPNG(img, scale: 1, to: dir.appendingPathComponent("spacing1x-\(tag).png"))
                try? StatusRenderer.renderPNG(img, scale: 2, to: dir.appendingPathComponent("spacing2x-\(tag).png"))
                let g = StatusRenderer.lastGaps
                print("DEBUG_SPACING \(tag) width=\(img.size.width) battery_text=\(g.0) text_arrow=\(g.1) arrow_num=\(g.2) right_slack=\(String(format: "%.1f", g.3))")
            }
            let variants: [(String, CGFloat, NSFont.Width)] = [("std10", 10, .standard), ("std9.5", 9.5, .standard),
                ("std9", 9, .standard), ("cond10", 10, .condensed), ("cond9.5", 9.5, .condensed)]
            for (tag, size, w) in variants {
                StatusRenderer.fontOverride = (size, w)
                for c in ["ac-100", "charging-18"] {
                    let st = parseDebugBattery(c.replacingOccurrences(of: "-", with: ","))!
                    let img = StatusRenderer.image(battery: batteryGlyphSpec(st), top: "128G", bottom: "100%", height: 24)
                    try? StatusRenderer.renderPNG(img, scale: 1, to: dir.appendingPathComponent("font1x-\(tag)-\(c).png"))
                    try? StatusRenderer.renderPNG(img, scale: 2, to: dir.appendingPathComponent("font2x-\(tag)-\(c).png"))
                    if c == "ac-100" { print("DEBUG_FONT \(tag) item_width=\(img.size.width) text=\(StatusRenderer.textColumnWidth)") }
                }
            }
            exit(0)
        }
        let idBase = Bundle.main.bundleIdentifier ?? "app"
        // 只有一个菜单栏项；新的 autosaveName，避免与 0.1.0/0.1.1 两项的位置冲突。
        statsItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statsItem.autosaveName = idBase + ".single"
        if let b = statsItem.button {
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageOnly
        }

        if let b = statsItem.button {
            b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                             owner: hover, userInfo: nil))
        }
        hover.onEnter = { [weak self] in self?.hoverEvent(.itemEnter) }
        hover.onExit = { [weak self] in self?.hoverEvent(.itemExit) }
        panel.tracker.onEnter = { [weak self] in self?.hoverEvent(.panelEnter) }
        panel.tracker.onExit = { [weak self] in self?.hoverEvent(.panelExit) }

        buildMenu()
        observeSleepAndLock()
        startPowerNotifications()
        resume()

        if debugOpenPanel {   // CI 截图用的隐藏参数：启动 2 秒后打开面板并保持
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.model.debugLongest = CommandLine.arguments.contains("--debug-longest")
                self.debouncer.handle(.click)
                self.applyHoverState()
                if let p = self.debugPage { self.panel.resetPage(to: p) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.printDebugGeometry() }
                if CommandLine.arguments.contains("--debug-scroll-test") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runScrollTest() }
                }
            }
        }
    }

    /// CI：合成真实的滚动事件（CGEvent → NSEvent）发给面板，验证翻页：鼠标滚轮竖滚、触控板横滑（带 phase），到头不越界。
    private func runScrollTest() {
        let last = model.cards.count - 1
        func wheel(_ lines: Int32) -> NSEvent {
            let c = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
            return NSEvent(cgEvent: c)!
        }
        func pad(_ dx: Int32, _ phase: Int64) -> NSEvent {
            let c = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0)!
            c.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            c.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)   // 1 began 2 changed 4 ended
            return NSEvent(cgEvent: c)!
        }
        func swipe(_ dx: Int32) -> [NSEvent] { [pad(dx / 4, 1), pad(dx / 2, 2), pad(dx, 2), pad(dx, 2), pad(0, 4)] }
        // (事件组, 期望页)。滚轮向下 / 手指向左 = 下一张。
        let steps: [(String, [NSEvent], Int)] = [
            ("wheel-up-at-first", [wheel(3)], 0),
            ("wheel-down", [wheel(-1)], 1),
            ("wheel-down", [wheel(-1)], 2),
            ("swipe-left", swipe(-40), 3),
            ("swipe-right", swipe(40), 2),
            ("swipe-left", swipe(-40), 3),
        ] + (0..<8).map { _ in ("wheel-down-past-end", [wheel(-1)], min(last, 99)) }
          + (0..<8).map { _ in ("wheel-up-to-first", [wheel(1)], 0) }
        var results: [String] = []
        var ok = true
        func run(_ i: Int) {
            guard i < steps.count else {
                print("DEBUG_SCROLL cards=\(model.cards.count) " + results.joined(separator: " ") + " ok=\(ok)")
                fflush(stdout); return
            }
            let (name, events, want) = steps[i]
            for e in events { panel.hostScroll(e) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                let got = model.page
                // 「到头」的一串只检查最后一步
                let check = !(name.hasSuffix("past-end") || name.hasSuffix("to-first")) || i == steps.count - 1 || steps[i + 1].0 != name
                if check && got != want { ok = false }
                if check { results.append("\(name)=\(got)") }
                run(i + 1)
            }
        }
        run(0)
    }

    // MARK: 菜单

    private func buildMenu() {
        let update = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        loginItem.target = self
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? ""
        let quit = NSMenuItem(title: "退出" + displayName, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        batteryLineItem.isEnabled = false
        contextMenu.autoenablesItems = false
        contextMenu.items = [batteryLineItem, batteryLineSeparator, update, loginItem, .separator(), quit]
        contextMenu.delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let line = batteryMenuLine(battery)
        batteryLineItem.title = line ?? ""
        batteryLineItem.isHidden = line == nil
        batteryLineSeparator.isHidden = line == nil
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRight {
            debouncer.forceHide()
            hidePanel()
            statsItem.menu = contextMenu
            sender.performClick(nil)
            statsItem.menu = nil
        } else {
            debouncer.handle(.click)
            applyHoverState()
        }
    }

    @objc private func checkForUpdates() {
        #if canImport(Sparkle)
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates(nil)
        #endif
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("开机自启动切换失败: \(error.localizedDescription)")
        }
    }

    // MARK: 面板

    private func hoverEvent(_ e: HoverDebouncer.Event) {
        if debugOpenPanel { return }
        debouncer.handle(e)
        applyHoverState()
        if debouncer.closeDeadline != nil {
            graceTimer?.invalidate()
            graceTimer = Timer.scheduledTimer(withTimeInterval: debouncer.grace + 0.02, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.debouncer.tick()
                self.applyHoverState()
            }
        }
    }

    private func applyHoverState() {
        if debouncer.isShown && !panel.isVisible { showPanel() }
        if !debouncer.isShown && panel.isVisible { hidePanel() }
    }

    private func showPanel() {
        guard let b = statsItem.button else { return }
        refreshPanel()
        refreshDisk()
        pushHistory()
        panel.resetPage()   // 每次打开都从总览开始
        panel.show(below: b)
        startPanelTimers()
    }

    private func hidePanel() {
        graceTimer?.invalidate(); graceTimer = nil
        panelTimer?.invalidate(); panelTimer = nil
        diskTimer?.invalidate(); diskTimer = nil
        panelPrevTicks = nil
        panel.orderOut(nil)
    }

    private func startPanelTimers() {
        guard gate.isActive else { return }
        if panelTimer == nil { panelTimer = repeating(Refresh.panel) { [weak self] in self?.refreshPanel() } }
        if diskTimer == nil { diskTimer = repeating(Refresh.disk) { [weak self] in self?.refreshDisk() } }
    }

    private func refreshPanel() {
        let t = Sampler.cpuTicks()
        if let p = panelPrevTicks ?? prevTicks {
            model.cpu = cpuPercent(previous: p, current: t)
            model.cpuSplitNow = cpuSplit(previous: p, current: t)
        }
        panelPrevTicks = t
        if model.debugLongest {
            model.memUsed = UInt64(128 * Units.gib); model.memTotal = UInt64(128 * Units.gib); model.cpu = 100
            return
        }
        model.memUsed = Sampler.memoryUsedBytes()
        model.memTotal = Sampler.memoryTotalBytes
        model.memCached = Sampler.memoryCachedBytes()
        model.swapUsed = Sampler.swapUsedBytes()
    }

    private func refreshDisk() {
        model.disk = model.debugLongest ? DiskUsage(total: 4_000_000_000_000, available: 1_000_000_000) : Sampler.disk()
    }

    /// CI 用：输出截图区域（左上原点、点）、backingScaleFactor 与面板布局自检。
    private func printDebugGeometry() {
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        func top(_ r: NSRect) -> String {
            "\(Int(r.minX.rounded(.down))),\(Int((screenH - r.maxY).rounded(.down))),\(Int(r.width.rounded(.up))),\(Int(r.height.rounded(.up)))"
        }
        let scale = panel.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let bf = statsItem.button?.window?.frame ?? .zero
        let menubar = NSRect(x: bf.minX - 160, y: bf.minY, width: bf.width + 320, height: bf.height)
        print("DEBUG_SCALE \(scale)")
        print("DEBUG_ITEM_WIDTH \(statsItem.length) max=\(StatusItemLayout.maxWidth) text=\(StatusRenderer.textColumnWidth) net=\(StatusRenderer.netColumnWidth)")
        let nc = Sampler.interfaceCounters()
        print("DEBUG_NET " + nc.keys.sorted().map { "\($0)\(isPhysicalInterface($0) ? "*" : "")=\(nc[$0]!.rx)/\(nc[$0]!.tx)" }.joined(separator: " "))
        print("DEBUG_RECT_ITEM " + top(bf.insetBy(dx: -4, dy: 0)))
        print("DEBUG_RECT_MENUBAR " + top(menubar))
        print("DEBUG_RECT_PANEL " + top(panel.frame.insetBy(dx: -8, dy: -8)))
        let f = model.frames
        let ids = ["mem", "cpu", "disk", "net"] + (model.battery == nil ? [] : ["bat"])
        let lmin = ids.map { Double(f[$0 + ".label"]?.minX ?? -1) }
        let lmax = ids.map { Double(f[$0 + ".label"]?.maxX ?? -1) }
        let vmin = ids.map { Double(f[$0 + ".value"]?.minX ?? -1) }
        let vmax = ids.map { Double(f[$0 + ".value"]?.maxX ?? -1) }
        let ok = layoutAligned(labelMinX: lmin, labelMaxX: lmax, valueMinX: vmin, valueMaxX: vmax)
        print("DEBUG_LAYOUT labelMinX=\(lmin) valueMaxX=\(vmax) ok=\(ok)")
        fflush(stdout)
    }

    // MARK: 菜单栏刷新

    private func repeating(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    private func refreshStats() {
        let t = Sampler.cpuTicks()
        let cpu = prevTicks.map { cpuPercent(previous: $0, current: t) } ?? 0
        if let p = prevTicks { cpuHistory.append(cpuSplit(previous: p, current: t)) }
        prevTicks = t
        let memUsedNow = Sampler.memoryUsedBytes()
        memHistory.append(Double(percentOf(used: memUsedNow, total: Sampler.memoryTotalBytes)))
        if panel.isVisible { pushHistory() }
        let nc = Sampler.interfaceCounters(), now = ProcessInfo.processInfo.systemUptime
        if let p = prevNet {
            let r = netRate(previous: p, current: nc, seconds: now - prevNetAt)
            netLines = formatNetLines(r); model.net = r
        }
        prevNet = nc; prevNetAt = now
        if debugLongest {   // CI：最长文案定宽检查
            memTitle = StatusItemLayout.widestLines.0; cpuTitle = StatusItemLayout.widestLines.1
            netLines = netWidestLines
            model.net = NetRate(up: 999 * 1024, down: 999 * 1024 * 1024)
        } else {
            memTitle = formatMemoryTitle(usedBytes: memUsedNow)
            cpuTitle = formatCPUTitle(percent: cpu)
        }
        redrawItem()
    }

    private func pushHistory() {
        model.cpuHistory = cpuHistory
        model.memHistory = memHistory
    }

    private func refreshBattery() {
        if let d = debugBattery { battery = d } else { battery = Sampler.battery() }
        if model.battery != battery { model.battery = battery }
        redrawItem()
    }

    private func redrawItem() {
        guard let b = statsItem.button else { return }
        let h = NSStatusBar.system.thickness
        let now = ProcessInfo.processInfo.systemUptime
        let memW = memSticky.update(actual: StatusRenderer.memActualWidth(top: memTitle, bottom: cpuTitle), now: now)
        let netW = netSticky.update(actual: StatusRenderer.netActualWidth(up: netLines.0, down: netLines.1),
                                    minimum: StatusRenderer.netMinimumWidth, now: now)
        let spec = batteryGlyphSpec(battery)
        let key = "\(String(describing: spec))|\(memTitle)|\(cpuTitle)|\(netLines)|\(memW)|\(netW)|\(h)"
        if key == lastDrawKey { return }   // 内容没变就不重绘，省 CPU
        lastDrawKey = key
        let img = StatusRenderer.image(battery: spec, top: memTitle, bottom: cpuTitle, height: h, net: netLines, columns: (memW, netW))
        statsItem.length = img.size.width
        b.image = img
        b.title = ""
    }

    private func resume() {
        guard gate.isActive else { return }
        prevTicks = nil; prevNet = nil
        refreshStats(); refreshBattery()
        if menuBarTimer == nil { menuBarTimer = repeating(Refresh.menuBar) { [weak self] in self?.refreshStats() } }
        if batteryTimer == nil { batteryTimer = repeating(Refresh.battery) { [weak self] in self?.refreshBattery() } }
        if panel.isVisible { startPanelTimers() }
    }

    private func pause() {
        for t in [menuBarTimer, batteryTimer, panelTimer, diskTimer] { t?.invalidate() }
        menuBarTimer = nil; batteryTimer = nil; panelTimer = nil; diskTimer = nil
    }

    private func updateGate(_ change: (inout RefreshGate) -> Void) {
        let wasActive = gate.isActive
        change(&gate)
        if wasActive && !gate.isActive { pause() }
        if !wasActive && gate.isActive { resume() }
    }

    // MARK: 睡眠 / 锁屏 / 电源通知

    private func observeSleepAndLock() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.updateGate { $0.systemAsleep = true } }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateGate { $0.systemAsleep = false } }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.updateGate { $0.screensAsleep = true } }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateGate { $0.screensAsleep = false } }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.updateGate { $0.screenLocked = true } }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.updateGate { $0.screenLocked = false } }
    }

    private func startPowerNotifications() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { if me.gate.isActive { me.refreshBattery() } }
        }
        if let src = IOPSNotificationCreateRunLoopSource(cb, ctx)?.takeRetainedValue() {
            powerSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
