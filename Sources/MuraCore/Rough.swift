import CoreGraphics
import Foundation
import JavaScriptCore

/// A sketchy shape request, handed to rough.js's generator (no DOM needed) inside JavaScriptCore.
struct Shape {
    enum Kind: String { case rectangle, ellipse, line, linearPath, curve }

    var kind: Kind
    var args: [Any]
    var stroke: CGColor?
    var fill: CGColor?
    var strokeWidth: CGFloat
    var options: [String: Any] = [:]
    var seed: UInt32
}

final class Rough {
    private let context: JSContext

    init() throws {
        guard let context = JSContext() else { throw MuraError.failed("JavaScriptCore is unavailable", code: "render") }
        context.evaluateScript(roughJSSource)
        context.evaluateScript("""
        var __g = rough.generator();
        function __sets(json) {
          return JSON.stringify(JSON.parse(json).map(function (s) {
            var d = __g[s.kind].apply(__g, s.args.concat([s.options]));
            return d.sets.map(function (set) {
              return { t: set.type, o: set.ops.map(function (op) {
                return [op.op === 'move' ? 0 : op.op === 'lineTo' ? 1 : 2].concat(op.data);
              }) };
            });
          }));
        }
        """)
        if let exception = context.exception {
            throw MuraError.failed("rough.js failed to load: \(exception)", code: "render")
        }
        self.context = context
    }

    /// rough.js wobbles by a fixed number of pixels, so shapes are generated at 1/`unit` scale
    /// (roughly Excalidraw's on-screen size) and scaled back up; otherwise a 4K canvas looks ruler-straight.
    func draw(_ shapes: [Shape], in ctx: CGContext, unit: CGFloat) throws {
        guard !shapes.isEmpty else { return }
        func down(_ value: Any) -> Any {
            if let array = value as? [Any] { return array.map(down) }
            if let number = value as? CGFloat { return Double(number / unit) }
            if let number = value as? Double { return number / Double(unit) }
            return value
        }
        let specs: [[String: Any]] = shapes.map { shape in
            var options = shape.options
            for key in ["fillWeight", "hachureGap"] where options[key] != nil { options[key] = down(options[key]!) }
            options["seed"] = Int(shape.seed % 2_000_000_000) + 1
            options["strokeWidth"] = Double(shape.strokeWidth / unit)
            options["stroke"] = shape.stroke == nil ? "none" : "#000"
            if shape.fill != nil {
                options["fill"] = "#000"
                if options["fillStyle"] == nil { options["fillStyle"] = "hachure" }
            }
            return ["kind": shape.kind.rawValue, "args": shape.args.map(down), "options": options]
        }
        let input = String(data: try JSONSerialization.data(withJSONObject: specs), encoding: .utf8)!
        guard let output = context.objectForKeyedSubscript("__sets").call(withArguments: [input])?.toString(),
              let data = output.data(using: .utf8),
              let all = try JSONSerialization.jsonObject(with: data) as? [[[String: Any]]], all.count == shapes.count
        else { throw MuraError.failed("rough.js returned no shapes: \(String(describing: context.exception))", code: "render") }

        for (shape, sets) in zip(shapes, all) {
            for set in sets {
                guard let type = set["t"] as? String, let ops = set["o"] as? [[Double]] else { continue }
                let path = CGMutablePath()
                for op in ops {
                    let v = op.enumerated().map { $0.offset == 0 ? CGFloat($0.element) : CGFloat($0.element) * unit }
                    switch Int(v[0]) {
                    case 0: path.move(to: CGPoint(x: v[1], y: v[2]))
                    case 1: path.addLine(to: CGPoint(x: v[1], y: v[2]))
                    default: path.addCurve(to: CGPoint(x: v[5], y: v[6]), control1: CGPoint(x: v[1], y: v[2]), control2: CGPoint(x: v[3], y: v[4]))
                    }
                }
                ctx.addPath(path)
                switch type {
                case "fillPath":
                    ctx.setFillColor(shape.fill!)
                    ctx.fillPath()
                case "fillSketch":
                    ctx.setStrokeColor(shape.fill!)
                    ctx.setLineWidth((shape.options["fillWeight"] as? CGFloat) ?? shape.strokeWidth / 2)
                    ctx.setLineCap(.round)
                    ctx.strokePath()
                default:
                    ctx.setStrokeColor(shape.stroke ?? shape.fill!)
                    ctx.setLineWidth(shape.strokeWidth)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                }
            }
        }
    }
}

/// Stable 32-bit FNV-1a, so the same item keeps the same wobble across re-renders.
func seed(_ parts: Any...) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in parts.map({ "\($0)" }).joined(separator: "|").utf8 {
        hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return hash
}
