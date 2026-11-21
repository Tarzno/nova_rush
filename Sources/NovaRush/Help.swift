import AppKit

/// Help → Nova Rush Help: the in-app manual. Styled rich text (14 pt body,
/// headings, key caps, aligned scoring table) with a table map that the game
/// renders from its own live playfield each time the window opens — numbered
/// badges on the map match the numbered sections of the table tour. Keep the
/// rules here in sync with the game (values come from `Score` / `Tuning`).
enum HelpManual {
    // MARK: Map markers (field coordinates; badge drawn at the point)

    struct Marker { let number: Int; let at: CGPoint }

    static let markers: [Marker] = [
        Marker(number: 1, at: CGPoint(x: 445, y: 150)),   // plunger lane
        Marker(number: 2, at: CGPoint(x: 220, y: 920)),   // NOVA lanes
        Marker(number: 3, at: CGPoint(x: 215, y: 820)),   // bumpers
        Marker(number: 4, at: CGPoint(x: 320, y: 470)),   // ramp mouth
        Marker(number: 5, at: CGPoint(x: 20, y: 730)),    // left orbit
        Marker(number: 6, at: CGPoint(x: 48, y: 382)),    // wormhole (left)
        Marker(number: 6, at: CGPoint(x: 245, y: 645)),   // wormhole (centre)
        Marker(number: 7, at: CGPoint(x: 368, y: 632)),   // saucer
        Marker(number: 8, at: CGPoint(x: 140, y: 520)),   // drop targets
        Marker(number: 9, at: CGPoint(x: 400, y: 470)),   // standups
        Marker(number: 10, at: CGPoint(x: 110, y: 215)),  // slingshot
        Marker(number: 10, at: CGPoint(x: 320, y: 215)),  // slingshot
        Marker(number: 11, at: CGPoint(x: 215, y: 105)),  // flippers
        Marker(number: 12, at: CGPoint(x: 22, y: 200)),   // outlane guard (left)
        Marker(number: 12, at: CGPoint(x: 408, y: 200)),  // outlane guard (right)
    ]

    // MARK: Colours (the table's own)

