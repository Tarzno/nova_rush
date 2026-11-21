import SpriteKit

/// Visual for a one-way gate: a thin hinged metal wire that swings open
/// when the ball passes from below and hangs shut otherwise, with a faint
/// chevron marking the pass direction. Purely cosmetic — the physics is a
/// toggled edge body owned by the scene.
final class GateFlap: SKNode {
    private let flap = SKShapeNode()
    private let swingAngle: CGFloat
    private var isOpen = false

    init(hinge: CGPoint, tip: CGPoint, swing: CGFloat, chevronAt: CGPoint,
         chevronRotation: CGFloat = 0) {
        swingAngle = swing
        super.init()
        position = hinge
        zPosition = 7

        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: tip.x - hinge.x, y: tip.y - hinge.y))
        flap.path = path
        flap.strokeColor = NSColor(calibratedRed: 0.82, green: 0.88, blue: 1.0, alpha: 0.95)
        flap.lineWidth = 3
        flap.lineCap = .round
        addChild(flap)

        let hingeDot = SKShapeNode(circleOfRadius: 4)
        hingeDot.fillColor = NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.66, alpha: 1)
        hingeDot.strokeColor = NSColor(calibratedRed: 0.82, green: 0.88, blue: 1.0, alpha: 0.9)
        hingeDot.lineWidth = 1.5
        addChild(hingeDot)

        let chevron = SKShapeNode()
        let c = CGMutablePath()
        c.move(to: CGPoint(x: -7, y: -5))
        c.addLine(to: CGPoint(x: 0, y: 3))
        c.addLine(to: CGPoint(x: 7, y: -5))
        chevron.path = c
        chevron.strokeColor = NSColor(calibratedRed: 0.21, green: 0.89, blue: 1.0, alpha: 0.45)
        chevron.lineWidth = 2.5
        chevron.lineCap = .round
        chevron.lineJoin = .round
        chevron.position = CGPoint(x: chevronAt.x - hinge.x, y: chevronAt.y - hinge.y)
        chevron.zRotation = chevronRotation
        addChild(chevron)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        // Snappy push-open, slower swing shut — like a real wire gate.
        flap.run(.rotate(toAngle: open ? swingAngle : 0,
                         duration: open ? 0.05 : 0.22,
                         shortestUnitArc: true))
    }
}
