#!/usr/bin/swift
// The window of the release disk image: its backdrop, its layout, and a check
// of what Finder stored. Scripts/build-dmg.sh uses all three.
//
//   swift Tools/dmgbackground.swift <output.png> [scale]   draw the backdrop (1 or 2)
//   swift Tools/dmgbackground.swift --mock <output.png>     the backdrop at 2x with the
//       icons and their names drawn on, once black (light mode) and once white
//       (dark mode), to judge it without building an image
//   swift Tools/dmgbackground.swift --layout                 the layout for the shell
//   swift Tools/dmgbackground.swift --check <volume> [--fix] the icon places and the
//       window options in the volume's .DS_Store; --fix first moves icons that
//       Finder stored elsewhere back to their places and switches off any
//       tab bar, toolbar, status bar or sidebar it stored for the window
//
// All coordinates are Finder's: points, origin top left, icon positions are
// icon centres. Finder draws icon names black in light mode and white in dark
// mode whatever the picture behind them, so the names stand on a mid-toned
// glow that keeps both readable; the rest of the picture is dark space.

import AppKit
import CoreText

// MARK: Layout (the single source: build-dmg.sh reads it with --layout)

let windowWidth: CGFloat = 680
let windowHeight: CGFloat = 440        // inside of the window, without the title bar
// The picture is larger, so a slightly bigger window never runs out of it.
let width: CGFloat = 760
let height: CGFloat = 520
let iconSize: CGFloat = 112
let textSize: CGFloat = 13
let appIcon = CGPoint(x: 180, y: 232)
let applicationsIcon = CGPoint(x: 500, y: 232)
/// Centre line of the icon names (Finder puts them just under the icon),
/// and the plate behind each name.
let labelY = appIcon.y + iconSize / 2 + 18      // measured in Finder (macOS 27)
let plateWidth: CGFloat = 148
let plateHeight: CGFloat = 28
/// Finder windows can show a tab bar (a global Finder setting the image cannot
/// overrule), which takes 40 points off the bottom of the window: everything
/// that must be seen stays above windowHeight − 40, and the frame fades out
/// toward the bottom instead of closing there.
let noteBaseline: CGFloat = 382
/// Where Finder should put the volume's hidden files, for somebody whose
/// Finder shows them (⌘⇧.): below the picture, out of the way.
let hiddenY = Int(height) + 160

let appName = "Nova Rush.app"
let hiddenItems = [".background", ".VolumeIcon.icns", ".fseventsd", ".Trashes"]

let args = CommandLine.arguments

if args.count > 1, args[1] == "--layout" {
    print("WIN_W=\(Int(windowWidth)) WIN_H=\(Int(windowHeight)) ICON=\(Int(iconSize)) TEXT=\(Int(textSize))",
          "APP_X=\(Int(appIcon.x)) APP_Y=\(Int(appIcon.y))",
          "APPS_X=\(Int(applicationsIcon.x)) APPS_Y=\(Int(applicationsIcon.y)) HIDDEN_Y=\(hiddenY)")
    exit(0)
}

// MARK: Check (and fix) Finder's .DS_Store

