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
                x += CGFloat(L.glyphWidth + L.gap)
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

    /// 竖电池（v0.1.3）：本体 8×16 圆角 2、1pt 描边 60% 不透明；正极头朝上；填充区 5×13 从下往上。
    /// 接电时在填充上叠实心 ⚡，外圈先用 .clear 挖出 1.4pt 的空隙，满格时轮廓仍清楚。
    private static func drawBattery(_ spec: BatteryIconSpec, origin o: NSPoint, ink: NSColor) {
        let bw = CGFloat(L.glyphWidth), bh = CGFloat(L.bodyHeight)
        let outer = NSRect(x: o.x, y: o.y, width: bw, height: bh)
        let body = outer.insetBy(dx: 0.5, dy: 0.5)
        ink.withAlphaComponent(0.6).setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 1.5, yRadius: 1.5)
        outline.lineWidth = 1
        outline.stroke()
        ink.withAlphaComponent(0.6).setFill()
        let cw = CGFloat(L.capWidth), ch = CGFloat(L.capHeight)
        NSBezierPath(roundedRect: NSRect(x: outer.midX - cw / 2, y: outer.maxY + CGFloat(L.capGap), width: cw, height: ch),
                     xRadius: 0.6, yRadius: 0.6).fill()
        let fw = CGFloat(L.fillWidth), fmax = CGFloat(L.fillMaxHeight)
        let fillArea = NSRect(x: outer.midX - fw / 2, y: outer.midY - fmax / 2, width: fw, height: fmax)
        let h = CGFloat(spec.fillHeight)
        if h > 0 {
            (spec.isLowRed ? NSColor.systemRed : ink).setFill()
            NSBezierPath(roundedRect: NSRect(x: fillArea.minX, y: fillArea.minY, width: fw, height: h),
                         xRadius: min(1, h / 2), yRadius: min(1, h / 2)).fill()
        }
        if spec.bolt { drawBolt(center: NSPoint(x: outer.midX, y: outer.midY), ink: ink) }
    }

    /// ⚡ 约 3.8×10pt：先描 1.4pt 的 .clear 外圈（只在本体内部挖），再实心填充。
    private static func drawBolt(center c: NSPoint, ink: NSColor) {
        let w: CGFloat = 3.8, h: CGFloat = 10
        let x0 = c.x - w / 2, y0 = c.y - h / 2
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x0 + w * 0.70, y: y0 + h))          // 上尖
        p.line(to: NSPoint(x: x0, y: y0 + h * 0.42))
        p.line(to: NSPoint(x: x0 + w * 0.46, y: y0 + h * 0.42))
        p.line(to: NSPoint(x: x0 + w * 0.30, y: y0))              // 下尖
        p.line(to: NSPoint(x: x0 + w, y: y0 + h * 0.58))
        p.line(to: NSPoint(x: x0 + w * 0.54, y: y0 + h * 0.58))
        p.close()
        p.lineJoinStyle = .round
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let clip = NSRect(x: c.x - CGFloat(L.fillWidth) / 2 - 0.5, y: c.y - CGFloat(L.fillMaxHeight) / 2 - 0.5,
                          width: CGFloat(L.fillWidth) + 1, height: CGFloat(L.fillMaxHeight) + 1)
        NSBezierPath(rect: clip).addClip()
        ctx.compositingOperation = .clear
        p.lineWidth = 2.8   // 描边居中，外扩 1.4pt
        NSColor.black.setStroke()
        p.stroke()
        ctx.restoreGraphicsState()
        ink.setFill()
        p.fill()
    }

    /// 离屏按 scale 倍渲染菜单栏图像为 PNG（CI 用 2x 检查 ⚡ 是否清楚）。
    static func renderPNG(_ img: NSImage, scale: CGFloat, to url: URL) throws {
        let pw = Int(img.size.width * scale), ph = Int(img.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = img.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
