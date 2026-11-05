// Draws Tidemeld's app icon, a hand-drawn capital T on the rice white of voytty's
// iOS icon, and writes every copy the two apps ship:
//   swift tools/render-icons.swift
// Android: the adaptive icon's vector foreground (also its monochrome layer)
// and the legacy mipmap PNGs. iOS: the light, dark and tinted AppIcon PNGs,
// full-bleed squares that iOS masks itself. Edit the pen below and rerun;
// don't edit the outputs by hand.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()

// MARK: - The letter

/// Two strokes in a 100-unit square, y pointing down. The crossbar and
/// stem share the same ink; their slight curves keep the mark hand-drawn.
let crossbar: [(x: CGFloat, y: CGFloat, half: CGFloat)] = [
    (28, 32, 3.2),
    (72, 30.5, 3.5),
]
let stem: [(x: CGFloat, y: CGFloat, half: CGFloat)] = [
    (51, 31.5, 3.1),
    (49, 72, 3.6),
]
/// Degrees the whole letter turns anticlockwise, as a hand slants it.
let slant: CGFloat = 2
/// Width of the round-joined line along the outline; it softens the notches.
let rim: CGFloat = 2

// MARK: - Colours

let paper: UInt32 = 0xF5F0E8, ink: UInt32 = 0x9F6561
let darkPaper: UInt32 = 0x191613, darkInk: UInt32 = 0xC69891
let tintedPaper: UInt32 = 0x191919, tintedInk: UInt32 = 0xF2F2F2

// MARK: - Geometry

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var unit: CGPoint { self * (1 / hypot(x, y)) }
    /// A quarter turn from this direction, the way +x turns into +y.
    var normal: CGPoint { CGPoint(x: -y, y: x) }
    var angle: CGFloat { atan2(y, x) }
}

func polar(_ angle: CGFloat) -> CGPoint { CGPoint(x: cos(angle), y: sin(angle)) }
func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }

struct Cubic {
    var a, b, c, d: CGPoint
    var reversed: Cubic { Cubic(a: d, b: c, c: b, d: a) }
    func map(_ f: (CGPoint) -> CGPoint) -> Cubic { Cubic(a: f(a), b: f(b), c: f(c), d: f(d)) }
    func at(_ t: CGFloat) -> CGPoint {
        let s = 1 - t
        return a * (s * s * s) + b * (3 * s * s * t) + c * (3 * s * t * t) + d * (t * t * t)
    }
}

func line(_ from: CGPoint, _ to: CGPoint, bowing offset: CGPoint) -> Cubic {
    let third = (to - from) * (1.0 / 3)
    return Cubic(a: from, b: from + third + offset, c: from + third * 2 + offset, d: to)
}

/// A circular arc as cubics of at most a quarter turn each.
func arc(around center: CGPoint, radius: CGFloat, from start: CGFloat, by sweep: CGFloat) -> [Cubic] {
    let pieces = Int((abs(sweep) / (.pi / 2)).rounded(.up))
    let step = sweep / CGFloat(pieces)
    let handle = 4.0 / 3 * tan(step / 4) * radius
    return (0..<pieces).map { i in
        let from = start + step * CGFloat(i), to = from + step
        let p = center + polar(from) * radius, q = center + polar(to) * radius
        return Cubic(a: p, b: p + polar(from).normal * handle, c: q - polar(to).normal * handle, d: q)
    }
}

func intersection(_ p: CGPoint, _ p2: CGPoint, _ q: CGPoint, _ q2: CGPoint) -> CGPoint {
    let r = p2 - p, s = q2 - q
    return p + r * (cross(q - p, s) / cross(r, s))
}

/// The ink's outline: each side of the pen's path, the outer side rounding
/// each turn and the inner sides meeting in a notch, with round ends.
func outline(pen: [(x: CGFloat, y: CGFloat, half: CGFloat)], bow: [CGFloat], pinch: [CGFloat]) -> [Cubic] {
    let points = pen.map { CGPoint(x: $0.x, y: $0.y) }
    let half = pen.map(\.half)
    let lines = Array(points.indices.dropLast())
    let normals = lines.map { (points[$0 + 1] - points[$0]).unit.normal }
    let signs: [CGFloat] = [1, -1]  // side 0 is the +normal side
    var starts = signs.map { sign in lines.map { points[$0] + normals[$0] * (half[$0] * sign) } }
    var ends = signs.map { sign in lines.map { points[$0 + 1] + normals[$0] * (half[$0 + 1] * sign) } }
    var outside: [Int: Int] = [:]
    for v in lines.dropFirst() {
        // Turning toward +normal puts the -normal side outside.
        let outer = cross(normals[v - 1], normals[v]) > 0 ? 1 : 0, inner = 1 - outer
        let notch = intersection(starts[inner][v - 1], ends[inner][v - 1], starts[inner][v], ends[inner][v])
        ends[inner][v - 1] = notch
        starts[inner][v] = notch
        outside[v] = outer
    }
    func side(_ s: Int) -> [Cubic] {
        lines.flatMap { l -> [Cubic] in
            var curves = [line(starts[s][l], ends[s][l], bowing: normals[l] * (bow[l] - pinch[l] * signs[s]))]
            let v = l + 1
            if outside[v] == s {
                let from = (normals[l] * signs[s]).angle
                var sweep = (normals[v] * signs[s]).angle - from
                if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }
                curves += arc(around: points[v], radius: half[v], from: from, by: sweep)
            }
            return curves
        }
    }
    let last = points.count - 1
    return side(0)
        + arc(around: points[last], radius: half[last], from: normals[last - 1].angle, by: -.pi)
        + side(1).reversed().map(\.reversed)
        + arc(around: points[0], radius: half[0], from: (normals[0] * -1).angle, by: -.pi)
}

