import SpriteKit

/// A flipper is a dynamic body pinned to a static anchor. Driving its
/// angular velocity (instead of animating rotation) makes the physics
/// engine transfer real momentum to the ball — live catches and slap
/// shots both fall out of this for free.
final class Flipper {
    enum Side { case left, right }

    let node: SKShapeNode
    private let side: Side

    init(side: Side) {
        self.side = side
        let path = CGMutablePath()
        path.addLines(between: Flipper.polygon(side: side))
        path.closeSubpath()

        let shape = SKShapeNode(path: path)
        shape.fillColor = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.30, alpha: 1)
        shape.strokeColor = shape.fillColor
        shape.lineWidth = 7
        shape.lineJoin = .round
        shape.zPosition = 9
        shape.zRotation = side == .left ? -L.flipperRestAngle : L.flipperRestAngle

        let body = SKPhysicsBody(polygonFrom: path)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = true
        body.mass = 4.0    // heavy bat: a resting ball takes the full stroke
        body.friction = 0.9          // rubber: lets the ball be caught
        body.restitution = 0.25
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Cat.flipper
        body.collisionBitMask = Cat.ball
        shape.physicsBody = body

        node = shape
    }

    /// Tapered bat, pivot at origin, extending toward the drain center.
    private static func polygon(side: Side) -> [CGPoint] {
        var pts: [CGPoint] = [
            CGPoint(x: -13, y: 0), CGPoint(x: -8, y: -10), CGPoint(x: 62, y: -6),
            CGPoint(x: 70, y: 0), CGPoint(x: 62, y: 6), CGPoint(x: -8, y: 10),
        ]
        if side == .right {
            pts = pts.map { CGPoint(x: -$0.x, y: $0.y) }.reversed()
        }
        return pts
    }

    func add(to field: SKNode, in scene: SKScene, pivotInField pivot: CGPoint) {
        node.position = pivot
        field.addChild(node)

        let anchorNode = SKNode()
        anchorNode.position = pivot
        let anchorBody = SKPhysicsBody(circleOfRadius: 2)
        anchorBody.isDynamic = false
        anchorBody.categoryBitMask = 0
        anchorBody.collisionBitMask = 0
        anchorNode.physicsBody = anchorBody
        field.addChild(anchorNode)

        // SpriteKit's pin-joint limits only behave reliably in the
        // [negative, 0] range, so the left flipper (which sweeps in the
        // positive direction) gets the body order swapped to flip the
        // joint's sign convention.
        let anchorPoint = scene.convert(pivot, from: field)
        let joint = side == .left
            ? SKPhysicsJointPin.joint(withBodyA: node.physicsBody!, bodyB: anchorBody,
                                      anchor: anchorPoint)
            : SKPhysicsJointPin.joint(withBodyA: anchorBody, bodyB: node.physicsBody!,
                                      anchor: anchorPoint)
        joint.shouldEnableLimits = true
        joint.lowerAngleLimit = -L.flipperStroke
        joint.upperAngleLimit = 0
        joint.frictionTorque = 0
        scene.physicsWorld.add(joint)
    }

    func drive(pressed: Bool) {
        guard let body = node.physicsBody else { return }
        let dir: CGFloat = side == .left ? 1 : -1
        let rest = -dir * L.flipperRestAngle
        let raised = rest + dir * L.flipperStroke
        let travel = pressed
            ? dir * (raised - node.zRotation)
            : dir * (node.zRotation - rest)
        if travel <= Tuning.flipperHoldBand {
            // Pinned at the end stop: press gently so the bat holds position
            // but a resting ball sees an (almost) motionless surface and can
            // settle. Commanding full speed here would make every contact
            // read full stroke velocity — cradling would be impossible.
            body.angularVelocity = (pressed ? dir : -dir) * Tuning.flipperHoldOmega
        } else {
            body.angularVelocity = (pressed ? dir : -dir)
                * (pressed ? Tuning.flipOmega : Tuning.returnOmega)
        }
    }
}
