import AppKit
import ServiceManagement
import IOKit.ps
#if canImport(Sparkle)
import Sparkle
#endif

/// 状态栏按钮的鼠标进出（hover 打开面板）。
final class HoverTracker: NSResponder {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var batteryItem: NSStatusItem!
    private var statsItem: NSStatusItem!
    private let model = PanelModel()
    private lazy var panel = HoverPanel(model: model)
    private let hover = HoverTracker()

    private var gate = RefreshGate()
    private var prevTicks: CPUTicks?
    private var panelPrevTicks: CPUTicks?
    private var menuBarTimer: Timer?
    private var batteryTimer: Timer?
    private var panelTimer: Timer?
    private var diskTimer: Timer?
    private var hoverCloseTimer: Timer?
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

        if let b = statsItem.button {
            b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                             owner: hover, userInfo: nil))
        }
        hover.onEnter = { [weak self] in self?.showPanel() }
        hover.onExit = { [weak self] in self?.scheduleHoverClose() }

        buildMenu()
        observeSleepAndLock()
        startPowerNotifications()
        resume()
    }

    // MARK: 菜单

    private func buildMenu() {
        let update = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        loginItem.target = self
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            hidePanel()
            let item = sender === batteryItem.button ? batteryItem! : statsItem!
            item.menu = contextMenu
            sender.performClick(nil)
            item.menu = nil
        } else {
            panel.isVisible ? hidePanel() : showPanel()
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

    private func showPanel() {
        guard let b = statsItem.button else { return }
        hoverCloseTimer?.invalidate()
        refreshPanel()
        refreshDisk()
        panel.show(below: b)
        startPanelTimers()
    }

    private func hidePanel() {
        hoverCloseTimer?.invalidate(); hoverCloseTimer = nil
        panelTimer?.invalidate(); panelTimer = nil
        diskTimer?.invalidate(); diskTimer = nil
        panelPrevTicks = nil
        panel.orderOut(nil)
    }

    /// 鼠标离开按钮后，只要既不在按钮上也不在面板上就关闭。
    private func scheduleHoverClose() {
        hoverCloseTimer?.invalidate()
        hoverCloseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.panel.isVisible else { self.hoverCloseTimer?.invalidate(); self.hoverCloseTimer = nil; return }
            let p = NSEvent.mouseLocation
            let inPanel = self.panel.frame.insetBy(dx: -6, dy: -6).contains(p)
            let inButton = self.statsItem.button?.window?.frame.contains(p) ?? false
            if !inPanel && !inButton { self.hidePanel() }
        }
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
        model.memUsed = Sampler.memoryUsedBytes()
        model.memTotal = Sampler.memoryTotalBytes
    }

    private func refreshDisk() { model.disk = Sampler.disk() }

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
