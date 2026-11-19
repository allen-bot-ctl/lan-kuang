/// 悬停去抖状态机（C9）：时钟可注入，便于测试。
/// - 进入左项：立即显示，取消待收起。
/// - 离开左项 / 离开面板：若鼠标既不在左项也不在面板，开始 300ms 宽限；到期才收起。
/// - 宽限期内进入左项或面板：取消收起。
/// - 点击左项：切换显示。
public final class HoverDebouncer {
    public enum Event { case itemEnter, itemExit, panelEnter, panelExit, click }

    public let grace: Double
    private let now: () -> Double
    public private(set) var isShown = false
    public private(set) var closeDeadline: Double?
    private var inItem = false
    private var inPanel = false

    public init(grace: Double = 0.3, now: @escaping () -> Double) {
        self.grace = grace
        self.now = now
    }

    /// 处理事件，返回处理后的显示状态。
    @discardableResult
    public func handle(_ e: Event) -> Bool {
        switch e {
        case .itemEnter:
            inItem = true; closeDeadline = nil; isShown = true
        case .panelEnter:
            inPanel = true; closeDeadline = nil
        case .itemExit:
            inItem = false; armIfOutside()
        case .panelExit:
            inPanel = false; armIfOutside()
        case .click:
            isShown.toggle(); closeDeadline = nil
        }
        return isShown
    }

    /// 定时调用（宽限到期时）；到期且鼠标仍在外面则收起。返回显示状态。
    @discardableResult
    public func tick() -> Bool {
        if let d = closeDeadline, now() >= d, !inItem, !inPanel {
            isShown = false; closeDeadline = nil
        }
        return isShown
    }

    /// 外部强制关闭（右键菜单、锁屏等）。
    public func forceHide() { isShown = false; closeDeadline = nil; inPanel = false }

    private func armIfOutside() {
        if isShown && !inItem && !inPanel { closeDeadline = now() + grace }
    }
}
