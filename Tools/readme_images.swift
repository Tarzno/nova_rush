// Renders the pictures for README.md into Images/.
//
//   Scripts/build-app.sh && swift Tools/readme_images.swift
//
// Every picture is taken from the game itself: the built app is started with
// its verification flags (--snapshot renders the table to a PNG, --nohint
// hides the key hint, --helpmap saves the Help window's numbered map), and
// the snapshots are cropped and arranged here. Needs `cwebp` (Homebrew:
// `brew install webp`) for the WebP files. The game sounds while it runs.
//
// The action shots depend on timing (a launched ball, multiball): look at
// the results, and run the script again if a shot missed its moment.
import AppKit

let app = "dist/Nova Rush.app/Contents/MacOS/NovaRush"
let outDir = URL(fileURLWithPath: "Images", isDirectory: true)
let work = FileManager.default.temporaryDirectory.appendingPathComponent("novarush-readme-\(getpid())")

guard FileManager.default.isExecutableFile(atPath: app) else {
    print("error: \(app) not found — run Scripts/build-app.sh first"); exit(1)
}
let searchPath = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
let cwebp = searchPath.split(separator: ":").map { "\($0)/cwebp" }.first {
    FileManager.default.isExecutableFile(atPath: $0)
}
guard let cwebp else { print("error: cwebp not found — brew install webp"); exit(1) }
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: Snapshots

/// A snapshot run: name → arguments (besides --snapshot).
let shots: [(String, [String])] = [
    ("attract", ["--attract", "--nohint", "--wait", "0.5"]),
    ("skill", ["--plunge", "0.80", "--when", "1", "--nohint", "--wait", "2.6"]),
    ("multiball", ["--plunge", "0.80", "--when", "1", "--multiball", "3.3", "--nohint", "--wait", "4.9"]),
    ("guard", ["--guards", "1", "--drop", "30", "345", "--nohint", "--wait", "1.05"]),
    ("map", ["--nohint", "--wait", "1.0", "--helpmap", work.appendingPathComponent("map.png").path]),
]
/// Attract-show rule teasers (seconds into the show at launch).
let teasers: [(String, Double)] = [
    ("t-skill", 8.8), ("t-guards", 12.6), ("t-combos", 24.6),
    ("t-extraball", 28.6), ("t-multiball", 40.6), ("t-modes", 56.6),
]

func run(_ args: [String]) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: app)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try! p.run()
    return p
}
func snapshotPath(_ name: String) -> String { work.appendingPathComponent("\(name).png").path }

print("Rendering snapshots…")
// The action shots one at a time (physics timing), the attract teasers side by side.
for (name, args) in shots { run(args + ["--snapshot", snapshotPath(name)]).waitUntilExit() }
let parallel = teasers.map { run(["--attract", "--nohint", "--wait", "\($0.1)", "--snapshot", snapshotPath($0.0)]) }
for p in parallel { p.waitUntilExit() }

// MARK: Drawing helpers

func load(_ name: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: snapshotPath(name))?
        .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("error: snapshot \(name) missing"); exit(1)
    }
    return image
}

/// Part of a snapshot, in scene points (500 × 1000, origin bottom left).
func crop(_ image: CGImage, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGImage {
    let s = CGFloat(image.width) / 500
    return image.cropping(to: CGRect(x: x * s, y: (1000 - y - h) * s, width: w * s, height: h * s))!
}

let rail = CGColor(srgbRed: 0.50, green: 0.53, blue: 0.75, alpha: 0.55)

/// Draws `image` into `rect` with rounded corners and a thin rail-coloured rim.
func tile(_ ctx: CGContext, _ image: CGImage, _ rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    let rim = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: radius - 1,
                     cornerHeight: radius - 1, transform: nil)
    ctx.addPath(rim)
    ctx.setStrokeColor(rail)
    ctx.setLineWidth(2)
    ctx.strokePath()
}

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

/// Writes Images/<name>.webp (via a temporary PNG).
func save(_ image: CGImage, _ name: String) {
    let png = work.appendingPathComponent("out-\(name).png")
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: png)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cwebp)
    p.arguments = ["-quiet", "-q", "90", "-alpha_q", "100", png.path,
                   "-o", outDir.appendingPathComponent("\(name).webp").path]
    try! p.run()
    p.waitUntilExit()
    print("  Images/\(name).webp  \(image.width)×\(image.height)")
}

print("Composing…")

// Hero: attract show · super skill shot · multiball, side by side.
do {
    let panels = ["attract", "skill", "multiball"].map(load)
    let w = 600, h = 1200, gap = 36
    save(canvas(3 * w + 2 * gap, h) { ctx in
        for (i, image) in panels.enumerated() {
            tile(ctx, image, CGRect(x: i * (w + gap), y: 0, width: w, height: h), radius: 26)
        }
    }, "hero")
}

// The Help window's table map with its numbered badges.
do {
    let map = NSImage(contentsOfFile: work.appendingPathComponent("map.png").path)!
        .cgImage(forProposedRect: nil, context: nil, hints: nil)!
    save(map, "table-map")
}

// Attract-show teasers: the display panel of six pages, 3 × 2.
do {
    let pages = teasers.map { crop(load($0.0), x: 105, y: 495, w: 290, h: 160) }
    let w = pages[0].width, h = pages[0].height, gap = 20
    save(canvas(3 * w + 2 * gap, 2 * h + gap) { ctx in
        for (i, page) in pages.enumerated() {
            let col = i % 3, row = 1 - i / 3
            tile(ctx, page, CGRect(x: col * (w + gap), y: row * (h + gap), width: w, height: h), radius: 18)
        }
    }, "attract-show")
}

// Outlane guard: the arch kicking a ball back up, with the countdown.
do {
    let close = crop(load("guard"), x: 0, y: 0, w: 230, h: 420)
    save(canvas(close.width, close.height) { ctx in
        tile(ctx, close, CGRect(x: 0, y: 0, width: close.width, height: close.height), radius: 22)
    }, "outlane-guard")
}

try? FileManager.default.removeItem(at: work)
print("Done.")