/// Every icon place in a .DS_Store: name → (x, y) and the byte offset of x.
/// A record is the name (a count of UTF-16 units, then the units), "Iloc",
/// "blob", 16, then x and y as big-endian 32-bit integers.
func places(_ raw: [UInt8]) -> [String: (x: Int, y: Int, at: Int)] {
    func u32(_ i: Int) -> Int {
        Int(raw[i]) << 24 | Int(raw[i + 1]) << 16 | Int(raw[i + 2]) << 8 | Int(raw[i + 3])
    }
    func i32(_ i: Int) -> Int { Int(Int32(bitPattern: UInt32(u32(i)))) }
    let tag = Array("Ilocblob".utf8)
    var out: [String: (Int, Int, Int)] = [:]
    var i = 0
    while i + 20 <= raw.count {
        if Array(raw[i..<i + 8]) == tag && u32(i + 8) == 16 {
            var j = i - 2
            while j >= 4 {
                let n = u32(j - 4)
                if n > 0 && n < 256 && j + 2 * n == i {
                    let units = stride(from: j, to: i, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
                    out[String(decoding: units, as: UTF16.self)] = (i32(i + 12), i32(i + 16), i + 12)
                    break
                }
                j -= 2
            }
            i += 20
        } else {
            i += 1
        }
    }
    return out.mapValues { (x: $0.0, y: $0.1, at: $0.2) }
}

/// The property list stored under a four-letter code ("bwsp" window, "icvp" icon view).
func plist(_ raw: [UInt8], _ code: String) -> [String: Any]? {
    let tag = Array((code + "blob").utf8)
    guard let i = (0...(raw.count - 12)).first(where: { Array(raw[$0..<$0 + 8]) == tag }) else { return nil }
    let n = Int(raw[i + 8]) << 24 | Int(raw[i + 9]) << 16 | Int(raw[i + 10]) << 8 | Int(raw[i + 11])
    let data = Data(raw[(i + 12)..<(i + 12 + n)])
    return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
}

/// Sets the given true booleans of the binary property list stored under
/// `code` to false, in place (a boolean is one byte: 0x09 true, 0x08 false,
/// so nothing else in the file moves). Returns the keys it switched.
func switchOff(_ raw: inout [UInt8], code: String, keys: Set<String>) -> [String] {
    let tag = Array((code + "blob").utf8)
    guard let i = (0...(raw.count - 12)).first(where: { Array(raw[$0..<$0 + 8]) == tag }) else { return [] }
    let base = i + 12
    func int(_ at: Int, _ size: Int) -> Int { (0..<size).reduce(0) { $0 << 8 | Int(raw[base + at + $1]) } }
    let n = Int(raw[i + 8]) << 24 | Int(raw[i + 9]) << 16 | Int(raw[i + 10]) << 8 | Int(raw[i + 11])
    guard n > 40, Array(raw[base..<base + 8]) == Array("bplist00".utf8) else { return [] }
    // Trailer: offset int size, object ref size, object count, top object, offset table.
    let offsetSize = Int(raw[base + n - 26]), refSize = Int(raw[base + n - 25])
    let top = int(n - 16, 8), table = int(n - 8, 8)
    func offset(_ object: Int) -> Int { int(table + object * offsetSize, offsetSize) }
    /// Count of a container or string at `at`, and the length of its header.
    func count(_ at: Int) -> (Int, Int) {
        let low = Int(raw[base + at] & 0x0F)
        if low != 0x0F { return (low, 1) }
        let size = 1 << Int(raw[base + at + 1] & 0x0F)
        return (int(at + 2, size), 2 + size)
    }
    let dict = offset(top)
    guard raw[base + dict] >> 4 == 0xD else { return [] }
    let (entries, header) = count(dict)
    var switched: [String] = []
    for k in 0..<entries {
        let key = offset(int(dict + header + k * refSize, refSize))
        let value = offset(int(dict + header + (entries + k) * refSize, refSize))
        guard raw[base + key] >> 4 == 0x5 else { continue }          // ASCII string
        let (length, h) = count(key)
        let name = String(decoding: raw[(base + key + h)..<(base + key + h + length)], as: UTF8.self)
        if keys.contains(name) && raw[base + value] == 0x09 {
            raw[base + value] = 0x08
            switched.append(name)
        }
    }
    return switched
}

if args.count > 2, args[1] == "--check" {
    let fix = args.contains("--fix")
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent(".DS_Store")
    guard var raw = try? [UInt8](Data(contentsOf: url)) else {
        print("dmgbackground: no .DS_Store in \(args[2])"); exit(1)
    }
    var want: [String: (Int, Int)] = [appName: (Int(appIcon.x), Int(appIcon.y)),
                                      "Applications": (Int(applicationsIcon.x), Int(applicationsIcon.y))]
    for (k, name) in hiddenItems.enumerated() { want[name] = (Int(appIcon.x) + 140 * k, hiddenY) }
    var problems: [String] = []
    var moved: [String] = []
    let got = places(raw)
    for (name, place) in want.sorted(by: { $0.key < $1.key }) {
        guard let p = got[name] else {
            // Hidden files only get a place if Finder could script them.
            if !hiddenItems.contains(name) { problems.append("\(name): no place stored") }
            continue
        }
        if (p.x, p.y) != place {
            if fix {
                for (k, v) in [place.0, place.1].enumerated() {
                    let bits = UInt32(bitPattern: Int32(v))
                    for b in 0..<4 { raw[p.at + 4 * k + b] = UInt8(truncatingIfNeeded: bits >> (24 - 8 * b)) }
                }
                moved.append("\(name) \(p.x),\(p.y) → \(place.0),\(place.1)")
            } else {
                problems.append("\(name) at \(p.x),\(p.y), want \(place.0),\(place.1)")
            }
        }
    }
    // The window takes Finder's defaults of the moment: a builder whose
    // windows show a tab bar would hand it to everybody, and the icons would
    // stand lower than the picture expects. Switch the bars off in place.
    let bars = ["ShowTabView", "ShowToolbar", "ShowStatusBar", "ShowPathbar", "ShowSidebar", "ContainerShowSidebar"]
    if fix {
        for bar in switchOff(&raw, code: "bwsp", keys: Set(bars)) { moved.append("\(bar) off") }
    }
    let window = plist(raw, "bwsp") ?? [:]
    let view = plist(raw, "icvp") ?? [:]
    for bar in bars where (window[bar] as? Bool) == true {
        problems.append("the window has \(bar) on")
    }
    if view["backgroundImageAlias"] == nil { problems.append("no backdrop stored for the window") }
    if (view["iconSize"] as? Double).map({ Int($0) }) != Int(iconSize) {
        problems.append("icon size \(view["iconSize"] ?? "none"), want \(Int(iconSize))")
    }
    if fix && !moved.isEmpty { try! Data(raw).write(to: url) }
    let placed = got.filter { want[$0.key] != nil }.map { "\($0.key) \($0.value.x),\($0.value.y)" }.sorted()
    print("layout: \(placed.joined(separator: ", ")); window \(window["WindowBounds"] ?? "?"), "
          + "icons \(view["iconSize"] ?? "?") pt, names \(view["textSize"] ?? "?") pt"
          + (moved.isEmpty ? "" : "; fixed: " + moved.joined(separator: "; ")))
    if !problems.isEmpty {
        print("dmgbackground: the layout is not as planned:\n  " + problems.joined(separator: "\n  "))
        exit(1)
    }
    exit(0)
}

// MARK: Drawing

let mock = args.count > 2 && args[1] == "--mock"
let output = mock ? args[2] : (args.count > 1 ? args[1] : "dmg-background.png")
let scale: CGFloat = mock ? 2 : (args.count > 2 ? CGFloat(Double(args[2]) ?? 1) : 1)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
// The table's own colours.
let amber = (r: 1.0 as CGFloat, g: 0.72 as CGFloat, b: 0.30 as CGFloat)
let cyan = (r: 0.21 as CGFloat, g: 0.75 as CGFloat, b: 0.95 as CGFloat)
let magenta = (r: 1.0 as CGFloat, g: 0.24 as CGFloat, b: 0.65 as CGFloat)
let rail = (r: 0.50 as CGFloat, g: 0.53 as CGFloat, b: 0.75 as CGFloat)

/// The game's nebula backdrop, turned on its side (it is painted for the
/// tall table) — or nil, and the picture is plain space.
func nebula() -> CGImage? {
    let path = "Sources/NovaRush/Resources/Skins/backdrop.jpg"
    guard let src = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }
    let ctx = makeContext(src.height, src.width)
    ctx.interpolationQuality = .high
    ctx.translateBy(x: CGFloat(src.height), y: 0)
    ctx.rotate(by: .pi / 2)
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: src.width, height: src.height))
    return ctx.makeImage()
}

