import SpriteKit

/// Decorative "lit plastic" for a slingshot: translucent violet plastic with
/// a Nova-star motif (chosen over a comet in a side-by-side test), a light
/// layer underneath that flashes on game events, and three
/// lamp dots along the kicking face. Pure vector (scales with the window);
/// physics stay on the sling's own shape node, which draws the magenta frame
/// on top of this.
final class SlingPlastic: SKNode {
    private let flashLight: SKShapeNode   // event flashes (hits, jackpot, …)
    private let pulseLight: SKShapeNode   // long-running patterns (multiball, attract)
    private var lamps: [SKShapeNode] = []
    private let lampColor: NSColor
    private let lampDim: CGFloat = 0.3

    /// `points`: triangle vertices [top, kicking-face bottom tip, outer bottom]
    /// — the kicking face is points[0] → points[1].
    init(points p: [CGPoint], frameColor: NSColor) {
        lampColor = frameColor
        let path = CGMutablePath()
        path.addLines(between: p)
        path.closeSubpath()

        // Incenter: the roomiest point of a narrow triangle.
        let a = hypot(p[1].x - p[2].x, p[1].y - p[2].y)
        let b = hypot(p[2].x - p[0].x, p[2].y - p[0].y)
        let c = hypot(p[0].x - p[1].x, p[0].y - p[1].y)
        let inc = CGPoint(x: (a * p[0].x + b * p[1].x + c * p[2].x) / (a + b + c),
                          y: (a * p[0].y + b * p[1].y + c * p[2].y) / (a + b + c))

        flashLight = SKShapeNode(path: path)
        pulseLight = SKShapeNode(path: path)
        super.init()

        let crop = SKCropNode()
        let mask = SKShapeNode(path: path)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        addChild(crop)

        // Plastic: smoky violet, lighter toward the core (a cheap gradient).
        let base = SKShapeNode(path: path)
        base.fillColor = NSColor(calibratedRed: 0.17, green: 0.07, blue: 0.30, alpha: 0.92)
        base.strokeColor = .clear
        crop.addChild(base)
        let core = SKShapeNode(path: Self.scaled(path, about: inc, by: 0.6))
        core.fillColor = NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.62, alpha: 0.35)
        core.strokeColor = .clear
        crop.addChild(core)

        // Lights under the motif (additive, invisible until driven).
        for light in [pulseLight, flashLight] {
            light.fillColor = frameColor
            light.strokeColor = .clear
            light.blendMode = .add
            light.alpha = 0
            crop.addChild(light)
        }

        // Motif: Nova star — white 4-point star, small amber star at 45°, soft glow.
        let center = CGPoint(x: inc.x + 0.12 * (p[0].x - inc.x), y: inc.y + 0.12 * (p[0].y - inc.y))
        let glow = SKShapeNode(circleOfRadius: 7)
        glow.position = center
        glow.fillColor = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.85, alpha: 0.25)
        glow.strokeColor = .clear
        glow.blendMode = .add
        crop.addChild(glow)
        let big = SKShapeNode(path: Self.star(points: 4, outer: 11, inner: 2.6, rotation: 0))
        big.position = center
        big.fillColor = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.96, alpha: 0.95)
        big.strokeColor = .clear
        crop.addChild(big)
        let small = SKShapeNode(path: Self.star(points: 4, outer: 5.5, inner: 1.6, rotation: .pi / 4))
        small.position = center
        small.fillColor = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.30, alpha: 0.9)
        small.strokeColor = .clear
        crop.addChild(small)

        // Lamp dots along the kicking face, set in toward the incenter.
        for t in [0.25, 0.5, 0.75] as [CGFloat] {
            let onFace = CGPoint(x: p[1].x + t * (p[0].x - p[1].x), y: p[1].y + t * (p[0].y - p[1].y))
            let dx = inc.x - onFace.x, dy = inc.y - onFace.y, d = max(hypot(dx, dy), 0.001)
            let lamp = SKShapeNode(circleOfRadius: 2.2)
            lamp.position = CGPoint(x: onFace.x + dx / d * 4.5, y: onFace.y + dy / d * 4.5)
            lamp.fillColor = frameColor
            lamp.strokeColor = .clear
            lamp.alpha = lampDim
            crop.addChild(lamp)
            lamps.append(lamp)       // ordered bottom → top (for the chase)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Light behaviours

    /// Quick flash(es) of the light layer and lamps in `color`.
    func flash(_ color: NSColor, times: Int = 1, intensity: CGFloat = 0.85) {
        flashLight.fillColor = color
        flashLight.removeAction(forKey: "flash")
        let one = SKAction.sequence([.fadeAlpha(to: intensity, duration: 0.03),
                                     .fadeAlpha(to: 0, duration: 0.2)])
        flashLight.run(.repeat(one, count: times), withKey: "flash")
        for lamp in lamps where lamp.action(forKey: "chase") == nil {
            lamp.run(.repeat(.sequence([.fadeAlpha(to: 1, duration: 0.03),
                                        .fadeAlpha(to: lampDim, duration: 0.2)]), count: times),
                     withKey: "flash")
        }
    }

    /// Multiball: strobe, offset by `phase` so left and right alternate.
    func setStrobe(_ on: Bool, color: NSColor, phase: TimeInterval) {
        pulseLight.removeAction(forKey: "pattern")
        pulseLight.alpha = 0
        guard on else { return }
        pulseLight.fillColor = color
        pulseLight.run(.sequence([.wait(forDuration: phase), .repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.04), .fadeAlpha(to: 0, duration: 0.22),
            .wait(forDuration: 0.24)]))]), withKey: "pattern")
    }

    /// Attract mode: slow breathing glow.
    func setBreathing(_ on: Bool, color: NSColor) {
        pulseLight.removeAction(forKey: "pattern")
        pulseLight.alpha = 0
        guard on else { return }
        pulseLight.fillColor = color
        pulseLight.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 1.0), .fadeAlpha(to: 0.02, duration: 1.0)])),
                       withKey: "pattern")
    }

    /// Combo window: lamps chase upward (pointing at the shots).
    func setChase(_ on: Bool, color: NSColor) {
        for (i, lamp) in lamps.enumerated() {
            lamp.removeAction(forKey: "chase")
            lamp.fillColor = on ? color : lampColor
            lamp.alpha = lampDim
            guard on else { continue }
            lamp.run(.sequence([.wait(forDuration: Double(i) * 0.12), .repeatForever(.sequence([
                .fadeAlpha(to: 1, duration: 0.05), .fadeAlpha(to: lampDim, duration: 0.2),
                .wait(forDuration: 0.11)]))]), withKey: "chase")
        }
    }

    /// Test/snapshot aid: hold the lights on.
    func holdLit(_ color: NSColor) {
        flashLight.fillColor = color
        flashLight.alpha = 0.6
        for lamp in lamps { lamp.alpha = 1 }
    }

    // MARK: Geometry helpers

    private static func scaled(_ path: CGPath, about c: CGPoint, by k: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: k, y: k)
            .translatedBy(x: -c.x, y: -c.y)
        return path.copy(using: &t) ?? path
    }

    private static func star(points n: Int, outer: CGFloat, inner: CGFloat, rotation: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<(2 * n) {
            let r = i % 2 == 0 ? outer : inner
            let a = rotation + .pi / 2 + CGFloat(i) * .pi / CGFloat(n)
            let pt = CGPoint(x: r * cos(a), y: r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

}
