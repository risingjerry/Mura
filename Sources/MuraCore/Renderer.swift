import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One display's pixel canvas plus the strips macOS covers (menu bar on top, Dock at the bottom).
public struct Canvas: Codable, Equatable {
    public var id: String
    public var width: Int
    public var height: Int
    public var safeTop: Int
    public var safeBottom: Int

    public init(id: String, width: Int, height: Int, safeTop: Int = 0, safeBottom: Int = 0) {
        self.id = id
        self.width = width
        self.height = height
        self.safeTop = safeTop
        self.safeBottom = safeBottom
    }
}

/// Excalidraw's palette on warm paper.
enum Ink {
    static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    static let paper = rgb(0xFAF6EE)
    static let ink = rgb(0x1E1E1E)
    static let faded = rgb(0x9A9894)
    static let red = rgb(0xE03131)
    static let green = rgb(0x2F9E44)
    static let blue = rgb(0x1971C2)
    static let highlight = rgb(0xFFD43B)
    static let noteFill = rgb(0x74C0FC)
}

struct Renderer {
    static let version = 1

    let fonts: Fonts
    let rough: Rough

    init(fonts: Fonts) throws {
        self.fonts = fonts
        self.rough = try Rough()
    }

    private struct Block {
        var lines: [CTLine]
        var lineHeight: CGFloat
        var ascent: CGFloat
        var height: CGFloat { CGFloat(lines.count) * lineHeight }
        var width: CGFloat { lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0 }
        func width(_ i: Int) -> CGFloat { CGFloat(CTLineGetTypographicBounds(lines[i], nil, nil, nil)) }
    }

    private func block(_ text: String, size: CGFloat, color: CGColor, width: CGFloat) -> Block {
        let font = fonts.font(size: size)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [CTLine] = []
        var start = 0
        while start < attributed.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return Block(lines: lines, lineHeight: size * 1.38, ascent: size * 1.02)
    }

    private struct Row {
        var item: Item?
        var text: Block
        var height: CGFloat
    }

    private struct Plan {
        var size: CGFloat
        var columns: [[Row]]
        var note: Block?
        var height: CGFloat
    }

    func render(day: Day, label: String, chinese: Bool, canvas: Canvas) throws -> CGImage {
        let W = CGFloat(canvas.width), H = CGFloat(canvas.height)
        guard let ctx = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw MuraError.failed("Cannot allocate a \(canvas.width)x\(canvas.height) canvas", code: "render") }
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setFillColor(Ink.paper)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        let u = min(H, W * 0.625) / 100
        let left = W * 0.085
        let maxWidth = min(W * 0.56, 130 * u)
        var under: [Shape] = [], over: [Shape] = []
        var texts: [(Block, CGPoint)] = []
        var y = CGFloat(canvas.safeTop) + 8 * u

        // Header: optional small date line, then the big title with a hand-drawn underline.
        let headline = day.title ?? label
        if day.title != nil {
            let date = block(label, size: 3.2 * u, color: Ink.faded, width: maxWidth)
            texts.append((date, CGPoint(x: left, y: y)))
            y += date.height + 0.6 * u
        }
        let title = block(headline, size: 7 * u, color: Ink.ink, width: maxWidth)
        texts.append((title, CGPoint(x: left, y: y)))
        y += title.height + 0.4 * u
        let lineEnd = left + title.width + 1.5 * u
        let span = lineEnd - left
        let wave = points([(left - 0.5 * u, y), (left + span * 0.35, y + 0.55 * u), (left + span * 0.7, y - 0.25 * u), (lineEnd, y + 0.2 * u)])
        over.append(Shape(kind: .curve, args: [wave],
                          stroke: Ink.red, strokeWidth: 0.42 * u, options: ["roughness": 1.1, "bowing": 1.2], seed: seed("underline", headline)))
        if !day.items.isEmpty, day.items.allSatisfy(\.done) {
            let stamp = block(chinese ? "全部搞定!" : "All done!", size: 3.6 * u, color: Ink.red, width: maxWidth)
            let x = lineEnd + 4 * u, top = y - title.height * 0.62
            if x + stamp.width + 3 * u < W {
                texts.append((stamp, CGPoint(x: x, y: top)))
                over.append(Shape(kind: .ellipse, args: [x + stamp.width / 2, top + stamp.height / 2, stamp.width + 3.4 * u, stamp.height + 2 * u],
                                  stroke: Ink.red, strokeWidth: 0.3 * u, options: ["roughness": 1.4], seed: seed("stamp", headline)))
            }
        }
        y += 5 * u