let ctx = makeContext(Int(width * scale), Int(height * scale))
ctx.interpolationQuality = .high
// Work in Finder coordinates: y grows downward.
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: height)
ctx.scaleBy(x: 1, y: -1)

/// Draws an image upright into a rect given in Finder coordinates.
func draw(_ image: CGImage, in rect: CGRect, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

/// Soft elliptical glow: full `color` inside `core` of the radius, fading out.
func glow(at c: CGPoint, rx: CGFloat, ry: CGFloat, color: CGColor, core: CGFloat = 0.45) {
    let clear = color.copy(alpha: 0)!
    guard let g = CGGradient(colorsSpace: space, colors: [color, color, clear] as CFArray,
                             locations: [0, core, 1]) else { return }
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: rx / ry, y: 1)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: ry, options: [])
    ctx.restoreGState()
}

// Ground: deep space, then the nebula, darkened so the neon reads.
ctx.setFillColor(srgb(0.02, 0.025, 0.07))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
if let sky = nebula() {
    // The spiral's heart sits a little right of the middle, under the arrow.
    let crop = CGRect(x: 360, y: 0, width: 1309, height: 896)
    if let part = sky.cropping(to: crop) {
        draw(part, in: CGRect(x: 0, y: 0, width: width, height: height), alpha: 0.85)
    }
}
// Darker at the top (for the title) and toward the edges.
if let g = CGGradient(colorsSpace: space, colors: [srgb(0.01, 0.015, 0.05, 0.85), srgb(0.01, 0.015, 0.05, 0)] as CFArray,
                      locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 165), options: [])
}
if let g = CGGradient(colorsSpace: space, colors: [srgb(0, 0, 0, 0), srgb(0.01, 0.015, 0.05, 0.75)] as CFArray,
                      locations: [0.55, 1]) {
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: windowWidth / 2, y: 250), startRadius: 0,
                           endCenter: CGPoint(x: windowWidth / 2, y: 250), endRadius: 470,
                           options: [.drawsAfterEndLocation])
}

