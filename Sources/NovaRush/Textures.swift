import SpriteKit

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Procedurally drawn textures — no bitmap assets anywhere in the project.
enum Textures {
    static func chromeBall(diameter: CGFloat) -> SKTexture {
        let px = Int(diameter * 4)
        let img = draw(size: CGSize(width: px, height: px)) { ctx, size in
            let r = size.width / 2
            let colors = [
                NSColor.white.cgColor,
                NSColor(calibratedRed: 0.68, green: 0.73, blue: 0.81, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.27, green: 0.31, blue: 0.40, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 0.45, 1])!
            ctx.addEllipse(in: CGRect(origin: .zero, size: size))
            ctx.clip()
            ctx.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: r * 0.7, y: r * 1.3), startRadius: 0,
                endCenter: CGPoint(x: r, y: r), endRadius: r,
                options: .drawsAfterEndLocation)
        }
        return SKTexture(cgImage: img)
    }

    /// Soft radial dot for particle effects.
    static func particleDot() -> SKTexture {
        let img = draw(size: CGSize(width: 32, height: 32)) { ctx, size in
            let colors = [
                NSColor.white.cgColor,
                NSColor(calibratedWhite: 1, alpha: 0).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: size.width / 2, options: [])
        }
        return SKTexture(cgImage: img)
    }

    static func bumperDome(diameter: CGFloat) -> SKTexture {
        let px = Int(diameter * 4)
        let img = draw(size: CGSize(width: px, height: px)) { ctx, size in
            let r = size.width / 2
            let colors = [
                NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.92, alpha: 1).cgColor,
                NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.65, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.45, green: 0.08, blue: 0.30, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 0.55, 1])!
            ctx.addEllipse(in: CGRect(origin: .zero, size: size))
            ctx.clip()
            ctx.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: r * 0.85, y: r * 1.2), startRadius: 0,
                endCenter: CGPoint(x: r, y: r), endRadius: r,
                options: .drawsAfterEndLocation)
        }
        return SKTexture(cgImage: img)
    }

    /// Playfield surface. With `art` (the generated backdrop skin) the image
    /// is aspect-filled into the silhouette and dimmed so the vector table
    /// parts stay readable; rendered at 4× so it stays sharp when the window
    /// is enlarged. Without art: the procedural gradient + star dots.
    static func playfield(size: CGSize, silhouette: CGPath, art: CGImage? = nil,
                          dim: CGFloat = 0.3) -> SKTexture {
        let scale: CGFloat = art == nil ? 2 : 4
        let img = draw(size: CGSize(width: size.width * scale, height: size.height * scale)) { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.addPath(silhouette)
            ctx.clip()
            if let art {
                let ar = CGFloat(art.width) / CGFloat(art.height)
                var r = CGRect(origin: .zero, size: size)
                if ar > size.width / size.height {
                    r.size.width = size.height * ar; r.origin.x = (size.width - r.width) / 2
                } else {
                    r.size.height = size.width / ar; r.origin.y = (size.height - r.height) / 2
                }
                ctx.interpolationQuality = .high
                ctx.draw(art, in: r)
                ctx.setFillColor(NSColor(calibratedRed: 0.01, green: 0.015, blue: 0.04, alpha: dim).cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                return
            }
            let colors = [
                NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.32, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.19, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])

            var rng = SeededRNG(state: 7)
            ctx.setFillColor(NSColor.white.cgColor)
            for _ in 0..<70 {
                let x = CGFloat.random(in: 10...(size.width - 10), using: &rng)
                let y = CGFloat.random(in: 20...(size.height - 20), using: &rng)
                let r = CGFloat.random(in: 0.5...1.4, using: &rng)
                ctx.setAlpha(CGFloat.random(in: 0.2...0.6, using: &rng))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
            }
        }
        return SKTexture(cgImage: img)
    }

    private static func draw(size: CGSize, _ body: (CGContext, CGSize) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(ctx, size)
        return ctx.makeImage()!
    }
}