        let bottom = H - CGFloat(canvas.safeBottom) - 7 * u
        if day.items.isEmpty && day.note == nil {
            texts.append((block(chinese ? "还没有安排" : "Nothing planned yet", size: 4 * u, color: Ink.faded, width: maxWidth), CGPoint(x: left, y: y)))
        } else {
            let plan = layout(day: day, chinese: chinese, available: bottom - y, maxWidth: maxWidth, wideWidth: min(W * 0.84, 200 * u), u: u)
            let f = plan.size
            let columnGap = 5 * u
            let columnWidth = plan.columns.count == 1 ? maxWidth : (min(W * 0.84, 200 * u) - columnGap) / 2
            var columnBottom = y
            for (c, rows) in plan.columns.enumerated() {
                var ry = y
                let x = left + CGFloat(c) * (columnWidth + columnGap)
                for row in rows {
                    draw(row: row, at: CGPoint(x: x, y: ry), size: f, under: &under, over: &over, texts: &texts)
                    ry += row.height + 0.55 * f
                }
                columnBottom = max(columnBottom, ry)
            }
            if let note = plan.note {
                let pad = 0.9 * f
                let top = columnBottom + 1.1 * f
                let box = CGRect(x: left, y: top, width: note.width + 2 * pad, height: note.height + 1.4 * pad)
                under.append(Shape(kind: .rectangle, args: [box.minX, box.minY, box.width, box.height], stroke: Ink.blue, fill: Ink.noteFill,
                                   strokeWidth: 0.07 * f, options: ["roughness": 1.3, "fillWeight": 0.03 * f, "hachureGap": 0.42 * f, "hachureAngle": -41],
                                   seed: seed("note", day.note ?? "")))
                texts.append((note, CGPoint(x: box.minX + pad, y: box.minY + 0.7 * pad)))
            }
        }

