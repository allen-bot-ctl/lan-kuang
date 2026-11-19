import AppKit

/// 单项菜单栏图像：电池图形（可无）· 间距 · 两行 9pt 等宽数字文字（上内存、下 CPU）。
/// 非低电量时整张为 template 图（跟随深浅菜单栏）；用电池且 ≤20% 时填充为 systemRed，其余用 labelColor。
enum StatusRenderer {
    typealias L = StatusItemLayout

    /// 9pt semibold 窄体 + 等宽数字（kNumberSpacingType=6 / kMonospacedNumbersSelector=0），压缩项宽。
    static let font: NSFont = {
        let size = CGFloat(L.fontSize)
        let base = NSFont.systemFont(ofSize: size, weight: .semibold, width: .condensed)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
        ])
        return NSFont(descriptor: desc, size: size) ?? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }()

    /// 按最长文案得到的文字列宽。
    static var textColumnWidth: Double {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        let w1 = (L.widestLines.0 as NSString).size(withAttributes: a).width
        let w2 = (L.widestLines.1 as NSString).size(withAttributes: a).width
        return Double(ceil(max(w1, w2)))
    }

    static func width(hasBattery: Bool) -> CGFloat {
        CGFloat(L.width(textColumn: textColumnWidth, hasBattery: hasBattery))
    }

    static func image(battery: BatteryIconSpec?, top: String, bottom: String, height: CGFloat) -> NSImage {
        let size = NSSize(width: width(hasBattery: battery != nil), height: height)
        let red = battery?.isLowRed ?? false
        let img = NSImage(size: size, flipped: false) { _ in
            let ink: NSColor = red ? .labelColor : .black
            var x = CGFloat(L.sidePadding)
            if let spec = battery {
                drawBattery(spec, origin: NSPoint(x: x, y: (height - CGFloat(L.glyphHeight)) / 2), ink: ink)
                x += CGFloat(L.glyphWidth + L.capWidth + L.gap)
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let lh = CGFloat(L.lineHeight)
            let blockBottom = (height - lh * 2) / 2
            // draw(at:) 的点是文字框左下角；文字框高 ≈ ascender − descender，按 10pt 行高上下排
            let box = font.ascender - font.descender
            let adjust = (lh - box) / 2
            (bottom as NSString).draw(at: NSPoint(x: x, y: blockBottom + adjust), withAttributes: attrs)
            (top as NSString).draw(at: NSPoint(x: x, y: blockBottom + lh + adjust), withAttributes: attrs)
            return true
        }
        img.isTemplate = !red
        return img
    }

    private static func drawBattery(_ spec: BatteryIconSpec, origin o: NSPoint, ink: NSColor) {
        let body = NSRect(x: o.x + 0.5, y: o.y + 0.5, width: CGFloat(L.glyphWidth) - 1, height: CGFloat(L.glyphHeight) - 1)
        ink.setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        outline.stroke()
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.5, y: body.midY - 1.75, width: CGFloat(L.capWidth), height: 3.5),
                     xRadius: 0.75, yRadius: 0.75).fill()
        let inner = body.insetBy(dx: 1.5, dy: 1.5)
        let w = max(spec.fillFraction > 0 ? 1.5 : 0, inner.width * CGFloat(spec.fillFraction))
        (spec.isLowRed ? NSColor.systemRed : ink).setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                     xRadius: 1, yRadius: 1).fill()
        let name: String?
        switch spec.overlay {
        case .bolt: name = "bolt.fill"
        case .plug: name = "powerplug.fill"
        case .none: name = nil
        }
        guard let name else { return }
        // 先用稍大的同形符号挖出一圈描边空隙，再用墨色实心画符号本身：
        // 不论电量多少（填充是否盖到中间），⚡/插头都清晰可见。
        if let halo = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 7.5, weight: .black)) {
            let s = halo.size
            halo.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height),
                      from: .zero, operation: .destinationOut, fraction: 1)
        }
        if let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 6, weight: .black)) {
            let s = sym.size
            let r = NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height)
            let tinted = NSImage(size: s, flipped: false) { rect in
                sym.draw(in: rect)
                ink.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}