// Name plates: a lit insert under each icon's name, mid-toned violet blue —
// light enough for black names, dark enough for white ones.
for icon in [appIcon, applicationsIcon] {
    let plate = CGRect(x: icon.x - plateWidth / 2, y: labelY - plateHeight / 2, width: plateWidth, height: plateHeight)
    let path = CGPath(roundedRect: plate, cornerWidth: plateHeight / 2, cornerHeight: plateHeight / 2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 12, color: srgb(cyan.r, cyan.g, cyan.b, 0.55))
    ctx.addPath(path)
    ctx.setFillColor(srgb(0.41, 0.45, 0.79))
    ctx.fillPath()
    ctx.restoreGState()
    // A lighter top half, as if lit from inside.
    if let g = CGGradient(colorsSpace: space, colors: [srgb(1, 1, 1, 0.10), srgb(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1]) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.midY), options: [])
        ctx.restoreGState()
    }
    ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 0.75, dy: 0.75), cornerWidth: plateHeight / 2 - 0.75,
                       cornerHeight: plateHeight / 2 - 0.75, transform: nil))
    ctx.setStrokeColor(srgb(0.78, 0.86, 1.0, 0.75))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
}

/// Draws one line of text centred on `x`; returns its width.
@discardableResult
func text(_ string: String, x: CGFloat, baseline y: CGFloat, font: NSFont, color: CGColor,
          glowColor: CGColor? = nil, glowRadius: CGFloat = 0, kern: CGFloat = 0) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: kern,
    ]))
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.saveGState()
    if let glowColor { ctx.setShadow(offset: .zero, blur: glowRadius, color: glowColor) }
    // Core Text draws y-up: undo the flip around the baseline.
    ctx.translateBy(x: x - w / 2, y: y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    return w
}

// The cabinet's rail along the window, with the table's rounded top. Open at
// the bottom: the sides fade out above the part a tab bar can hide.
do {
    let left: CGFloat = 14, right = windowWidth - 14, topY: CGFloat = 14, radius: CGFloat = 64
    let p = CGMutablePath()
    p.move(to: CGPoint(x: left, y: windowHeight))
    p.addLine(to: CGPoint(x: left, y: topY + radius))
    p.addArc(tangent1End: CGPoint(x: left, y: topY), tangent2End: CGPoint(x: left + radius, y: topY), radius: radius)
    p.addLine(to: CGPoint(x: right - radius, y: topY))
    p.addArc(tangent1End: CGPoint(x: right, y: topY), tangent2End: CGPoint(x: right, y: topY + radius), radius: radius)
    p.addLine(to: CGPoint(x: right, y: windowHeight))
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 8, color: srgb(rail.r, rail.g, rail.b, 0.6))
    ctx.addPath(p)
    ctx.setStrokeColor(srgb(rail.r, rail.g, rail.b, 0.85))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setBlendMode(.destinationIn)
    if let fade = CGGradient(colorsSpace: space, colors: [srgb(0, 0, 0, 1), srgb(0, 0, 0, 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: labelY + 10), end: CGPoint(x: 0, y: noteBaseline - 4),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// Title and line, as on the table: amber Menlo with a warm glow.
let titleFont = NSFont(name: "Menlo-Bold", size: 46) ?? .monospacedSystemFont(ofSize: 46, weight: .bold)
text("NOVA RUSH", x: windowWidth / 2, baseline: 86, font: titleFont, color: srgb(amber.r, amber.g, amber.b),
     glowColor: srgb(amber.r, amber.g, amber.b, 0.75), glowRadius: 16, kern: 2)
text("A space pinball table for your Mac", x: windowWidth / 2, baseline: 114,
     font: .systemFont(ofSize: 15, weight: .medium), color: srgb(1, 1, 1, 0.92),
     glowColor: srgb(0, 0, 0, 0.9), glowRadius: 6)

// "Drag the app onto Applications": a neon arrow between the two icons.
do {
    let from = appIcon.x + iconSize / 2 + 30
    let to = applicationsIcon.x - iconSize / 2 - 30
    let y = appIcon.y - 6
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: from, y: y))
    arrow.addLine(to: CGPoint(x: to, y: y))
    arrow.move(to: CGPoint(x: to - 15, y: y - 13))
    arrow.addLine(to: CGPoint(x: to, y: y))
    arrow.addLine(to: CGPoint(x: to - 15, y: y + 13))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (lineWidth, color, blur) in [(7.0 as CGFloat, srgb(cyan.r, cyan.g, cyan.b, 0.9), 14.0 as CGFloat),
                                     (3.0, srgb(0.85, 0.97, 1.0), 0)] {
        ctx.saveGState()
        if blur > 0 { ctx.setShadow(offset: .zero, blur: blur, color: srgb(cyan.r, cyan.g, cyan.b, 1)) }
        ctx.addPath(arrow)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
        ctx.restoreGState()
    }
    // Two magenta lamps at the arrow's tail, like the sling plastics' dots.
    for dx in [-14.0 as CGFloat, -26] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6, color: srgb(magenta.r, magenta.g, magenta.b, 1))
        ctx.setFillColor(srgb(magenta.r, magenta.g, magenta.b))
        ctx.fillEllipse(in: CGRect(x: from + dx - 3, y: y - 3, width: 6, height: 6))
        ctx.restoreGState()
    }
    text("drag to install", x: (from + to) / 2, baseline: y + 32, font: .systemFont(ofSize: 13, weight: .medium),
         color: srgb(1, 1, 1, 0.92), glowColor: srgb(0, 0, 0, 0.9), glowRadius: 5)
}