        try rough.draw(under, in: ctx, unit: u / 10)
        for (block, origin) in texts {
            for (i, line) in block.lines.enumerated() {
                ctx.textPosition = CGPoint(x: origin.x, y: origin.y + CGFloat(i) * block.lineHeight + block.ascent)
                CTLineDraw(line, ctx)
            }
        }
        try rough.draw(over, in: ctx, unit: u / 10)
        guard let image = ctx.makeImage() else { throw MuraError.failed("Rendering produced no image", code: "render") }
        return image
    }

    /// Picks the largest font that fits, falling back to two columns, then to "…and N more".
    private func layout(day: Day, chinese: Bool, available: CGFloat, maxWidth: CGFloat, wideWidth: CGFloat, u: CGFloat) -> Plan {
        func rows(_ items: [Item], size f: CGFloat, width: CGFloat) -> [Row] {
            items.map { item in
                let text = block(item.text, size: f, color: item.done ? Ink.faded : Ink.ink, width: width - 1.5 * f)
                return Row(item: item, text: text, height: max(text.height, 0.82 * f))
            }
        }
        func height(_ rows: [Row], size f: CGFloat) -> CGFloat {
            rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * 0.55 * f
        }
        func plan(items: [Item], size f: CGFloat, columns: Int, overflow: Int = 0) -> Plan {
            let width = columns == 1 ? maxWidth : (wideWidth - 5 * u) / 2
            var all = rows(items, size: f, width: width)
            if overflow > 0 {
                let more = block(chinese ? "…还有 \(overflow) 项" : "…and \(overflow) more", size: f, color: Ink.faded, width: width)
                all.append(Row(item: nil, text: more, height: more.height))
            }
            let split = columns == 1 ? all.count : (all.count + 1) / 2
            let cols = columns == 1 ? [all] : [Array(all[..<split]), Array(all[split...])]
            let note = day.note.map { block($0, size: 0.8 * f, color: Ink.ink, width: maxWidth - 1.8 * f) }
            let noteHeight = note.map { 1.1 * f + $0.height + 1.26 * f } ?? 0
            return Plan(size: f, columns: cols, note: note, height: cols.map { height($0, size: f) }.max()! + noteHeight)
        }

        let sizes = stride(from: 5.6 * u, through: 2.6 * u, by: -0.2 * u)
        for columns in [1, 2] where columns == 1 || day.items.count > 3 {
            for f in sizes {
                let p = plan(items: day.items, size: f, columns: columns)
                if p.height <= available { return p }
            }
        }
        let f = 2.6 * u
        var keep = day.items.count
        while keep > 1 {
            keep -= 1
            let p = plan(items: Array(day.items.prefix(keep)), size: f, columns: 2, overflow: day.items.count - keep)
            if p.height <= available { return p }
        }
        return plan(items: Array(day.items.prefix(1)), size: f, columns: 1, overflow: day.items.count - 1)
    }

    private func draw(row: Row, at origin: CGPoint, size f: CGFloat, under: inout [Shape], over: inout [Shape], texts: inout [(Block, CGPoint)]) {
        guard let item = row.item else {
            texts.append((row.text, origin))
            return
        }
        let b = 0.82 * f
        let lh = row.text.lineHeight
        let box = CGRect(x: origin.x, y: origin.y + (lh - b) / 2 + 0.06 * f, width: b, height: b)
        let textX = origin.x + b + 0.68 * f
        let s = seed(item.text)
        texts.append((row.text, CGPoint(x: textX, y: origin.y)))

        over.append(Shape(kind: .rectangle, args: [box.minX, box.minY, b, b], stroke: item.done ? Ink.faded : item.important ? Ink.red : Ink.ink,
                          strokeWidth: 0.07 * f, options: ["roughness": 1.7, "bowing": 1.4], seed: s))
        for i in row.text.lines.indices {
            let lineTop = origin.y + CGFloat(i) * lh
            let w = row.text.width(i)
            if item.important && !item.done {
                under.append(Shape(kind: .rectangle, args: [textX - 0.25 * f, lineTop + 0.2 * lh, w + 0.5 * f, lh * 0.68], stroke: nil, fill: Ink.highlight,
                                   strokeWidth: 0.06 * f, options: ["roughness": 1.1, "fillWeight": 0.07 * f, "hachureGap": 0.15 * f, "hachureAngle": -41],
                                   seed: s &+ UInt32(i)))
            }
            if item.done {
                let mid = lineTop + lh * 0.55
                over.append(Shape(kind: .line, args: [textX - 0.15 * f, mid, textX + w + 0.15 * f, mid - 0.05 * f], stroke: Ink.faded,
                                  strokeWidth: 0.07 * f, options: ["roughness": 1.2], seed: s &+ 31 &+ UInt32(i)))
            }
        }
        if item.done {
            let check = points([(box.minX + 0.12 * b, box.minY + 0.5 * b), (box.minX + 0.42 * b, box.minY + 0.86 * b), (box.maxX + 0.12 * b, box.minY - 0.22 * b)])
            over.append(Shape(kind: .linearPath, args: [check],
                              stroke: Ink.green, strokeWidth: 0.13 * f, options: ["roughness": 0.8], seed: s &+ 7))
        }
    }
}

private func points(_ list: [(CGFloat, CGFloat)]) -> [[Double]] {
    list.map { [Double($0.0), Double($0.1)] }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
    guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw MuraError.failed("Cannot write \(url.path)", code: "io")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw MuraError.failed("Cannot encode PNG \(url.path)", code: "io") }
    guard rename(tmp.path, url.path) == 0 else { throw MuraError.failed("Cannot move PNG into \(url.path)", code: "io") }
}