    static let amber = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.30, alpha: 1)
    static let cyan = NSColor(calibratedRed: 0.21, green: 0.75, blue: 0.95, alpha: 1)
    static let magenta = NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.65, alpha: 1)
    static let violet = NSColor(calibratedRed: 0.62, green: 0.42, blue: 1.0, alpha: 1)

    // MARK: Images

    /// Amber number badge — used on the map and in the text.
    static func badge(_ n: Int, diameter d: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            amber.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor(calibratedWhite: 0.08, alpha: 0.9).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1
            ring.stroke()
            let s = "\(n)" as NSString
            let font = NSFont.systemFont(ofSize: d * (n > 9 ? 0.48 : 0.58), weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                   withAttributes: attrs)
            return true
        }
    }

    /// Margin (field points) rendered around the playfield, so the outer
    /// walls show completely. Pass to `GameScene.playfieldImage(margin:)`.
    static let mapMargin: CGFloat = 6

    /// The playfield with numbered badges, sized `width` points wide.
    static func mapImage(playfield: CGImage, width: CGFloat) -> NSImage {
        let m = mapMargin
        let height = width * (L.H + 2 * m) / (L.W + 2 * m)
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let clip = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            clip.addClip()
            NSGraphicsContext.current?.cgContext.draw(playfield, in: rect)
            let k = width / (L.W + 2 * m)
            let d: CGFloat = 26
            for marker in markers {
                let c = CGPoint(x: (marker.at.x + m) * k, y: (marker.at.y + m) * k)
                let r = NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = 4
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
                shadow.set()
                badge(marker.number, diameter: d).draw(in: r)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
    }

    // MARK: Text

    private static let bodySize: CGFloat = 14

    private static func para(spacingBefore: CGFloat = 0, after: CGFloat = 6,
                             indent: CGFloat = 0, tabs: [NSTextTab] = [],
                             align: NSTextAlignment = .left) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = after
        p.lineSpacing = 2
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        p.tabStops = tabs
        p.alignment = align
        return p
    }

    /// Builds the manual. `playfield` is the live table render (nil → no map).
    static func text(playfield: CGImage?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: bodySize)
        let bold = NSFont.systemFont(ofSize: bodySize, weight: .semibold)
        let label = NSColor.labelColor
        let secondary = NSColor.secondaryLabelColor

        func add(_ s: String, _ font: NSFont = body, color: NSColor = label,
                 style: NSParagraphStyle = para()) {
            out.append(NSAttributedString(string: s, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        /// Inline mini-markup: **bold** spans.
        func rich(_ s: String, style: NSParagraphStyle = para(), color: NSColor = label) {
            for (i, part) in s.components(separatedBy: "**").enumerated() {
                add(part, i % 2 == 1 ? bold : body, color: color, style: style)
            }
        }
        func heading(_ s: String, accent: NSColor) {
            add("\n", NSFont.systemFont(ofSize: 6), style: para(after: 0))
            add("▍", NSFont.systemFont(ofSize: 20, weight: .bold), color: accent, style: para(spacingBefore: 10, after: 8))
            add(s + "\n", NSFont.systemFont(ofSize: 20, weight: .bold), style: para(spacingBefore: 10, after: 8))
        }
        func subheading(_ s: String, color: NSColor = label) {
            add(s + "\n", NSFont.systemFont(ofSize: 16, weight: .bold), color: color,
                style: para(spacingBefore: 8, after: 4))
        }
        func image(_ img: NSImage, centered: Bool = true, style: NSParagraphStyle? = nil) {
            let a = NSTextAttachment()
            a.image = img
            a.bounds = NSRect(origin: .zero, size: img.size)
            let s = NSMutableAttributedString(attachment: a)
            s.addAttribute(.paragraphStyle, value: style ?? para(after: 10, align: centered ? .center : .left),
                           range: NSRange(location: 0, length: s.length))
            out.append(s)
        }
        func numbered(_ n: Int, _ title: String, _ text: String) {
            let style = para(after: 9, indent: 30, tabs: [NSTextTab(textAlignment: .left, location: 30)])
            let first = NSMutableParagraphStyle()
            first.setParagraphStyle(style)
            first.firstLineHeadIndent = 0
            let a = NSTextAttachment()
            a.image = badge(n, diameter: 20)
            a.bounds = NSRect(x: 0, y: -4, width: 20, height: 20)
            let s = NSMutableAttributedString(attachment: a)
            s.addAttribute(.paragraphStyle, value: first, range: NSRange(location: 0, length: s.length))
            out.append(s)
            add("\t", style: first)
            add(title + " — ", bold, style: first)
            rich(text + "\n", style: first)
        }
        /// Key-cap styled key names, then the action.
        func keyRow(_ keys: [String], _ action: String) {
            let style = para(after: 7, tabs: [NSTextTab(textAlignment: .left, location: 210)])
            for (i, key) in keys.enumerated() {
                if i > 0 { add("  ", style: style) }
                out.append(NSAttributedString(string: "\u{2009}\(key)\u{2009}", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .semibold),
                    .foregroundColor: label,
                    .backgroundColor: NSColor.quaternaryLabelColor,
                    .paragraphStyle: style,
                ]))
            }
            add("\t" + action + "\n", style: style)
        }
        func scoreRow(_ what: String, _ points: String, note: String = "") {
            let style = para(after: 4, tabs: [NSTextTab(textAlignment: .right, location: 330),
                                              NSTextTab(textAlignment: .left, location: 345)])
            add(what, style: style)
            add("\t" + points, NSFont.monospacedDigitSystemFont(ofSize: bodySize, weight: .semibold), style: style)
            add((note.isEmpty ? "" : "\t" + note) + "\n", color: secondary, style: style)
        }

        // Title
        add("NOVA RUSH\n", NSFont.systemFont(ofSize: 30, weight: .heavy),
            style: para(after: 2, align: .center))
        add("How to play\n", NSFont.systemFont(ofSize: 15), color: secondary,
            style: para(after: 16, align: .center))
        if let playfield {
            image(mapImage(playfield: playfield, width: 300))
            add("\n", style: para(after: 6, align: .center))
            add("The table — numbers refer to the Table tour below.\n",
                NSFont.systemFont(ofSize: 12), color: secondary, style: para(after: 6, align: .center))
        }

        heading("Controls", accent: cyan)
        keyRow(["Ctrl", "Left ⇧", "←"], "Left flipper")
        keyRow(["Right ⇧", "→"], "Right flipper")
        keyRow(["Space", "↓"], "Plunger — hold to pull, release to launch")
        keyRow(["Space", "Return"], "Start a game (between games)")
        keyRow(KeyLabels.nudge, "Nudge from left · front · right (careful: TILT!)")
        keyRow(["P"], "Pause / resume")
        keyRow(["C"], "Continuous play (practice) on / off")
        keyRow(["M"], "Music on / off")
        keyRow(["V"], "Voice callouts on / off")
        keyRow(["B"], "Backdrop art on / off")
        keyRow(["R"], "New game")
        keyRow(["⌘ ?"], "This help")

        heading("The basics", accent: amber)
        rich("Between games the table runs its **attract show** — rule teasers, high scores and "
             + "a light show; the flipper buttons page through it. Press **Space** (or Return) "
             + "to start a game.\n")
        rich("You have **3 balls**. Pull the plunger with Space and release to launch. "
             + "A ball that drains within **8 seconds** of launch is returned for free (ball saver).\n")
        rich("Almost everything you hit adds to your **end-of-ball bonus**, paid out — times the "
             + "**bonus multiplier** — when the ball drains.\n")
        rich("A gentle nudge can save a ball, but too much shaking **tilts** the table: flippers "
             + "and kickers go dead, the outlane guards drop and that ball's bonus is lost.\n")
        rich("**Continuous play** (C) is for practice: no ball limit and no scoring, so it can't "
             + "touch the high scores.\n")

        heading("Table tour", accent: magenta)
        numbered(1, "Plunger lane", "Hold Space to pull, release to launch. The pull decides "
                 + "how far the ball travels across the top (see Skill shot).")
        numbered(2, "NOVA lanes", "Roll through all four letters to score **NOVA**: it raises the "
                 + "**bonus multiplier** (up to ×8) and puts the outlane guards back up.")
        numbered(3, "Pop bumpers", "Three bumpers kick the ball around the upper field.")
        numbered(4, "Comet ramp", "Its mouth sits mid-right. A firm shot climbs the ramp, rips the "
                 + "ramp spinner and drops the ball back into the left inlane. Weak shots stall "
                 + "and roll back.")
        numbered(5, "Left orbit", "Shoot up the left wall, through the spinner and the one-way gate, "
                 + "round the top into the NOVA lanes.")
        numbered(6, "Wormholes", "A linked pair: one on the left wall, one under the middle bumper. "
                 + "A slow ball is swallowed and comes out again — sometimes from the **other** hole.")
        numbered(7, "Nebula saucer", "The right pocket under the ramp. Starts modes, locks balls "
                 + "for multiball and collects the Extra Ball.")
        numbered(8, "Drop targets", "Three cyan targets mid-left. Clear the bank to light **MODE** "
                 + "at the saucer.")
        numbered(9, "Standup targets", "Three magenta targets on the right. Hit all three to light "
                 + "**LOCK** at the saucer.")
        numbered(10, "Slingshots", "Kick the ball back into play. Their lights flash with the "
                 + "big moments of the game.")
        numbered(11, "Flippers & inlanes", "Inlanes feed the ball to a flipper; outlanes on the far "
                 + "sides are trouble. A fast ball can ride the bottom arc **around the horn** "
                 + "and come back up the other side.")
        numbered(12, "Outlane guards", "A steel arch pops up in the middle of each outlane and kicks "
                 + "the ball back into the inlane. The guards are up for the first "
                 + "**\(Int(Tuning.guardTime)) seconds** of every ball — the GUARDS counter in the lower "
                 + "left corner shows the time left, and the arches blink before they drop — and "
                 + "**spelling NOVA** raises them again. A tilt drops them at once.")

        heading("Special shots", accent: violet)
        subheading("Skill shot")
        rich("When a new ball reaches the plunger, one NOVA letter **flashes orange** — that's "
             + "your target. Aim with the pull: a little under half → **A**, a bit more → **V**, "
             + "more → **O**, a full pull → **N**. Hit the flashing lane first: **10,000** for N, "
             + "**25,000** (super skill shot) for O, V or A.\n")
        subheading("Combos")
        rich("The **ramp** and the **left orbit** are the major shots. Make another major shot "
             + "within **5 seconds** to build a combo: ×2 scores **5,000**, ×3 **10,000**, and "
             + "so on. While a combo is live the ramp and orbit arrows blink white.\n")
        subheading("Wormholes & warp", color: violet)
        rich("Each capture scores **2,500**. In 40% of captures the ball **warps** and comes out of "
             + "the other hole for another **2,500**. After ejecting, a hole closes briefly.\n")
        subheading("Extra Ball", color: amber)
        rich("Get the ball swallowed by **both** wormholes during one ball: an amber ring marks each "
             + "visited hole, and EXTRA BALL lights at the saucer. Collect it there for a "
             + "**shoot again** — the next drain replays the same ball. Up to 2 per game.\n")
        subheading("Multiball & jackpot", color: magenta)
        rich("Light LOCK (standups) and lock a ball in the saucer — twice. The next saucer shot "
             + "starts **3-ball multiball**: every ramp is a **25,000 jackpot** while it lasts.\n")
        subheading("Modes", color: cyan)
        rich("Clear the drop targets to light MODE, then hit the saucer for a random "
             + "**30-second** mode:\n")
        let bullet = para(after: 4, indent: 18)
        rich("• **Asteroid Storm** — bumpers score 1,000\n", style: bullet)
        rich("• **Solar Flare** — spinners 500 per spin, ramp 5,000\n", style: bullet)
        rich("• **Gravity Well** — drop targets 2,500, saucer 10,000\n", style: para(after: 8, indent: 18))

        heading("Scoring", accent: amber)
        scoreRow("Slingshot", "10")
        scoreRow("Pop bumper", "100")
        scoreRow("Spinner", "100", note: "per spin")
        scoreRow("Standup target", "300", note: "set of 3: 3,000")
        scoreRow("NOVA lane", "500")
        scoreRow("Drop target", "500", note: "bank: 5,000")
        scoreRow("Comet ramp", "1,000")
        scoreRow("Saucer", "1,500")
        scoreRow("Wormhole", "2,500", note: "warp: +2,500")
        scoreRow("NOVA complete", "5,000", note: "× multiplier")
        scoreRow("Ball lock", "5,000")
        scoreRow("Combo", "5,000", note: "× (combo − 1)")
        scoreRow("Skill shot", "10,000", note: "super: 25,000")
        scoreRow("Jackpot (multiball)", "25,000")

        heading("Tips", accent: cyan)
        rich("• **Cradle** the ball: hold a flipper up, let the ball settle, release and flip again "
             + "as it reaches the tip — that's your aimed shot.\n", style: bullet)
        rich("• A full plunge is the easy skill shot when **N** is flashing.\n", style: bullet)
        rich("• While the outlane guards are up, play boldly — then go for NOVA to keep them up.\n",
             style: bullet)
        rich("• Ramp → orbit → ramp is the classic combo route.\n", style: bullet)
        rich("• Slow balls dropping out of the bumpers often find the centre wormhole.\n",
             style: para(after: 4, indent: 18))
        return out
    }
}

/// The Help window: rebuilt on every open so the map shows the current table.
final class HelpWindowController: NSWindowController {
    private var textView: NSTextView!

    convenience init() {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: min(860, visible - 60)),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Nova Rush Help"
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.textContainerInset = NSSize(width: 32, height: 26)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        window.contentView = scroll
        window.center()
        textView = tv
    }

    func show(playfield: CGImage?) {
        textView.textStorage?.setAttributedString(HelpManual.text(playfield: playfield))
        textView.scrollToBeginningOfDocument(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The whole manual as one tall PDF page (verification aid).
    func pdfData() -> Data {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()
        return textView.dataWithPDF(inside: textView.bounds)
    }
}
