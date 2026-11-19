import AppKit

/// 自绘电池图标：外框 + 按电量填充；⚡/插头以镂空方式叠在中间。
/// 非低电量时为 template 图（跟随菜单栏深浅色）；用电池且 ≤20% 时填充为红色（非 template）。
enum BatteryIcon {
    static let size = NSSize(width: 25, height: 12)

    static func image(_ spec: BatteryIconSpec) -> NSImage {
        let img = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 0.5, y: 0.5, width: 21.5, height: 11)
            let ink: NSColor = spec.isLowRed ? .labelColor : .black
            ink.setStroke()
            let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1
            outline.stroke()
            // 正极帽
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 23, y: 4, width: 1.6, height: 4), xRadius: 0.8, yRadius: 0.8).fill()
            // 电量填充
            let inner = body.insetBy(dx: 1.5, dy: 1.5)
            let w = max(spec.fillFraction > 0 ? 1.5 : 0, inner.width * CGFloat(spec.fillFraction))
            (spec.isLowRed ? NSColor.systemRed : NSColor.black).setFill()
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                         xRadius: 1.5, yRadius: 1.5).fill()
            // 叠加符号：镂空
            let symbolName: String?
            switch spec.overlay {
            case .bolt: symbolName = "bolt.fill"
            case .plug: symbolName = "powerplug.fill"
            case .none: symbolName = nil
            }
            if let name = symbolName,
               let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .black)) {
                let s = sym.size
                let r = NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height)
                sym.draw(in: r, from: .zero, operation: .destinationOut, fraction: 1)
            }
            return true
        }
        img.isTemplate = !spec.isLowRed
        return img
    }
}
