import AppKit

/// 单项菜单栏图像：电池图形（可无）· 间距 · 两行 10pt 窄体等宽数字文字（上内存、下 CPU）。
/// 非低电量时整张为 template 图（跟随深浅菜单栏）；用电池且 ≤20% 时填充为 systemRed，其余用 labelColor。
enum StatusRenderer {
    typealias L = StatusItemLayout

    /// 10pt semibold 窄体 + 等宽数字（kNumberSpacingType=6 / kMonospacedNumbersSelector=0），压缩项宽。
    /// 调试用：离屏对比不同字号/字宽（仅 --debug-render-icons 设置）。
    static var fontOverride: (CGFloat, NSFont.Width)? = nil { didSet { cachedFont = nil } }
    private static var cachedFont: NSFont?
    static var font: NSFont {
        if let f = cachedFont { return f }
        let size = fontOverride?.0 ?? CGFloat(L.fontSize)
        let base = NSFont.systemFont(ofSize: size, weight: .semibold, width: fontOverride?.1 ?? .condensed)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
        ])
        let f = NSFont(descriptor: desc, size: size) ?? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        cachedFont = f
        return f
    }

    /// 按最长文案得到的文字列宽。
    static var textColumnWidth: Double {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        let w1 = (L.widestLines.0 as NSString).size(withAttributes: a).width
        let w2 = (L.widestLines.1 as NSString).size(withAttributes: a).width
        return Double(ceil(max(w1, w2)))
    }

    /// 第三列（网速）定宽：矢量箭头 + 间隙 + 最长数字（"999K"）。字体自带的 ↑ 有 8.2pt 宽，整项会到 77pt，所以箭头自己画。
    static let arrowWidth: CGFloat = 5, arrowGap: CGFloat = 1
    /// 调试：最近一次绘制的 电池→文字、文字→箭头、箭头→数字、右侧留白（pt）。
    static var lastGaps: (Double, Double, Double, Double) = (0, 0, 0, 0)
    static var netColumnWidth: Double {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        let w1 = (String(netWidestLines.0.dropFirst()) as NSString).size(withAttributes: a).width
        let w2 = (String(netWidestLines.1.dropFirst()) as NSString).size(withAttributes: a).width
        return Double(ceil(arrowWidth + arrowGap + max(w1, w2)))
    }

    /// 细箭头：竖线 + 两侧斜线，宽 arrowWidth、高 7pt，1.1pt 线宽。
    private static func drawArrow(up: Bool, x: CGFloat, midY: CGFloat, ink: NSColor) {
        let w = arrowWidth, h: CGFloat = 7, head: CGFloat = 2.6
        let cx = x + w / 2, top = midY + h / 2, bot = midY - h / 2
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: bot)); p.line(to: NSPoint(x: cx, y: top))
        if up {
            p.move(to: NSPoint(x: x + 0.4, y: top - head)); p.line(to: NSPoint(x: cx, y: top)); p.line(to: NSPoint(x: x + w - 0.4, y: top - head))
        } else {
            p.move(to: NSPoint(x: x + 0.4, y: bot + head)); p.line(to: NSPoint(x: cx, y: bot)); p.line(to: NSPoint(x: x + w - 0.4, y: bot + head))
        }
        p.lineWidth = 1.1; p.lineCapStyle = .round; p.lineJoinStyle = .round
        ink.setStroke(); p.stroke()
    }

    static func width(hasBattery: Bool, hasNet: Bool = true) -> CGFloat {
        CGFloat(L.width(textColumn: textColumnWidth, hasBattery: hasBattery, netColumn: hasNet ? netColumnWidth : 0))
    }

    /// v0.1.8：本次两行文字的实际列宽（不取整）。
    static func memActualWidth(top: String, bottom: String) -> Double {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        return Double(max((top as NSString).size(withAttributes: a).width, (bottom as NSString).size(withAttributes: a).width))
    }
    static func netActualWidth(up: String, down: String) -> Double {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        let n1 = (String(up.drop(while: { $0 == "↑" || $0 == "↓" })) as NSString).size(withAttributes: a).width
        let n2 = (String(down.drop(while: { $0 == "↑" || $0 == "↓" })) as NSString).size(withAttributes: a).width
        return Double(arrowWidth + arrowGap + max(n1, n2))
    }
    /// 网速列的最小宽度：按 `99K`。
    static var netMinimumWidth: Double { netActualWidth(up: "↑99K", down: "↓99K") }

    static func image(battery: BatteryIconSpec?, top: String, bottom: String, height: CGFloat,
                      net: (String, String)? = nil, columns: (mem: Double, net: Double)? = nil) -> NSImage {
        // columns 给定时整项宽度贴合这两列（v0.1.8 防抖后的宽度），否则按最长文案定宽（调试字体对比用）
        var w = width(hasBattery: battery != nil, hasNet: net != nil)
        if let c = columns {
            let batteryPart: Double = battery != nil ? L.glyphWidth + L.gap : 0
            let netPart: Double = net != nil ? L.columnGap + c.net : 0
            let total: Double = L.sidePadding * 2 + batteryPart + c.mem + netPart
            w = CGFloat(total.rounded(.up))
        }
        let size = NSSize(width: w, height: height)
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
            if let (up, down) = net {   // v0.1.7：网速列紧跟本次第二列实际最宽行的右缘 3pt，箭头 1pt 数字，一体左对齐；多余空白留在最右
                let memW = max((top as NSString).size(withAttributes: attrs).width, (bottom as NSString).size(withAttributes: attrs).width)
                let nx = x + memW + CGFloat(L.columnGap)
                let rows: [(String, CGFloat, Bool)] = [(down, blockBottom, false), (up, blockBottom + lh, true)]
                for (text, y, isUp) in rows {
                    let num = String(text.drop(while: { $0 == "↑" || $0 == "↓" }))
                    (num as NSString).draw(at: NSPoint(x: nx + arrowWidth + arrowGap, y: y + adjust), withAttributes: attrs)
                    drawArrow(up: isUp, x: nx, midY: y + adjust - font.descender + font.capHeight / 2, ink: ink)
                }
                lastGaps = (Double(L.gap), Double(L.columnGap), Double(arrowGap), Double(size.width - (nx + arrowWidth + arrowGap + max((String(up.dropFirst()) as NSString).size(withAttributes: attrs).width, (String(down.dropFirst()) as NSString).size(withAttributes: attrs).width))))
            }
            return true
        }
        img.isTemplate = !red
        return img
    }

    /// 竖电池（v0.1.3）：本体 11×14 圆角 2（含正极头总高 16）、1pt 描边不透明；正极头朝上；填充区 8×10 从下往上。
    /// 接电时在填充上叠实心 ⚡，外圈先用 .clear 挖出 1pt 的空隙，满格时轮廓仍清楚。
    private static func drawBattery(_ spec: BatteryIconSpec, origin o: NSPoint, ink: NSColor) {
        let bw = CGFloat(L.glyphWidth), bh = CGFloat(L.bodyHeight)
        let outer = NSRect(x: o.x, y: o.y, width: bw, height: bh)
        let sw = CGFloat(L.strokeWidth)
        let body = outer.insetBy(dx: sw / 2, dy: sw / 2)
        ink.setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 1.5, yRadius: 1.5)
        outline.lineWidth = sw
        outline.stroke()
        ink.setFill()
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

    /// ⚡ 约 4.5×8pt：先描 1pt 的 .clear 外圈（只在本体内部挖），再实心填充。
    private static func drawBolt(center c: NSPoint, ink: NSColor) {
        let w: CGFloat = 4.5, h: CGFloat = 8
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
        p.lineWidth = 2   // 描边居中，外扩 1pt（填充区只有 5pt 宽，1.4pt 会把 45% 的电量挖没）
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