// The first start: the app is signed ad hoc, not notarized.
text("First start: if macOS won’t open the app, allow it under "
     + "System Settings › Privacy & Security › Open Anyway.",
     x: windowWidth / 2, baseline: noteBaseline, font: .systemFont(ofSize: 11.5), color: srgb(1, 1, 1, 0.85),
     glowColor: srgb(0, 0, 0, 1), glowRadius: 4)

// MARK: Mock: what Finder puts on top

func save(_ image: CGImage, _ path: String) {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        print("dmgbackground: cannot render"); exit(1)
    }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch {
        print("dmgbackground: \(error.localizedDescription)"); exit(1)
    }
}

guard let picture = ctx.makeImage() else { print("dmgbackground: cannot render"); exit(1) }

if mock {
    // Two views side by side, each cut to the window: light mode without a tab
    // bar, dark mode with one (40 points less window at the bottom).
    let w = Int(windowWidth * 2), h = Int(windowHeight * 2)
    let sheet = makeContext(2 * w + 40, h)
    sheet.setFillColor(srgb(0.5, 0.5, 0.5))
    sheet.fill(CGRect(x: 0, y: 0, width: 2 * w + 40, height: h))
    let icons: [(NSImage, CGPoint, String)] = [
        (NSImage(contentsOfFile: "Support/AppIcon.iconset/icon_256x256@2x.png") ?? NSImage(), appIcon, "Nova Rush"),
        (NSWorkspace.shared.icon(forFile: "/Applications"), applicationsIcon, "Applications"),
    ]
    for (k, labelColor) in [NSColor.black, NSColor.white].enumerated() {
        let visible = k == 0 ? h : h - 80
        let window = picture.cropping(to: CGRect(x: 0, y: 0, width: w, height: visible))!
        let ox = CGFloat(k * (w + 40))
        sheet.draw(window, in: CGRect(x: ox, y: CGFloat(h - visible), width: CGFloat(w), height: CGFloat(visible)))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
        for (image, at, name) in icons {
            let s = iconSize * 2
            image.draw(in: NSRect(x: ox + at.x * 2 - s / 2, y: CGFloat(h) - at.y * 2 - s / 2, width: s, height: s))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: textSize * 2),
                                                        .foregroundColor: labelColor]
            let size = (name as NSString).size(withAttributes: attrs)
            (name as NSString).draw(at: NSPoint(x: ox + at.x * 2 - size.width / 2,
                                                y: CGFloat(h) - labelY * 2 - size.height / 2), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    save(sheet.makeImage()!, output)
    print("dmgbackground: wrote the mock \(output)")
} else {
    save(picture, output)
    print("dmgbackground: wrote \(output) (\(picture.width) x \(picture.height))")
}