/// The outline centred in the square and slanted.
func placed(_ strokes: [[Cubic]]) -> [[Cubic]] {
    let samples = strokes.flatMap { $0 }.flatMap { c in stride(from: 0, through: 1, by: 0.05).map { c.at($0) } }
    let xs = samples.map(\.x), ys = samples.map(\.y)
    let center = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
    let turn = -slant * .pi / 180
    return strokes.map { curves in curves.map {
        $0.map { p in
            let q = p - center
            return CGPoint(x: 50 + q.x * cos(turn) - q.y * sin(turn), y: 50 + q.x * sin(turn) + q.y * cos(turn))
        }
    } }
}

let letters = placed([
    outline(pen: crossbar, bow: [0.8], pinch: [0.35]),
    outline(pen: stem, bow: [-0.7], pinch: [0.3]),
])

// MARK: - Output

func color(_ hex: UInt32, in space: CGColorSpace) -> CGColor {
    let components: [CGFloat] = space.model == .monochrome ? [CGFloat(hex & 255) / 255, 1]
        : [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, 1]
    return CGColor(colorSpace: space, components: components)!
}

/// Draws the icon `size` pixels square; `corner` rounds it off as a share of
/// the size and leaves the rest transparent, otherwise it is opaque.
func png(_ path: String, size: Int, paper: UInt32, ink: UInt32, gray: Bool = false, corner: CGFloat? = nil) throws {
    let space = CGColorSpace(name: gray ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = corner != nil ? .premultipliedLast : gray ? .none : .noneSkipLast
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else {
        throw NSError(domain: "AppIcon", code: 1)
    }
    let square = CGRect(x: 0, y: 0, width: size, height: size)
    if let corner {
        let radius = CGFloat(size) * corner
        context.addPath(CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
    }
    context.setFillColor(color(paper, in: space))
    context.fill(square)
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: CGFloat(size) / 100, y: -CGFloat(size) / 100)
    let outline = CGMutablePath()
    for letter in letters {
        outline.move(to: letter[0].a)
        for c in letter { outline.addCurve(to: c.d, control1: c.b, control2: c.c) }
        outline.closeSubpath()
    }
    context.setFillColor(color(ink, in: space))
    context.setStrokeColor(color(ink, in: space))
    context.setLineWidth(rim)
    context.setLineJoin(.round)
    context.addPath(outline)
    context.drawPath(using: .fillStroke)
    let url = repository.appendingPathComponent(path)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "AppIcon", code: 2)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "AppIcon", code: 3) }
    print("Wrote \(path)")
}

/// The adaptive icon's 108-unit layer shows its middle 72 units, so the
/// square maps onto those.
func vector(_ path: String) throws {
    func number(_ v: CGFloat) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
    func point(_ p: CGPoint) -> String { "\(number(18 + p.x * 0.72)),\(number(18 + p.y * 0.72))" }
    let data = letters.map { letter in
        "M" + point(letter[0].a)
            + letter.map { "C" + [$0.b, $0.c, $0.d].map(point).joined(separator: " ") }.joined() + "Z"
    }.joined()
    let hex = String(format: "#%06X", ink)
    let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- Tidemeld's mark: a hand-drawn capital T. Written by tools/render-icons.swift,
             which also draws the mipmap PNGs and the iOS icons; edit the script, not
             this file. -->
        <vector xmlns:android="http://schemas.android.com/apk/res/android"
            android:width="108dp"
            android:height="108dp"
            android:viewportWidth="108"
            android:viewportHeight="108">
            <path
                android:fillColor="\(hex)"
                android:pathData="\(data)"
                android:strokeColor="\(hex)"
                android:strokeWidth="\(number(rim * 0.72))"
                android:strokeLineJoin="round" />
        </vector>

        """
    try xml.write(to: repository.appendingPathComponent(path), atomically: true, encoding: .utf8)
    print("Wrote \(path) (\(data.count) characters of path)")
}

let android = "app/src/main/res"
try vector("\(android)/drawable/ic_launcher_foreground.xml")
for (density, size) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    try png("\(android)/mipmap-\(density)/ic_launcher.png", size: size, paper: paper, ink: ink, corner: 0.18)
}
let ios = "ios/Tidemeld/Resources/Assets.xcassets/AppIcon.appiconset"
try png("\(ios)/AppIcon.png", size: 1024, paper: paper, ink: ink)
try png("\(ios)/AppIconDark.png", size: 1024, paper: darkPaper, ink: darkInk)
try png("\(ios)/AppIconTinted.png", size: 1024, paper: tintedPaper, ink: tintedInk, gray: true)
