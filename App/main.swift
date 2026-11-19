import AppKit
import ServiceManagement
import IOKit.ps
#if canImport(Sparkle)
import Sparkle
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var batteryItem: NSStatusItem!
    private var statsItem: NSStatusItem!
    private let model = PanelModel()
    private lazy var panel = HoverPanel(model: model)
    private let hover = HoverTracker()
    private let debouncer = HoverDebouncer(now: { ProcessInfo.processInfo.systemUptime })
    private let debugOpenPanel = CommandLine.arguments.contains("--debug-open-panel")

    private var gate = RefreshGate()
    private var prevTicks: CPUTicks?
    private var panelPrevTicks: CPUTicks?
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
        let idBase = Bundle.main.bundleIdentifier ?? "app"
        // 先创建的在右边：电池在右，内存/CPU 在左。
        batteryItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        batteryItem.autosaveName = idBase + ".battery"
        statsItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statsItem.autosaveName = idBase + ".stats"

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        for item in [statsItem!, batteryItem!] {
            guard let b = item.button else { continue }
            b.font = font
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        batteryItem.button?.imagePosition = .imageLeading
        // 左项按最长文案定宽，数字变化时宽度不跳。
        let widest = (statusTitleWidest as NSString).size(withAttributes: [.font: font]).width
        statsItem.length = ceil(widest) + 12

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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.printDebugGeometry() }
            }
        }
    }

    // MARK: 菜单

    private func buildMenu() {
        let update = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        loginItem.target = self
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? ""
        let quit = NSMenuItem(title: "退出" + displayName, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        contextMenu.items = [update, loginItem, .separator(), quit]
        contextMenu.delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRight || sender === batteryItem.button {
            debouncer.forceHide()
            hidePanel()
            let item = sender === batteryItem.button ? batteryItem! : statsItem!
            item.menu = contextMenu
            sender.performClick(nil)
            item.menu = nil
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
        if let p = panelPrevTicks { model.cpu = cpuPercent(previous: p, current: t) }
        else if let p = prevTicks { model.cpu = cpuPercent(previous: p, current: t) }
        panelPrevTicks = t
        if model.debugLongest {
            model.memUsed = UInt64(128 * Units.gib); model.memTotal = UInt64(128 * Units.gib); model.cpu = 100
            return
        }
        model.memUsed = Sampler.memoryUsedBytes()
        model.memTotal = Sampler.memoryTotalBytes
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
        print("DEBUG_RECT_MENUBAR " + top(menubar))
        print("DEBUG_RECT_PANEL " + top(panel.frame.insetBy(dx: -8, dy: -8)))
        let f = model.frames
        let ids = ["mem", "cpu", "disk"]
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
        prevTicks = t
        statsItem.button?.title = formatStatusTitle(memoryUsedBytes: Sampler.memoryUsedBytes(), cpuPercent: cpu)
    }

    private func refreshBattery() {
        guard let s = Sampler.battery() else { batteryItem.isVisible = false; return }
        batteryItem.isVisible = true
        batteryItem.button?.image = BatteryIcon.image(batteryIconSpec(s))
        batteryItem.button?.title = " " + batteryTitle(s)
        batteryItem.button?.toolTip = batteryStatusText(s)
    }

    private func resume() {
        guard gate.isActive else { return }
        prevTicks = nil
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
