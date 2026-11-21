// Generates the app icon set procedurally (no bitmap assets, like
// everything else in this project). Usage: swift Tools/icongen.swift
// then: iconutil -c icns Support/AppIcon.iconset -o Support/AppIcon.icns
import AppKit

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func drawIcon(px: Int) -> CGImage {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = s / 1024

    // macOS icon plate: 824pt rounded rect on the 1024 grid.
    let plate = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 186 * u,
                       cornerHeight: 186 * u, transform: nil))
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.42, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.045, green: 0.06, blue: 0.16, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: .zero, options: [])

    var state: UInt64 = 12
    func rnd() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 40) / CGFloat(1 << 24)
    }
    ctx.setFillColor(NSColor.white.cgColor)
    for _ in 0..<42 {
        let x = 100 * u + rnd() * 824 * u
        let y = 100 * u + rnd() * 824 * u
        let r = (2 + rnd() * 5) * u
        ctx.setAlpha(0.25 + rnd() * 0.5)
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
    ctx.setAlpha(1)

    // The Comet ramp: amber band arcing across the field.
    ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0.72, blue: 0.3, alpha: 0.95).cgColor)
    ctx.setLineWidth(42 * u)
    ctx.setLineCap(.round)
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 205 * u, y: 290 * u))
    arc.addQuadCurve(to: CGPoint(x: 820 * u, y: 400 * u),
                     control: CGPoint(x: 500 * u, y: 950 * u))
    ctx.addPath(arc)
    ctx.strokePath()

    // Pop bumper dome, upper left.
    let bumpCenter = CGPoint(x: 355 * u, y: 700 * u)
    let bump = CGGradient(colorsSpace: space, colors: [
        NSColor(calibratedRed: 1, green: 0.78, blue: 0.92, alpha: 1).cgColor,
        NSColor(calibratedRed: 1, green: 0.24, blue: 0.65, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.45, green: 0.08, blue: 0.30, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: bumpCenter.x - 125 * u, y: bumpCenter.y - 125 * u,
                              width: 250 * u, height: 250 * u))
    ctx.clip()
    ctx.drawRadialGradient(bump,
                           startCenter: CGPoint(x: bumpCenter.x - 30 * u, y: bumpCenter.y + 50 * u),
                           startRadius: 0, endCenter: bumpCenter, endRadius: 125 * u,
                           options: .drawsAfterEndLocation)
    ctx.restoreGState()

    // Chrome ball, lower right.
    let ballCenter = CGPoint(x: 655 * u, y: 340 * u)
    let ball = CGGradient(colorsSpace: space, colors: [
        NSColor.white.cgColor,
        NSColor(calibratedRed: 0.68, green: 0.73, blue: 0.81, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.35, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.45, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: ballCenter.x - 165 * u, y: ballCenter.y - 165 * u,
                              width: 330 * u, height: 330 * u))
    ctx.clip()
    ctx.drawRadialGradient(ball,
                           startCenter: CGPoint(x: ballCenter.x - 55 * u, y: ballCenter.y + 80 * u),
                           startRadius: 0, endCenter: ballCenter, endRadius: 165 * u,
                           options: .drawsAfterEndLocation)
    ctx.restoreGState()

    return ctx.makeImage()!
}

let dir = "Support/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let rep = NSBitmapImageRep(cgImage: drawIcon(px: px))
    rep.size = NSSize(width: px, height: px)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
print("wrote \(sizes.count) icons to \(dir)")
