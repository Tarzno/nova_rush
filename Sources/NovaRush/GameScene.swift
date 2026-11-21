import SpriteKit

/// One ball in play. The engine supports several at once (multiball).
private final class BallEntity {
    let node: SKSpriteNode
    let shadow: SKShapeNode
    var onRamp = false
    var railS: CGFloat = 0     // arc position along the ramp rail
    var railV: CGFloat = 0     // signed speed along the rail
    var railLateral: CGFloat = 0  // entry offset from the centerline, eased out
    var stuckSince: TimeInterval = 0
    var searchKicks = 0        // escalating ball-search strength
    var trail: SKEmitterNode?  // comet trail, birthrate follows speed

    init(node: SKSpriteNode, shadow: SKShapeNode) {
        self.node = node
        self.shadow = shadow
    }
}

/// Arc-length parametrised polyline for rail-guided motion.
private struct Rail {
    let points: [CGPoint]
    let lengths: [CGFloat]      // cumulative, lengths[0] = 0
    let total: CGFloat

    init(_ pts: [CGPoint]) {
        points = pts
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count {
            cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))
        }
        lengths = cum
        total = cum.last ?? 0
    }

    private func segment(at s: CGFloat) -> Int {
        var i = 0
        while i < lengths.count - 2 && lengths[i + 1] < s { i += 1 }
        return i
    }

    func position(at s: CGFloat) -> CGPoint {
        let i = segment(at: s)
        let segLen = max(lengths[i + 1] - lengths[i], 0.001)
        let t = min(max((s - lengths[i]) / segLen, 0), 1)
        return CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * t,
                       y: points[i].y + (points[i + 1].y - points[i].y) * t)
    }

    func direction(at s: CGFloat) -> CGVector {
        let i = segment(at: s)
        let dx = points[i + 1].x - points[i].x
        let dy = points[i + 1].y - points[i].y
        let len = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / len, dy: dy / len)
    }

    /// Left-hand unit normal of the rail at `s`.
    func normal(at s: CGFloat) -> CGVector {
        let d = direction(at: s)
        return CGVector(dx: -d.dy, dy: d.dx)
    }
}

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private let field = SKNode()
    private var balls: [BallEntity] = []
    private var ballTexture: SKTexture!
    private let leftFlipper = Flipper(side: .left)
    private let rightFlipper = Flipper(side: .right)
    private var plunger: SKShapeNode!
    private var gateNode = SKNode()
    private var laneGateFlap: GateFlap!
    private var topLeftGateBody: SKPhysicsBody?
    private var topRightGateBody: SKPhysicsBody?
    private var topLeftGateFlap: GateFlap!
    private var topRightGateFlap: GateFlap!
    private let sounds = SoundBank(["flipper", "slingshot", "bumper", "drain", "jackpot",
                                    "target", "drop", "launch", "gameover", "spinner",
                                    "rollover", "saucer", "eject", "lock", "multiball",
                                    "mode", "nudge", "wormhole", "warp", "ramp"])

    // Kickers and targets
    private var bumperNodes: [SKNode] = []
    private var slingNodes: [(node: SKNode, kick: CGVector)] = []
    private var slingPlastics: [SlingPlastic] = []

    private var dropTargets: [SKShapeNode] = []
    private var dropTargetDown: [Bool] = []
    private var standupNodes: [SKShapeNode] = []
    private var standupHit: [Bool] = []
    private var lastKick: [ObjectIdentifier: TimeInterval] = [:]
    private var now: TimeInterval = 0

    // Phase 3 furniture
    private var novaSensors: [SKNode] = []
    private var novaLabels: [SKLabelNode] = []
    private var novaLit: [Bool] = [false, false, false, false]
    private var spinnerBar: SKShapeNode!
    private var rampSpinnerBar: SKShapeNode!
    private var saucerNode: SKShapeNode!
    private var saucerBusy = false
    private var wormholeNodes: [SKShapeNode] = []
    private var wormholeBusy = [false, false]
    // Extra Ball: capture the ball in BOTH wormholes during one ball → lit
    // at the saucer; collecting it banks a "shoot again" (same ball number).
    private var wormholeVisited = [false, false]
    private var wormholeVisitRings: [SKShapeNode] = []
    private var extraBallLit = false
    private var extraBalls = 0            // banked shoot-agains
    private var extraBallsEarned = 0      // this game, capped at Tuning.extraBallsPerGame
    private var extraBallLabel: SKLabelNode!
    // Skill shot: when a fresh ball reaches the plunger, a random NOVA lane
    // is fixed as the target (its letter flashes orange). The pull aims: pull
    // bands map to lanes (Tuning.skillBandLane), and steerSkillBall drops the
    // ball into its band's lane. The first lane rolled through must be the
    // target: 10,000 for N, 25,000 ("super") for O, V or A.
    private var skillLane: Int?            // nil = not armed
    private var skillLaunched = false
    private var skillLaunchTime: TimeInterval = 0
    private var skillAimLane: Int?         // lane the launch's pull band aims at
    private var skillBall: ObjectIdentifier?
    // Combos: major shots (ramp completed, orbit made) chained within
    // Tuning.comboWindow of each other score a growing award.
    private var comboCount = 0                 // shots in the current chain
    private var comboDeadline: TimeInterval = 0
    private var orbitArrow: SKShapeNode!
    private var lastOrbitTime: [ObjectIdentifier: TimeInterval] = [:]
    private var orbitClimbTime: [ObjectIdentifier: TimeInterval] = [:]  // last seen climbing the left orbit lane
    private(set) var comboStatsForTest = (orbits: 0, combos: 0, best: 0)
    /// Chance a wormhole capture warps to the other hole (tests override).
    var wormholeWarpChance = Tuning.wormholeWarpChance
    var lostBallQuipChance = Tuning.lostBallQuipChance
    private(set) var quipsForTest = 0
    // Outlane guards (L.guardPosts): a retractable steel arch in each outlane,
    // up at every new ball, down `guardTime` after the launch or on a tilt,
    // raised again by spelling NOVA. A raised arch kicks a touching ball back
    // into the inlane; a ball climbing the outlane from below (around the
    // horn) passes. The counter in the lower left corner shows the time left.
    private var guardArches: [SKNode] = []       // raised-arch visuals
    private var guardBodies: [SKNode] = []       // physics carriers (category set per frame)
    private var guardsUp = true
    private var guardDeadline: TimeInterval?     // set at launch; nil = not counting
    var guardTime = Tuning.guardTime             // tests shorten it
    private var lastGuardKick: [ObjectIdentifier: TimeInterval] = [:]
    private var guardPassing: [Set<ObjectIdentifier>] = [[], []]   // balls passing each arch from below
    private var guardCounter: SKNode!            // box + title + value
    private var guardCounterValue: SKLabelNode!
    private var ballsInOutlane: Set<ObjectIdentifier> = []
    private(set) var outlaneStatsForTest = (entries: 0, passesFromBelow: 0, saves: 0)
    /// Balls held in a saucer/wormhole awaiting eject: still in play, so a
    /// drain of the last visible ball must not end the ball (multiball).
    private var pendingEjects = 0
    private var rampArrow: SKShapeNode!
    private var flashNode: SKSpriteNode!
    private lazy var sparkTexture = Textures.particleDot()
    private let rampRail = Rail(L.rampRailPoints)
    private var slingRally = 0
    private var lastSlingTime: TimeInterval = 0

    // Game state
    private var score = 0
    private var ballNumber = 1
    private let ballsPerGame = 3
    private var gameOver = false
    private var hintShown = true
    private var bonusUnits = 0
    private var multiplier = 1
    private var ballSaveUntil: TimeInterval = 0
    private var tiltHeat: Double = 0
    private var tilted = false
    private var highScores: [Int] =
        UserDefaults.standard.array(forKey: "highScores") as? [Int] ?? []
    // Attract show: runs whenever no game is in progress — at launch and
    // after game over — until Space / Return / R starts a game.
    /// Launch into the attract show. Verification runs (`--snapshot`
    /// without `--attract`) start a game directly; set before presenting.
    var startInAttract = true
    private var attractRunning = false
    private var attractTitle: SKLabelNode!
    private var attractPanel: SKShapeNode!       // the display the slides appear on
    private var attractText: SKLabelNode!
    private var startPrompt: SKLabelNode!
    private var attractCycle: [AttractSlide] = []
    private var attractIndex = -1                // page of attractCycle on display
    private var attractStep = 0                  // rotates mottos and teasers
    /// Spoken invitation ("Ready for launch, pilot?" …): first one this long
    /// into the show, then about every `every` seconds (tests shorten both).
    var attractVoiceTiming = (first: 60.0, every: 195.0)
    private var attractHighlight: AttractSlide.Highlight?
    private var lastGameScore: Int?              // the show's GAME OVER page
    private var gameOverTime: TimeInterval = -10

    // Modes & multiball
    private enum Mode: CaseIterable {
        case asteroidStorm, solarFlare, gravityWell
        var name: String {
            switch self {
            case .asteroidStorm: return "ASTEROID STORM"
            case .solarFlare: return "SOLAR FLARE"
            case .gravityWell: return "GRAVITY WELL"
            }
        }
        var hint: String {
            switch self {
            case .asteroidStorm: return "BUMPERS 1000"
            case .solarFlare: return "SPINNER + RAMP BIG"
            case .gravityWell: return "TARGETS + SAUCER BIG"
            }
        }
    }
    private var activeMode: Mode?
    private var modeEndTime: TimeInterval = 0
    private var modeLit = false
    private var lockLit = false
    private var locks = 0
    private var multiball = false

    var freePlay = false        // test modes: infinite balls
    private var gamePaused = false
    private var pauseLabel: SKLabelNode!
    /// Continuous play (C): practice mode — no ball limit, no ball
    /// counter, and no scoring.
    private var continuousPlay = false

    // HUD
    private var scoreLabel: SKLabelNode!
    private var ballLabel: SKLabelNode!
    private var modeLabel: SKLabelNode!
    private var statusLabel: SKLabelNode!
    private var hintLabel: SKLabelNode!
    private var messageLabel: SKLabelNode!

    // Input / loop state. Flipper state is recomputed from all sources on
    // every input event — stateless, so a missed event can't wedge a key.
    private var leftShiftDown = false
    private var rightShiftDown = false
    private var ctrlDown = false
    private var leftArrowDown = false
    private var rightArrowDown = false
    private var testLeftDown = false
    private var testRightDown = false
    // In the attract show the flipper buttons also page through the display
    // (left = back, right = next), like on modern machines.
    private var leftPressed = false {
        didSet {
            guard leftPressed && !oldValue else { return }
            sounds.play("flipper", volume: 0.8, pan: -0.4)
            if attractRunning && !gamePaused { turnAttractPage(by: -1) }
        }
    }
    private var rightPressed = false {
        didSet {
            guard rightPressed && !oldValue else { return }
            sounds.play("flipper", volume: 0.8, pan: 0.4)
            if attractRunning && !gamePaused { turnAttractPage(by: 1) }
        }
    }

    /// Timed game events (next ball, ejects, respawns, target resets …) run
    /// on this node, so a new game (R) cancels everything the old one had
    /// scheduled. It is a scene child: pause freezes it like everything else.
    private let gameTimers = SKNode()

    private func later(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        gameTimers.run(.sequence([.wait(forDuration: delay), .run(block)]))
    }

    private func refreshFlipperInputs() {
        leftPressed = ctrlDown || leftShiftDown || leftArrowDown || testLeftDown
        rightPressed = rightShiftDown || rightArrowDown || testRightDown
    }

    private var plungerPressed = false
    private var charge: CGFloat = 0
    private var lastTime: TimeInterval = 0

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 0.024, green: 0.035, blue: 0.075, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: Tuning.gravity)
        physicsWorld.contactDelegate = self

        field.position = L.fieldOrigin
        addChild(field)
        addChild(gameTimers)

        buildBackground()
        buildWalls()
        buildGate()
        buildDrain()
        buildBumpers()
        buildDropTargets()
        buildStandups()
        buildNovaLanes()
        buildOrbit()
        buildSaucer()
        for i in L.wormholeCenters.indices { buildWormhole(i) }
        buildRamp()
        buildFlippers()
        buildPlunger()
        buildHUD()
        if startInAttract {
            gameOver = true             // no game yet: the table invites a player
            refreshHUD()
            startAttract()
        } else {
            spawnBall(at: L.ballSpawn)
            refreshHUD()
        }
        sounds.startMusic()
    }

    // MARK: - Effects

    /// Table-space x → stereo pan.
    private func pan(_ x: CGFloat) -> Float {
        Float((x / L.W) * 1.6 - 0.8)
    }

    private func burst(at p: CGPoint, color: NSColor, count: Int = 16,
                       speed: CGFloat = 160, life: CGFloat = 0.5, size: CGFloat = 6) {
        let e = SKEmitterNode()
        e.particleTexture = sparkTexture
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) / 0.06
        e.particleLifetime = life
        e.particleLifetimeRange = life * 0.5
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.6
        e.yAcceleration = -300
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -1.8
        e.particleSize = CGSize(width: size, height: size)
        e.particleScaleSpeed = -0.7
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.position = p
        e.zPosition = 25
        e.targetNode = field
        field.addChild(e)
        e.run(.sequence([.wait(forDuration: Double(life) + 0.4), .removeFromParent()]))
    }

    private func flash(_ color: NSColor = .white, intensity: CGFloat = 0.16) {
        flashNode.color = color
        flashNode.alpha = intensity
        flashNode.run(.fadeOut(withDuration: 0.3))
    }

    /// What the lamps last showed. refreshHUD runs on every award, so
    /// refreshLamps only touches a lamp whose state changed — restarting the
    /// blinks that often left lit lamps stuck dim during fast scoring, and
    /// undid the attract show's highlights. `force` redraws everything (after
    /// something else drew on the lamps, e.g. an attract highlight).
    private struct LampState: Equatable {
        var saucer = 0               // 0 plain, 1 lock lit, 2 mode lit
        var extraBall = false
        var visited = [false, false]
        var jackpotArrow = false
    }
    private var shownLamps: LampState?

    /// Lamp shows: pulsing inserts reflect what's currently lit.
    private func refreshLamps(force: Bool = false) {
        let want = LampState(saucer: lockLit ? 1 : (modeLit ? 2 : 0), extraBall: extraBallLit,
                             visited: wormholeVisited, jackpotArrow: multiball)
        let old = force ? nil : shownLamps
        guard want != old else { return }
        shownLamps = want

        if want.saucer != old?.saucer {
            saucerNode.removeAction(forKey: "lamp")
            switch want.saucer {
            case 1:
                saucerNode.strokeColor = magentaColor
                saucerNode.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.35, duration: 0.3), .fadeAlpha(to: 1.0, duration: 0.3),
                ])), withKey: "lamp")
            case 2:
                saucerNode.strokeColor = cyanColor
                saucerNode.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.4, duration: 0.45), .fadeAlpha(to: 1.0, duration: 0.45),
                ])), withKey: "lamp")
            default:
                saucerNode.alpha = 1
                saucerNode.strokeColor = amberColor
            }
        }

        if want.extraBall != old?.extraBall {
            extraBallLabel.removeAction(forKey: "lamp")
            extraBallLabel.isHidden = !want.extraBall
            extraBallLabel.alpha = 1
            if want.extraBall {
                extraBallLabel.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.25, duration: 0.25), .fadeAlpha(to: 1.0, duration: 0.25),
                ])), withKey: "lamp")
            }
        }
        if want.visited != old?.visited || want.extraBall != old?.extraBall {
            for (i, ring) in wormholeVisitRings.enumerated() {
                ring.isHidden = !(want.visited[i] || want.extraBall)
            }
        }

        if want.jackpotArrow != old?.jackpotArrow {
            rampArrow.removeAction(forKey: "lamp")
            if want.jackpotArrow {
                rampArrow.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.2, duration: 0.15), .fadeAlpha(to: 1.0, duration: 0.15),
                ])), withKey: "lamp")
            } else {
                rampArrow.alpha = 1
            }
        }
    }

    /// Generated backdrop skin (Resources/Skins/backdrop.jpg), toggled with B
    /// and remembered across launches. `--plain` forces the procedural one.
    private lazy var backdropArt: CGImage? = {
        guard let url = Bundle.resources.url(forResource: "backdrop", withExtension: "jpg",
                                             subdirectory: "Resources/Skins"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }()
    private var backdropEnabled: Bool {
        get { !CommandLine.arguments.contains("--plain") &&
              (UserDefaults.standard.object(forKey: "backdropArt") as? Bool ?? true) }
        set { UserDefaults.standard.set(newValue, forKey: "backdropArt") }
    }
    private var backgroundNode: SKSpriteNode?

    private func buildBackground() {
        backgroundNode?.removeFromParent()
        let tex = Textures.playfield(size: CGSize(width: L.W, height: L.H),
                                     silhouette: L.fieldSilhouette(),
                                     art: backdropEnabled ? backdropArt : nil)
        let bg = SKSpriteNode(texture: tex)
        backgroundNode = bg
        bg.anchorPoint = .zero
        bg.size = CGSize(width: L.W, height: L.H)
        bg.zPosition = -10
        field.addChild(bg)
    }

    private var railColor: NSColor { NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.66, alpha: 1) }
    private var cyanColor: NSColor { NSColor(calibratedRed: 0.21, green: 0.89, blue: 1.0, alpha: 0.9) }
    private var magentaColor: NSColor { NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.65, alpha: 1) }
    private var amberColor: NSColor { NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.30, alpha: 1) }

    private func buildWalls() {
        addWall(L.outerPath(), stroke: railColor, width: 5)
        addWall(L.bottomRightPath(), stroke: railColor, width: 5)
        // Dead wall: balls landing on the bank's backboard should die and
        // dribble off into the inlane, not ricochet into the outlane.
        addWall(L.dropBankBackPath(), stroke: railColor.withAlphaComponent(0.8), width: 4,
                restitution: 0.05, friction: 0.3)
        addWall(L.standupCapPath(), stroke: railColor.withAlphaComponent(0.8), width: 4)


        // Outlane protection bumps (rubber bulges on the walls). Raised
        // high enough that a ball climbing around the horn passes around
        // them into open field — plain solid rubber, no tricks needed.
        for path in L.outlaneBumpPaths() {
            let bump = SKShapeNode(path: path)
            bump.fillColor = amberColor
            bump.strokeColor = NSColor(calibratedRed: 0.75, green: 0.5, blue: 0.2, alpha: 1)
            bump.lineWidth = 2
            bump.zPosition = 6
            let body = SKPhysicsBody(edgeLoopFrom: path)
            body.friction = 0.1
            body.restitution = 0.5   // rubber
            body.categoryBitMask = Cat.wall
            bump.physicsBody = body
            field.addChild(bump)
        }

        for path in L.guidePaths() {
            addWall(path, stroke: cyanColor, width: 4, glow: 1.5)
        }
        buildOutlaneGuards()
        buildSlings()

        // Visible drain hole between the bottom curves' lips.
        let hole = SKShapeNode(rect: CGRect(x: L.holeLipLeft.x + 2, y: 0,
                                            width: L.holeLipRight.x - L.holeLipLeft.x - 4,
                                            height: 14),
                               cornerRadius: 7)
        hole.fillColor = NSColor(calibratedRed: 0.01, green: 0.015, blue: 0.04, alpha: 1)
        hole.strokeColor = railColor.withAlphaComponent(0.6)
        hole.lineWidth = 2
        hole.zPosition = 6
        field.addChild(hole)
    }

    private func addWall(_ path: CGPath, stroke: NSColor, width: CGFloat, glow: CGFloat = 0,
                         restitution: CGFloat = 0.25, friction: CGFloat = 0.08) {
        let node = SKShapeNode(path: path)
        node.strokeColor = stroke
        node.lineWidth = width
        node.lineCap = .round
        node.lineJoin = .round
        node.glowWidth = glow
        node.zPosition = 5
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.friction = friction
        body.restitution = restitution
        body.categoryBitMask = Cat.wall
        node.physicsBody = body
        field.addChild(node)
    }

    private func buildSlings() {
        // Kick directions: up and across, toward the opposite inlane —
        // steeper than the face normal so slings don't fire straight into
        // the opposite outlane.
        let kicks: [CGVector] = [CGVector(dx: 0.72, dy: 0.7), CGVector(dx: -0.72, dy: 0.7)]
        for (path, kick) in zip(L.slingPaths(), kicks) {
            // Lit plastic underneath; the physics shape draws only the frame.
            let plastic = SlingPlastic(points: L.slingTriangles[slingPlastics.count],
                                       frameColor: magentaColor)
            plastic.zPosition = 4
            field.addChild(plastic)
            slingPlastics.append(plastic)
            let shape = SKShapeNode(path: path)
            shape.fillColor = .clear
            shape.strokeColor = magentaColor
            shape.lineWidth = 3
            shape.lineJoin = .round
            shape.glowWidth = 1.5
            shape.zPosition = 5
            let body = SKPhysicsBody(edgeLoopFrom: path)
            body.friction = 0.05
            body.restitution = 0.3
            body.categoryBitMask = Cat.sling
            shape.physicsBody = body
            field.addChild(shape)
            slingNodes.append((shape, kick))
        }
    }

    private func buildGate() {
        let body = SKPhysicsBody(edgeChainFrom: L.gatePath())
        body.friction = 0
        body.restitution = 0.1
        body.categoryBitMask = Cat.wall
        gateNode.physicsBody = body
        field.addChild(gateNode)
        // Hinged on the outer wall, swinging inward — like the real thing.
        laneGateFlap = GateFlap(hinge: CGPoint(x: 460, y: L.gateY + 6),
                                tip: CGPoint(x: L.laneX, y: L.gateY - 2),
                                swing: 0.6, chevronAt: CGPoint(x: 445, y: 668))
        field.addChild(laneGateFlap)

        // Top containment gates: seal the arch left and right of the NOVA
        // lanes so a ball at the top must exit down through the lanes.
        let tl = SKNode()
        let tlPath = CGMutablePath()
        tlPath.move(to: L.topLeftGateHinge)
        tlPath.addLine(to: L.topLeftGateTip)
        let tlBody = SKPhysicsBody(edgeChainFrom: tlPath)
        tlBody.friction = 0
        tlBody.restitution = 0.1
        tlBody.categoryBitMask = Cat.wall
        tl.physicsBody = tlBody
        field.addChild(tl)
        topLeftGateBody = tlBody
        topLeftGateFlap = GateFlap(hinge: L.topLeftGateHinge, tip: L.topLeftGateTip,
                                   swing: -0.55, chevronAt: CGPoint(x: 112, y: 905),
                                   chevronRotation: -.pi / 2)
        field.addChild(topLeftGateFlap)

        let tr = SKNode()
        let trPath = CGMutablePath()
        trPath.move(to: L.topRightGateHinge)
        trPath.addLine(to: L.topRightGateTip)
        let trBody = SKPhysicsBody(edgeChainFrom: trPath)
        trBody.friction = 0
        trBody.restitution = 0.1
        trBody.categoryBitMask = Cat.wall
        tr.physicsBody = trBody
        field.addChild(tr)
        topRightGateBody = trBody
        topRightGateFlap = GateFlap(hinge: L.topRightGateHinge, tip: L.topRightGateTip,
                                    swing: 0.55, chevronAt: CGPoint(x: 322, y: 910),
                                    chevronRotation: .pi / 2)
        field.addChild(topRightGateFlap)
    }

    private let steelColor = NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.95, alpha: 1)

    /// Capsule (stadium) path centred on the origin, long axis along y.
    private func capsulePath(width w: CGFloat, length l: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: -w / 2, y: -l / 2, width: w, height: l),
               cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
    }

    /// Each outlane: a chrome plate with a dark slot along the lane (as on
    /// real tables) and the steel arch standing in it — drawn with a
    /// highlight and a cast shadow so it reads as raised. The arch's physics
    /// lives on a separate node whose category `updateGuards` sets every
    /// frame (up / down / one-way). Plus the countdown display in the lower
    /// left corner of the cabinet.
    private func buildOutlaneGuards() {
        let w = L.guardWidth, l = L.guardLength
        for p in L.guardPosts {
            let plate = SKShapeNode(path: capsulePath(width: 13, length: l + 16))
            plate.position = p
            plate.fillColor = NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.52, alpha: 1)
            plate.strokeColor = NSColor(calibratedWhite: 0.85, alpha: 0.9)
            plate.lineWidth = 1.2
            plate.zPosition = 4
            field.addChild(plate)
            let slot = SKShapeNode(path: capsulePath(width: w + 1, length: l + 4))
            slot.position = p
            slot.fillColor = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.03, alpha: 1)
            slot.strokeColor = .clear
            slot.zPosition = 4.5
            field.addChild(slot)

            let arch = SKNode()
            arch.position = p
            arch.zPosition = 6
            let shadow = SKShapeNode(path: capsulePath(width: w + 1, length: l))
            shadow.position = CGPoint(x: 3, y: -4)
            shadow.fillColor = NSColor(calibratedWhite: 0, alpha: 0.45)
            shadow.strokeColor = .clear
            arch.addChild(shadow)
            let steel = SKShapeNode(path: capsulePath(width: w, length: l))
            steel.name = "steel"
            steel.fillColor = steelColor
            steel.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.9)
            steel.lineWidth = 0.8
            steel.glowWidth = 1
            steel.zPosition = 0.1
            arch.addChild(steel)
            let shine = SKShapeNode(rect: CGRect(x: -w / 2 + 0.9, y: -l / 2 + 4, width: 1.2, height: l - 8))
            shine.fillColor = .white
            shine.strokeColor = .clear
            shine.zPosition = 0.2
            arch.addChild(shine)
            field.addChild(arch)
            guardArches.append(arch)

            let carrier = SKNode()
            carrier.position = p
            let body = SKPhysicsBody(edgeLoopFrom: capsulePath(width: w, length: l))
            body.friction = 0.08
            body.restitution = 0.3
            body.categoryBitMask = Cat.guardPost
            carrier.physicsBody = body
            field.addChild(carrier)
            guardBodies.append(carrier)
        }

        // Countdown: a small display in the cabinet corner, left of the
        // bottom curve (scene coordinates, outside the playfield).
        let box = SKShapeNode(rect: CGRect(x: -24, y: -21, width: 48, height: 42), cornerRadius: 6)
        box.position = CGPoint(x: 40, y: 33)
        box.fillColor = NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.07, alpha: 0.9)
        box.strokeColor = cyanColor.withAlphaComponent(0.5)
        box.lineWidth = 1.2
        box.zPosition = 50
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "GUARDS"
        title.fontSize = 8
        title.fontColor = cyanColor.withAlphaComponent(0.75)
        title.position = CGPoint(x: 0, y: 9)
        box.addChild(title)
        let value = SKLabelNode(fontNamed: "Menlo-Bold")
        value.fontSize = 20
        value.position = CGPoint(x: 0, y: -15)
        box.addChild(value)
        addChild(box)
        guardCounter = box
        guardCounterValue = value
    }

    /// Raises or lowers both guards (arches pop up with a white flash / sink
    /// into their slots). The timer is the caller's business.
    private func setGuards(up: Bool, sound: Bool = true) {
        for arch in guardArches { arch.removeAction(forKey: "warn") }
        guard up != guardsUp else {
            for arch in guardArches { arch.alpha = up ? 1 : 0 }
            return
        }
        guardsUp = up
        for arch in guardArches {
            arch.removeAction(forKey: "guard")
            if up {
                arch.alpha = 1
                arch.setScale(1)
                flashArch(arch)
            } else {
                arch.run(.group([.fadeOut(withDuration: 0.2), .scaleY(to: 0.6, duration: 0.2)]),
                         withKey: "guard")
            }
        }
        if sound { sounds.play(up ? "target" : "drop", volume: 0.7, jitter: 0) }
        refreshHUD()
    }

    private func flashArch(_ arch: SKNode) {
        guard let steel = arch.childNode(withName: "steel") as? SKShapeNode else { return }
        steel.run(.sequence([
            .run { steel.fillColor = .white }, .wait(forDuration: 0.12),
            .run { [weak self] in steel.fillColor = self?.steelColor ?? .white },
        ]), withKey: "flash")
    }

    /// New ball (or game reset): guards up, timer waits for the launch.
    private func resetGuards(sound: Bool = true) {
        guardDeadline = nil
        guardPassing = [[], []]
        setGuards(up: true, sound: sound)
    }

    /// The ball is over: the timer stops where it is (the next ball resets
    /// the guards), so OUTLANES OPEN can't fire between balls.
    private func stopGuardTimer() {
        guardDeadline = nil
        for arch in guardArches {
            arch.removeAction(forKey: "warn")
            arch.alpha = guardsUp ? 1 : 0
        }
    }

    /// A raised guard fires a touching ball back up into the inlane — the
    /// arch never holds a ball. Per-ball cooldown so one touch is one kick.
    private func kickFromGuard(_ i: Int, ball entity: BallEntity) {
        guard guardsUp, !tilted, let body = entity.node.physicsBody else { return }
        let key = ObjectIdentifier(entity)
        if let last = lastGuardKick[key], now - last < 0.15 { return }
        lastGuardKick[key] = now
        let side: CGFloat = i == 0 ? 1 : -1
        body.velocity = CGVector(dx: Tuning.guardKick.dx * side, dy: Tuning.guardKick.dy)
        body.angularVelocity = 0
        let p = L.guardPosts[i]
        sounds.play("slingshot", volume: 0.85, pan: pan(p.x))
        flashArch(guardArches[i])
        burst(at: CGPoint(x: p.x, y: p.y + L.guardLength / 2), color: .white, count: 10, speed: 110, size: 4)
        outlaneStatsForTest.saves += 1
    }

    /// Every frame: the timer (warning blink, then down), the countdown
    /// display, and each arch's physics — solid while up, except for a ball
    /// climbing its outlane from below (around the horn), which passes while
    /// the arch ducks. A ball found touching a raised arch is kicked (covers
    /// slow touches that start no new contact).
    private func updateGuards() {
        if guardsUp, let deadline = guardDeadline {
            if now >= deadline {
                guardDeadline = nil
                setGuards(up: false)
                banner("OUTLANES OPEN", color: cyanColor)
            } else if now >= deadline - Tuning.guardWarning,
                      guardArches.first?.action(forKey: "warn") == nil {
                for arch in guardArches {
                    arch.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.12),
                                                       .fadeAlpha(to: 1.0, duration: 0.12)])),
                             withKey: "warn")
                }
            }
        }
        refreshGuardCounter()

        let half = L.guardLength / 2, reach = L.ballRadius + L.guardWidth / 2 + 1.5
        for (i, carrier) in guardBodies.enumerated() {
            let c = L.guardPosts[i]
            var open = false
            for entity in balls where !entity.onRamp {
                let key = ObjectIdentifier(entity), p = entity.node.position
                guard abs(p.x - c.x) < 26, let v = entity.node.physicsBody?.velocity else {
                    guardPassing[i].remove(key)
                    continue
                }
                let dy = max(abs(p.y - c.y) - (half - L.guardWidth / 2), 0)
                let distance = hypot(p.x - c.x, dy)
                // Climbing from below (around the horn): the arch stays open
                // for this ball until it is clear above it, or turns back.
                if guardsUp && p.y < c.y + half - 2 && p.y > c.y - half - 80 && v.dy > 60 {
                    guardPassing[i].insert(key)
                }
                if guardPassing[i].contains(key) {
                    if v.dy <= 0 || distance > reach + 4 {
                        guardPassing[i].remove(key)
                        if v.dy > 0 && p.y > c.y { outlaneStatsForTest.passesFromBelow += 1 }
                    } else {
                        open = true
                    }
                }
            }
            let solid = guardsUp && !open
            carrier.physicsBody?.categoryBitMask = solid ? Cat.guardPost : 0
            if guardsUp && guardArches[i].action(forKey: "warn") == nil
                && guardArches[i].action(forKey: "attractHi") == nil {
                guardArches[i].alpha = open ? 0.35 : 1     // ducks for a ball from below
            }
            guard solid else { continue }
            for entity in balls where !entity.onRamp {
                let p = entity.node.position
                let dy = max(abs(p.y - c.y) - (half - L.guardWidth / 2), 0)
                if hypot(p.x - c.x, dy) <= reach { kickFromGuard(i, ball: entity) }
            }
        }
        // Test statistic: balls that got past a guard into the outlane below.
        for entity in balls {
            let p = entity.node.position, key = ObjectIdentifier(entity)
            let inside = p.y > 150 && p.y < 215 && (p.x < 45 || (p.x > 385 && p.x < L.laneX))
            if inside && !ballsInOutlane.contains(key) { outlaneStatsForTest.entries += 1 }
            if inside { ballsInOutlane.insert(key) } else { ballsInOutlane.remove(key) }
        }
    }

    /// Lower-left countdown: seconds left while the guards are up (full time
    /// while the ball waits to be launched), amber for the last seconds,
    /// "--" once they are down. Hidden between games (except when the
    /// attract show's guard page lights it).
    private func refreshGuardCounter() {
        let showcase = attractHighlight == .guards
        guardCounter.isHidden = gameOver && !showcase
        let text: String, color: NSColor
        if showcase || (guardsUp && guardDeadline == nil) {
            text = "\(Int(guardTime))"
            color = cyanColor
        } else if guardsUp, let deadline = guardDeadline {
            let left = max(0, Int((deadline - now).rounded(.up)))
            text = String(format: "%02d", left)
            color = deadline - now <= Tuning.guardWarning ? amberColor : cyanColor
        } else {
            text = "--"
            color = railColor.withAlphaComponent(0.7)
        }
        if guardCounterValue.text != text { guardCounterValue.text = text }
        if guardCounterValue.fontColor != color { guardCounterValue.fontColor = color }
    }

    private func buildDrain() {
        // Below the drain hole, outside the visible table — the ball falls
        // through the opening and out of play before this catches it.
        let drain = SKNode()
        drain.position = CGPoint(x: 215, y: -25)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 140, height: 40))
        body.isDynamic = false
        body.categoryBitMask = Cat.drain
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.ball
        drain.physicsBody = body
        field.addChild(drain)
    }

    private func buildBumpers() {
        let tex = Textures.bumperDome(diameter: L.bumperRadius * 2)
        for center in L.bumpers {
            let bumper = SKNode()
            bumper.position = center

            let dome = SKSpriteNode(texture: tex,
                                    size: CGSize(width: L.bumperRadius * 2, height: L.bumperRadius * 2))
            dome.name = "dome"
            dome.zPosition = 7
            bumper.addChild(dome)

            let ring = SKShapeNode(circleOfRadius: L.bumperRadius)
            ring.name = "ring"
            ring.strokeColor = magentaColor
            ring.lineWidth = 3
            ring.glowWidth = 2
            ring.zPosition = 8
            bumper.addChild(ring)

            let body = SKPhysicsBody(circleOfRadius: L.bumperRadius)
            body.isDynamic = false
            body.friction = 0.1
            body.restitution = 0.3
            body.categoryBitMask = Cat.bumper
            bumper.physicsBody = body

            field.addChild(bumper)
            bumperNodes.append(bumper)
        }
    }

    private func buildDropTargets() {
        for center in L.dropTargetCenters {
            let target = SKShapeNode(rectOf: L.dropTargetSize, cornerRadius: 2)
            target.position = center
            target.zRotation = L.dropTargetAngle
            target.fillColor = cyanColor
            target.strokeColor = NSColor(calibratedRed: 0.7, green: 0.97, blue: 1.0, alpha: 1)
            target.lineWidth = 2
            target.zPosition = 7
            let body = SKPhysicsBody(rectangleOf: L.dropTargetSize)
            body.isDynamic = false
            body.friction = 0.1
            body.restitution = 0.35
            body.categoryBitMask = Cat.dropTarget
            target.physicsBody = body
            field.addChild(target)
            dropTargets.append(target)
            dropTargetDown.append(false)
        }
    }

    private func buildStandups() {
        for center in L.standupCenters {
            let target = SKShapeNode(rectOf: L.standupSize, cornerRadius: 2)
            target.position = center
            target.fillColor = magentaColor
            target.strokeColor = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.85, alpha: 1)
            target.lineWidth = 2
            target.zPosition = 7
            let body = SKPhysicsBody(rectangleOf: L.standupSize)
            body.isDynamic = false
            body.friction = 0.1
            body.restitution = 0.5
            body.categoryBitMask = Cat.standup
            target.physicsBody = body
            field.addChild(target)
            standupNodes.append(target)
            standupHit.append(false)
        }
    }

    private func buildNovaLanes() {
        for x in L.novaDividerXs {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: L.novaLaneBottom))
            path.addLine(to: CGPoint(x: x, y: L.novaLaneTop))
            addWall(path, stroke: cyanColor.withAlphaComponent(0.7), width: 4, glow: 1)
        }
        for (i, cx) in L.novaLaneCenters.enumerated() {
            let sensor = SKNode()
            sensor.position = CGPoint(x: cx, y: 880)
            let body = SKPhysicsBody(rectangleOf: CGSize(width: 8, height: 36))
            body.isDynamic = false
            body.categoryBitMask = Cat.rollover
            body.collisionBitMask = 0
            body.contactTestBitMask = Cat.ball
            sensor.physicsBody = body
            field.addChild(sensor)
            novaSensors.append(sensor)

            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = L.novaLetters[i]
            label.fontSize = 16
            label.fontColor = cyanColor.withAlphaComponent(0.35)
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: cx, y: 878)
            label.zPosition = 6
            field.addChild(label)
            novaLabels.append(label)
        }
    }

    private func novaLabelColor(_ i: Int) -> NSColor {
        novaLit[i] ? amberColor : cyanColor.withAlphaComponent(0.35)
    }

    /// Fixed target from the moment the ball reaches the plunger: its NOVA
    /// letter flashes orange; the player aims with the pull (see
    /// `Tuning.skillBandLane`).
    private func armSkillShot(lane forced: Int? = nil) {
        guard !multiball, !continuousPlay else { return }
        if let old = skillLane { stopLetterFlash(old) }
        let lane = forced ?? Int.random(in: 0..<L.novaLaneCenters.count)
        skillLane = lane
        skillLaunched = false
        skillAimLane = nil
        skillBall = nil
        let label = novaLabels[lane]
        label.run(.repeatForever(.sequence([
            .run { [weak self, weak label] in label?.fontColor = self?.amberColor },
            .wait(forDuration: 0.22),
            .run { [weak self, weak label] in
                label?.fontColor = self?.cyanColor.withAlphaComponent(0.35) },
            .wait(forDuration: 0.22),
        ])), withKey: "skill")
    }

    private func stopLetterFlash(_ i: Int) {
        novaLabels[i].removeAction(forKey: "skill")
        novaLabels[i].fontColor = novaLabelColor(i)
    }

    private func disarmSkillShot() {
        if let lane = skillLane { stopLetterFlash(lane) }
        skillLane = nil
        skillLaunched = false
        skillAimLane = nil
        skillBall = nil
    }

    private func updateSkillShot() {
        guard skillLane != nil, skillLaunched else { return }
        if now - skillLaunchTime > Tuning.skillWindow { disarmSkillShot() }
    }

    /// During a skill-shot launch the ball drops into the lane its pull band
    /// aimed at: once it is above that lane (moving left along the arch), its
    /// sideways motion is taken out. Stronger pulls always travel at least
    /// that far, so this only ever stops a ball — it never pushes one. (Raw
    /// physics alone is chaotic here: the first lane jumps N/O/N between
    /// launch strengths 0.91/0.92/0.93.)
    private func steerSkillBall(_ entity: BallEntity, body: SKPhysicsBody) {
        guard skillLaunched, let aim = skillAimLane,
              skillBall == ObjectIdentifier(entity) else { return }
        let p = entity.node.position, v = body.velocity
        let target = L.novaLaneCenters[aim]
        guard p.y > L.novaLaneTop, v.dx < 0, p.x <= target + 4 else { return }
        entity.node.position.x = target
        body.velocity = CGVector(dx: 0, dy: min(v.dy, 0))
        skillBall = nil                     // steer once
    }

    private func resolveSkillShot(lane index: Int) {
        guard let lit = skillLane, skillLaunched else { return }
        disarmSkillShot()
        guard index == lit else { return }
        let superShot = index != 0
        let points = superShot ? Score.superSkillShot : Score.skillShot
        let p = CGPoint(x: L.novaLaneCenters[index], y: 845)
        sounds.play("jackpot", volume: 0.9, jitter: 0)
        flash(NSColor.white, intensity: 0.15)
        burst(at: CGPoint(x: p.x, y: 880), color: .white, count: 30, speed: 220)
        award(points, at: p, color: .white)
        banner(superShot ? "SUPER SKILL SHOT!" : "SKILL SHOT!", color: .white)
        for plastic in slingPlastics { plastic.flash(.white, times: 3) }
        sounds.say(superShot ? "superskill" : "skillshot", priority: 3, delay: 0.15)
        skillShotsForTest += 1
    }

    private func majorShot(at p: CGPoint) {
        guard !continuousPlay, !tilted else { return }
        comboCount = now <= comboDeadline ? comboCount + 1 : 1
        comboDeadline = now + Tuning.comboWindow
        if comboCount >= 2 {
            let points = Score.combo * (comboCount - 1)
            award(points, at: CGPoint(x: p.x, y: p.y + 22), color: .white)
            banner("COMBO \u{00D7}\(comboCount)", color: .white)
            flash(NSColor.white, intensity: 0.08 + 0.03 * CGFloat(min(comboCount, 5)))
            sounds.say(comboCount >= 3 ? "supercombo" : "combo", priority: 2, delay: 0.2)
            comboStatsForTest.combos += 1
            comboStatsForTest.best = max(comboStatsForTest.best, comboCount)
        }
        refreshCombo()
    }

    private func refreshCombo() {
        let running = comboCount > 0 && now <= comboDeadline
        orbitArrow.removeAction(forKey: "combo")
        rampArrow.removeAction(forKey: "combo")
        orbitArrow.isHidden = !running
        for plastic in slingPlastics { plastic.setChase(running, color: .white) }
        if running {
            let blink = SKAction.repeatForever(.sequence([
                .fadeAlpha(to: 0.2, duration: 0.12), .fadeAlpha(to: 1.0, duration: 0.12)]))
            orbitArrow.run(blink, withKey: "combo")
            rampArrow.strokeColor = .white
            rampArrow.run(blink, withKey: "combo")
        } else {
            rampArrow.strokeColor = amberColor.withAlphaComponent(0.6)
            rampArrow.alpha = 1
            refreshLamps()      // restore the multiball jackpot blink if any
        }
        refreshHUD()
    }

    private func updateCombo() {
        if comboCount > 0 && now > comboDeadline {
            comboCount = 0
            refreshCombo()
        }
    }

    private func buildOrbit() {
        for path in L.orbitGuidePaths() {
            addWall(path, stroke: cyanColor, width: 4, glow: 1.5)
        }
        // Spinner: a bar across the orbit lane; visual spins, sensor scores.
        spinnerBar = SKShapeNode(rectOf: L.spinnerSize, cornerRadius: 2)
        spinnerBar.position = L.spinnerCenter
        spinnerBar.fillColor = amberColor
        spinnerBar.strokeColor = .clear
        spinnerBar.zPosition = 6
        field.addChild(spinnerBar)

        let sensor = SKNode()
        sensor.position = L.spinnerCenter
        let body = SKPhysicsBody(rectangleOf: CGSize(width: L.spinnerSize.width, height: 10))
        body.isDynamic = false
        body.categoryBitMask = Cat.spinner
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.ball
        sensor.physicsBody = body
        field.addChild(sensor)
    }

    /// Shared spinner animation: n visual flips with a tick per flip.
    private func spin(_ bar: SKShapeNode, times: Int, panX: CGFloat) {
        let p = pan(panX)
        let flip = SKAction.sequence([
            .run { [weak self] in self?.sounds.play("spinner", volume: 0.35, pan: p) },
            .scaleY(to: 0.12, duration: 0.05),
            .scaleY(to: 1.0, duration: 0.05),
        ])
        bar.run(.repeat(flip, count: times))
    }

    private func buildSaucer() {
        saucerNode = SKShapeNode(circleOfRadius: L.saucerRadius)
        saucerNode.position = L.saucerCenter
        saucerNode.fillColor = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.14, alpha: 1)
        saucerNode.strokeColor = amberColor
        saucerNode.lineWidth = 2.5
        saucerNode.glowWidth = 1.5
        saucerNode.zPosition = 6
        let inner = SKShapeNode(circleOfRadius: L.saucerRadius * 0.45)
        inner.fillColor = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.30, alpha: 1)
        inner.strokeColor = .clear
        saucerNode.addChild(inner)
        field.addChild(saucerNode)

        extraBallLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        extraBallLabel.text = "EXTRA BALL"
        extraBallLabel.fontSize = 9
        extraBallLabel.fontColor = amberColor
        extraBallLabel.position = CGPoint(x: L.saucerCenter.x, y: L.saucerCenter.y - L.saucerRadius - 14)
        extraBallLabel.zPosition = 7
        extraBallLabel.isHidden = true
        field.addChild(extraBallLabel)

        // Small catch zone: only a well-centered ball drops in (a larger
        // sensor swallowed everything descending the left corridor).
        let sensor = SKNode()
        sensor.position = L.saucerCenter
        let body = SKPhysicsBody(circleOfRadius: L.saucerRadius * 0.55)
        body.isDynamic = false
        body.categoryBitMask = Cat.saucer
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.ball
        sensor.physicsBody = body
        field.addChild(sensor)
    }

    private let violetColor = NSColor(calibratedRed: 0.62, green: 0.42, blue: 1.0, alpha: 1)

    private func buildWormhole(_ index: Int) {
        let violet = violetColor
        let center = L.wormholeCenters[index]
        let wormholeNode = SKShapeNode(circleOfRadius: L.wormholeRadius)
        wormholeNode.position = center
        wormholeNode.fillColor = NSColor(calibratedRed: 0.03, green: 0.02, blue: 0.10, alpha: 1)
        wormholeNode.strokeColor = violet
        wormholeNode.lineWidth = 2.5
        wormholeNode.glowWidth = 2
        wormholeNode.zPosition = 6
        // Swirl: two spiral arms rotating slowly.
        let swirl = SKShapeNode()
        let path = CGMutablePath()
        for arm in 0..<2 {
            let base = CGFloat(arm) * .pi
            path.move(to: CGPoint(x: 2 * cos(base), y: 2 * sin(base)))
            for i in 1...14 {
                let t = CGFloat(i) / 14
                let a = base + t * 1.6 * .pi
                let r = 2 + t * (L.wormholeRadius - 5)
                path.addLine(to: CGPoint(x: r * cos(a), y: r * sin(a)))
            }
        }
        swirl.path = path
        swirl.strokeColor = violet.withAlphaComponent(0.7)
        swirl.lineWidth = 1.5
        swirl.lineCap = .round
        swirl.run(.repeatForever(.rotate(byAngle: -2 * .pi, duration: 3)))
        wormholeNode.addChild(swirl)
        field.addChild(wormholeNode)
        wormholeNodes.append(wormholeNode)
        // "Visited" lamp: an amber ring around the hole, lit once the ball
        // has been captured there this ball (Extra Ball progress).
        let ring = SKShapeNode(circleOfRadius: L.wormholeRadius + 5)
        ring.position = center
        ring.strokeColor = amberColor
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.glowWidth = 2
        ring.zPosition = 5
        ring.isHidden = true
        field.addChild(ring)
        wormholeVisitRings.append(ring)

        let sensor = SKNode()
        sensor.name = "wormhole\(index)"
        sensor.position = center
        let body = SKPhysicsBody(circleOfRadius: L.wormholeRadius * 0.55)
        body.isDynamic = false
        body.categoryBitMask = Cat.wormhole
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.ball
        sensor.physicsBody = body
        field.addChild(sensor)
    }

    private func buildRamp() {
        // The walls are visual only — while on the ramp, the ball is
        // rail-guided along the centerline (2D edge containment cannot
        // reliably hold a fast ball through a 180° turn).
        for path in [L.rampOuterWall(), L.rampInnerWall()] {
            let node = SKShapeNode(path: path)
            node.strokeColor = amberColor.withAlphaComponent(0.75)
            node.lineWidth = 3.5
            node.lineCap = .round
            node.glowWidth = 1
            node.zPosition = 12
            field.addChild(node)
        }
        // Solid sections where the deck is at playfield level (entry funnel
        // + cap, exit chute + cap).
        for path in L.rampSolidWallPaths() {
            addWall(path, stroke: amberColor, width: 3.5, glow: 1.5)
        }
        // Translucent deck between the walls.
        let deck = SKShapeNode(path: L.rampCenterline())
        deck.strokeColor = amberColor.withAlphaComponent(0.10)
        deck.lineWidth = 30
        deck.lineCap = .round
        deck.zPosition = 11
        field.addChild(deck)

        // Entry is a geometric check in the game loop (see checkRampEntry),
        // not a sensor body: only a ball that is centred in the mouth and
        // travelling along the ramp axis climbs it.

        // Ramp spinner just past the mouth (rail-triggered).
        rampSpinnerBar = SKShapeNode(rectOf: L.spinnerSize, cornerRadius: 2)
        rampSpinnerBar.position = L.rampSpinnerCenter
        rampSpinnerBar.zRotation = L.rampSpinnerAngle
        rampSpinnerBar.fillColor = amberColor
        rampSpinnerBar.strokeColor = .clear
        rampSpinnerBar.zPosition = 13
        field.addChild(rampSpinnerBar)
        // Entrance arrow marker (pulses as the jackpot lamp in multiball).
        rampArrow = SKShapeNode()
        let a = CGMutablePath()
        a.move(to: CGPoint(x: 296, y: 448))
        a.addLine(to: CGPoint(x: 304, y: 458))
        a.addLine(to: CGPoint(x: 312, y: 448))
        rampArrow.path = a
        rampArrow.strokeColor = amberColor.withAlphaComponent(0.6)
        rampArrow.lineWidth = 2.5
        rampArrow.lineCap = .round
        rampArrow.lineJoin = .round
        rampArrow.zPosition = 6
        field.addChild(rampArrow)

        // Orbit arrow (left lane, between the wormhole and the spinner):
        // only shown while a combo is running.
        orbitArrow = SKShapeNode()
        let o = CGMutablePath()
        o.move(to: CGPoint(x: 13, y: 470))
        o.addLine(to: CGPoint(x: 21, y: 480))
        o.addLine(to: CGPoint(x: 29, y: 470))
        orbitArrow.path = o
        orbitArrow.strokeColor = .white
        orbitArrow.lineWidth = 2.5
        orbitArrow.lineCap = .round
        orbitArrow.lineJoin = .round
        orbitArrow.glowWidth = 2
        orbitArrow.zPosition = 6
        orbitArrow.isHidden = true
        field.addChild(orbitArrow)

        // Exit marker: downward chevron at the drop-off end.
        let exitMark = SKShapeNode()
        let e = CGMutablePath()
        e.move(to: CGPoint(x: 73, y: 556))
        e.addLine(to: CGPoint(x: 81, y: 546))
        e.addLine(to: CGPoint(x: 89, y: 556))
        exitMark.path = e
        exitMark.strokeColor = amberColor.withAlphaComponent(0.6)
        exitMark.lineWidth = 2.5
        exitMark.lineCap = .round
        exitMark.lineJoin = .round
        exitMark.zPosition = 12
        field.addChild(exitMark)
    }

    private func buildFlippers() {
        leftFlipper.add(to: field, in: self, pivotInField: L.leftPivot)
        rightFlipper.add(to: field, in: self, pivotInField: L.rightPivot)
    }

    private func buildPlunger() {
        plunger = SKShapeNode(rectOf: CGSize(width: 22, height: 30), cornerRadius: 6)
        plunger.fillColor = amberColor
        plunger.strokeColor = .clear
        plunger.position = L.plungerRest
        plunger.zPosition = 4
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 22, height: 30))
        body.isDynamic = false
        body.friction = 0.2
        body.restitution = 0.1
        body.categoryBitMask = Cat.plunger
        plunger.physicsBody = body
        field.addChild(plunger)
    }

    private func buildHUD() {
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        scoreLabel.fontSize = 21
        scoreLabel.fontColor = amberColor
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 24, y: 972)
        scoreLabel.zPosition = 50
        addChild(scoreLabel)

        ballLabel = SKLabelNode(fontNamed: "Menlo")
        ballLabel.fontSize = 13
        ballLabel.fontColor = cyanColor
        ballLabel.horizontalAlignmentMode = .right
        ballLabel.position = CGPoint(x: 476, y: 976)
        ballLabel.zPosition = 50
        addChild(ballLabel)

        modeLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        modeLabel.fontSize = 12
        modeLabel.fontColor = amberColor
        modeLabel.horizontalAlignmentMode = .left
        modeLabel.position = CGPoint(x: 24, y: 950)
        modeLabel.zPosition = 50
        modeLabel.isHidden = true
        addChild(modeLabel)

        statusLabel = SKLabelNode(fontNamed: "Menlo")
        statusLabel.fontSize = 11
        statusLabel.fontColor = cyanColor.withAlphaComponent(0.8)
        statusLabel.horizontalAlignmentMode = .right
        statusLabel.position = CGPoint(x: 476, y: 956)
        statusLabel.zPosition = 50
        addChild(statusLabel)

        hintLabel = SKLabelNode(fontNamed: "Menlo")
        // Kept narrow so it sits clear of the left wormhole and the outlane
        // bumps; the full key list is in Help (⌘?).
        hintLabel.text = "CTRL / RIGHT-SHIFT = FLIPPERS (\u{2190} \u{2192})\n"
            + "HOLD SPACE = PLUNGER · NUDGE \(KeyLabels.nudge.joined(separator: " "))\n"
            + "R NEW GAME · P PAUSE · \u{2318}? ALL KEYS"
        hintLabel.numberOfLines = 3
        hintLabel.horizontalAlignmentMode = .center
        hintLabel.fontSize = 11
        hintLabel.fontColor = NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.73, alpha: 1)
        hintLabel.position = CGPoint(x: 250, y: 360)
        hintLabel.zPosition = 50
        addChild(hintLabel)

        // Title: the band under the NOVA lanes, above the bumpers. Centred
        // vertically so its pulse grows evenly; a blurred dark copy behind it
        // keeps it readable where the ramp arches cross.
        attractTitle = SKLabelNode(fontNamed: "Menlo-Bold")
        attractTitle.text = "NOVA RUSH"
        attractTitle.fontSize = 40
        attractTitle.fontColor = amberColor
        attractTitle.verticalAlignmentMode = .center
        attractTitle.position = CGPoint(x: 250, y: 850)
        attractTitle.zPosition = 55
        attractTitle.isHidden = true
        addChild(attractTitle)
        let halo = SKEffectNode()
        halo.shouldRasterize = true
        halo.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 7])
        halo.zPosition = -1
        let shade = SKLabelNode(fontNamed: "Menlo-Bold")
        shade.text = attractTitle.text
        shade.fontSize = attractTitle.fontSize
        shade.fontColor = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.03, alpha: 0.95)
        shade.verticalAlignmentMode = .center
        halo.addChild(shade)
        attractTitle.addChild(halo)

        // Attract display: a dark panel between the bumpers and the drop
        // targets, narrow enough to leave the saucer and the EXTRA BALL lamp
        // visible (the teasers light them).
        attractPanel = SKShapeNode()
        attractPanel.fillColor = NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.07, alpha: 0.86)
        attractPanel.lineWidth = 2
        attractPanel.glowWidth = 2.5
        attractPanel.position = CGPoint(x: 250, y: 575)
        attractPanel.zPosition = 52
        attractPanel.isHidden = true
        addChild(attractPanel)
        attractText = SKLabelNode()
        attractText.numberOfLines = 0
        attractText.horizontalAlignmentMode = .center
        attractText.verticalAlignmentMode = .center
        attractPanel.addChild(attractText)

        startPrompt = SKLabelNode(fontNamed: "Menlo-Bold")
        startPrompt.text = "PRESS SPACE TO START"
        startPrompt.fontSize = 17
        startPrompt.fontColor = .white
        startPrompt.position = CGPoint(x: 250, y: 300)
        startPrompt.zPosition = 52
        startPrompt.isHidden = true
        addChild(startPrompt)

        messageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        messageLabel.fontSize = 24
        messageLabel.fontColor = amberColor
        messageLabel.numberOfLines = 6
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: 250, y: 560)
        messageLabel.zPosition = 50
        messageLabel.isHidden = true
        addChild(messageLabel)

        pauseLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        pauseLabel.text = "PAUSED\nPRESS P TO RESUME"
        pauseLabel.fontSize = 24
        pauseLabel.fontColor = cyanColor
        pauseLabel.numberOfLines = 2
        pauseLabel.horizontalAlignmentMode = .center
        pauseLabel.verticalAlignmentMode = .center
        pauseLabel.position = CGPoint(x: 250, y: 470)
        pauseLabel.zPosition = 95
        pauseLabel.isHidden = true
        addChild(pauseLabel)

        flashNode = SKSpriteNode(color: .white, size: L.sceneSize)
        flashNode.position = CGPoint(x: L.sceneSize.width / 2, y: L.sceneSize.height / 2)
        flashNode.alpha = 0
        flashNode.zPosition = 90
        addChild(flashNode)
    }

    // MARK: - Balls

    @discardableResult
    private func spawnBall(at point: CGPoint, velocity: CGVector = .zero) -> BallEntity? {
        guard balls.count < Tuning.maxBalls else { return nil }
        if ballTexture == nil {
            ballTexture = Textures.chromeBall(diameter: L.ballRadius * 2)
        }
        let shadow = SKShapeNode(circleOfRadius: L.ballRadius)
        shadow.fillColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.zPosition = 8
        field.addChild(shadow)

        let node = SKSpriteNode(texture: ballTexture,
                                size: CGSize(width: L.ballRadius * 2, height: L.ballRadius * 2))
        node.position = point
        node.zPosition = 10
        let body = SKPhysicsBody(circleOfRadius: L.ballRadius)
        body.mass = Tuning.ballMass
        body.friction = Tuning.ballFriction
        body.restitution = Tuning.ballRestitution
        body.linearDamping = Tuning.ballLinearDamping
        body.angularDamping = Tuning.ballAngularDamping
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Cat.ball
        body.collisionBitMask = Cat.wall | Cat.flipper | Cat.plunger | Cat.allKickers
        body.contactTestBitMask = Cat.drain | Cat.allKickers | Cat.allSensors
        body.velocity = velocity
        node.physicsBody = body
        field.addChild(node)

        // Comet trail, fed by speed in the game loop.
        let trail = SKEmitterNode()
        trail.particleTexture = sparkTexture
        trail.particleBirthRate = 0
        trail.particleLifetime = 0.22
        trail.particleAlpha = 0.3
        trail.particleAlphaSpeed = -1.4
        trail.particleSize = CGSize(width: 10, height: 10)
        trail.particleScaleSpeed = -1.2
        trail.particleColor = amberColor
        trail.particleColorBlendFactor = 1
        trail.particleBlendMode = .add
        trail.zPosition = 9
        trail.targetNode = field
        node.addChild(trail)

        let entity = BallEntity(node: node, shadow: shadow)
        entity.trail = trail
        balls.append(entity)
        // A fresh ball in the plunger lane (new ball, shoot again, ball
        // save, lock) arms the skill shot.
        if point == L.ballSpawn && balls.count == 1 { armSkillShot() }
        return entity
    }

    private func removeBall(_ entity: BallEntity) {
        entity.node.removeFromParent()
        entity.shadow.removeFromParent()
        balls.removeAll { $0 === entity }
    }

    private func entity(for node: SKNode?) -> BallEntity? {
        guard let node else { return nil }
        return balls.first { $0.node === node }
    }

    // MARK: - Scoring

    private func fmt(_ n: Int) -> String { Score.format(n) }

    private func refreshHUD() {
        if saucerNode != nil { refreshLamps() }
        scoreLabel.text = fmt(score)
        // No game running (attract / game over): like a real machine set to
        // free play, the display shows the last score and FREE PLAY.
        if gameOver && !freePlay {
            ballLabel.text = continuousPlay ? "CONTINUOUS" : "FREE PLAY"
            statusLabel.text = ""
            return
        }
        var right = freePlay ? "FREE PLAY"
            : continuousPlay ? "CONTINUOUS"
            : "BALL \(min(ballNumber, ballsPerGame))/\(ballsPerGame)" + (extraBalls > 0 ? " +EB" : "")
        if multiplier > 1 { right = "\u{00D7}\(multiplier)  ·  " + right }
        ballLabel.text = right

        var status: [String] = []
        if multiball { status.append("JACKPOT ON RAMP") }
        else {
            if locks > 0 { status.append("LOCKS \(locks)/2") }
            if lockLit { status.append("LOCK LIT") }
            if modeLit { status.append("MODE LIT") }
        }
        if comboCount >= 1 && now <= comboDeadline {
            status.append(comboCount >= 2 ? "COMBO \u{00D7}\(comboCount)" : "COMBO READY")
        }
        if extraBallLit { status.append("EXTRA BALL LIT") }
        if extraBalls > 0 { status.append("SHOOT AGAIN") }
        statusLabel.text = status.joined(separator: "  ·  ")
    }

    private func award(_ points: Int, at p: CGPoint, color: NSColor) {
        // Continuous play is practice: no points (protects the high scores).
        guard !continuousPlay else { return }
        score += points
        refreshHUD()
        let pop = SKLabelNode(fontNamed: "Menlo-Bold")
        pop.text = "+\(fmt(points))"
        pop.fontSize = 13
        pop.fontColor = color
        pop.position = CGPoint(x: min(max(p.x, 34), L.W - 34), y: min(p.y + 20, L.H - 30))
        pop.zPosition = 30
        field.addChild(pop)
        pop.run(.sequence([
            .group([.moveBy(x: 0, y: 26, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent(),
        ]))
    }

    // Banners share one spot, so they are queued: one at a time. A banner
    // shows for 1.45 s, or only 0.6 s when another is waiting (end of ball
    // can fire MODE OVER + BONUS + SHOOT AGAIN within a second — they used
    // to be drawn on top of each other).
    private var bannerQueue: [(text: String, color: NSColor)] = []
    private var currentBanner: SKLabelNode?
    private var bannerMinShown = false
    private var bannerFading = false
    private(set) var maxBannersOnScreenForTest = 0

    private var bannerY: CGFloat { messageLabel.isHidden && attractPanel.isHidden ? 620 : 700 }

    /// New game: drop whatever the old one still had queued or on screen.
    private func clearBanners() {
        bannerQueue.removeAll()
        currentBanner?.removeFromParent()
        currentBanner = nil
        bannerFading = false
        bannerMinShown = false
    }

    private func banner(_ text: String, color: NSColor? = nil) {
        let c = color ?? amberColor
        if currentBanner?.text == text && !bannerFading { return }          // already showing
        if bannerQueue.last?.text == text { return }                          // already queued
        bannerQueue.append((text, c))
        if bannerQueue.count > 4 { bannerQueue.removeFirst() }               // never lag far behind
        if currentBanner == nil && !bannerFading {
            showNextBanner()
        } else if bannerMinShown {
            dismissBanner()
        }
    }

    private func showNextBanner() {
        guard !bannerQueue.isEmpty else { return }
        let next = bannerQueue.removeFirst()
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = "banner"
        label.text = next.text
        label.fontSize = 26
        label.fontColor = next.color
        // Above the tilt text / attract display while that is shown.
        label.position = CGPoint(x: 250, y: bannerY)
        label.zPosition = 60
        label.setScale(0.3)
        addChild(label)
        currentBanner = label
        bannerMinShown = false
        maxBannersOnScreenForTest = max(maxBannersOnScreenForTest,
                                        children.filter { $0.name == "banner" }.count)
        label.run(.sequence([
            .scale(to: 1.0, duration: 0.15),
            .wait(forDuration: 0.45),
            .run { [weak self] in
                guard let self, self.currentBanner === label else { return }
                self.bannerMinShown = true
                if !self.bannerQueue.isEmpty { self.dismissBanner() }
            },
            .wait(forDuration: 0.85),
            .run { [weak self] in
                guard let self, self.currentBanner === label else { return }
                self.dismissBanner()
            },
        ]), withKey: "life")
    }

    private func dismissBanner() {
        guard let label = currentBanner, !bannerFading else { return }
        bannerFading = true
        label.removeAction(forKey: "life")
        label.run(.sequence([
            .fadeOut(withDuration: bannerQueue.isEmpty ? 0.4 : 0.15),
            .removeFromParent(),
            .run { [weak self] in
                guard let self else { return }
                self.currentBanner = nil
                self.bannerFading = false
                self.showNextBanner()
            },
        ]))
    }

    // MARK: - Nudge & tilt

    /// Rock the table: every ball gets a shove, the cabinet visibly jolts,
    /// and the tilt bob heats up. Too much too fast forfeits the ball's
    /// flippers, kickers, and bonus — classic rules.
    private func nudge(_ direction: CGVector) {
        // No ball on the table (e.g. the 1.2 s between balls): nothing to
        // shake — and a tilt there would carry over to the next ball.
        guard !tilted, !gameOver, !balls.isEmpty else { return }
        sounds.play("nudge", volume: 0.7)
        for entity in balls where !entity.onRamp {
            entity.node.physicsBody?.applyImpulse(
                CGVector(dx: direction.dx * 3.2, dy: direction.dy * 3.2))
        }
        field.run(.sequence([
            .moveBy(x: direction.dx * 5, y: direction.dy * 5, duration: 0.04),
            .move(to: L.fieldOrigin, duration: 0.11),
        ]))
        tiltHeat += 1.1
        if tiltHeat > 3.2 {
            tilt()
        }
    }

    private func tilt() {
        disarmSkillShot()
        tilted = true
        guardDeadline = nil
        setGuards(up: false)            // you rocked it: no safety net
        sounds.play("gameover", volume: 0.8, jitter: 0)
        sounds.say("tilt", priority: 4)
        flash(magentaColor, intensity: 0.25)
        messageLabel.text = "TILT"
        messageLabel.isHidden = false
        // Kill any live flipper stroke immediately.
        leftFlipper.drive(pressed: false)
        rightFlipper.drive(pressed: false)
    }

    // MARK: - Kicker reactions

    private func kickAllowed(_ node: SKNode, cooldown: TimeInterval = Tuning.kickerCooldown) -> Bool {
        if tilted { return false }
        let id = ObjectIdentifier(node)
        if let last = lastKick[id], now - last < cooldown { return false }
        lastKick[id] = now
        return true
    }

    private func hitBumper(_ bumper: SKNode, ball entity: BallEntity) {
        guard kickAllowed(bumper), let ballBody = entity.node.physicsBody else { return }
        let d = CGVector(dx: entity.node.position.x - bumper.position.x,
                         dy: entity.node.position.y - bumper.position.y)
        let len = max(hypot(d.dx, d.dy), 0.01)
        ballBody.applyImpulse(CGVector(dx: d.dx / len * Tuning.bumperKick,
                                       dy: d.dy / len * Tuning.bumperKick))
        sounds.play("bumper", volume: 0.9, pan: pan(bumper.position.x))
        let points = activeMode == .asteroidStorm ? 1000 : Score.bumper
        award(points, at: bumper.position, color: magentaColor)
        bonusUnits += 10
        burst(at: entity.node.position, color: magentaColor, count: 14, speed: 200)

        if let dome = bumper.childNode(withName: "dome") {
            dome.run(.sequence([
                .group([.scale(to: 1.15, duration: 0.05),
                        .colorize(with: .white, colorBlendFactor: 0.6, duration: 0.05)]),
                .group([.scale(to: 1.0, duration: 0.12),
                        .colorize(withColorBlendFactor: 0, duration: 0.12)]),
            ]))
        }
        if let ring = bumper.childNode(withName: "ring") as? SKShapeNode {
            let pulse = SKShapeNode(circleOfRadius: L.bumperRadius)
            pulse.strokeColor = ring.strokeColor
            pulse.lineWidth = 2
            pulse.zPosition = 9
            bumper.addChild(pulse)
            pulse.run(.sequence([
                .group([.scale(to: 1.8, duration: 0.25), .fadeOut(withDuration: 0.25)]),
                .removeFromParent(),
            ]))
        }
    }

    private func hitSling(_ sling: SKNode, kick: CGVector, ball entity: BallEntity) {
        guard kickAllowed(sling), let ballBody = entity.node.physicsBody else { return }
        // Real slings vary with hit position; jitter the kick angle so two
        // slings can't form a lossless resonance, and damp rapid rallies.
        if now - lastSlingTime > 2.0 { slingRally = 0 }
        lastSlingTime = now
        slingRally += 1
        let angle = atan2(kick.dy, kick.dx) + CGFloat.random(in: -0.22...0.22)
        let damp = pow(0.85, CGFloat(max(0, slingRally - 2)))
        let impulse = Tuning.slingKick * damp * CGFloat.random(in: 0.9...1.05)
        ballBody.applyImpulse(CGVector(dx: cos(angle) * impulse,
                                       dy: sin(angle) * impulse))
        sounds.play("slingshot", volume: 0.8, pan: pan(entity.node.position.x))
        if let i = slingNodes.firstIndex(where: { $0.node === sling }) {
            slingPlastics[i].flash(magentaColor)
        }
        award(Score.sling, at: entity.node.position, color: magentaColor)
        bonusUnits += 2
        burst(at: entity.node.position, color: magentaColor, count: 8, speed: 120, size: 5)
        if let shape = sling as? SKShapeNode {
            let normalWidth = shape.lineWidth
            shape.run(.sequence([
                .run { shape.lineWidth = normalWidth + 3 },
                .wait(forDuration: 0.08),
                .run { shape.lineWidth = normalWidth },
            ]))
        }
    }

    private func hitDropTarget(_ target: SKShapeNode) {
        guard let index = dropTargets.firstIndex(of: target),
              !dropTargetDown[index], kickAllowed(target) else { return }
        dropTargetDown[index] = true
        target.physicsBody?.categoryBitMask = 0
        sounds.play("drop", volume: 0.9, pan: pan(target.position.x))
        let points = activeMode == .gravityWell ? 2500 : Score.dropTarget
        award(points, at: target.position, color: cyanColor)
        bonusUnits += 25
        burst(at: target.position, color: cyanColor, count: 14, speed: 140)
        // Dropped: fill goes dark, the thin outline remains as the marker.
        target.run(.sequence([
            .run { target.fillColor = .white },
            .wait(forDuration: 0.06),
            .run { target.fillColor = .clear },
        ]))

        if dropTargetDown.allSatisfy({ $0 }) {
            sounds.play("jackpot", volume: 1.0, jitter: 0)
            burst(at: CGPoint(x: 152, y: 480), color: amberColor, count: 30, speed: 240)
            award(Score.dropBank, at: CGPoint(x: 152, y: 490), color: amberColor)
            if !modeLit && activeMode == nil {
                modeLit = true
                banner("MODE LIT AT SAUCER", color: cyanColor)
                sounds.say("modelit", priority: 1, delay: 0.4)
            }
            refreshHUD()
            later(1.2) { [weak self] in self?.resetDropBank() }
        }
    }

    private func resetDropBank() {
        for (i, target) in dropTargets.enumerated() {
            dropTargetDown[i] = false
            target.physicsBody?.categoryBitMask = Cat.dropTarget
            target.fillColor = cyanColor
        }
        sounds.play("drop", volume: 0.6)
    }

    private func hitStandup(_ target: SKShapeNode) {
        guard let index = standupNodes.firstIndex(of: target), kickAllowed(target) else { return }
        sounds.play("target", volume: 0.85, pan: pan(target.position.x))
        if standupHit[index] {
            // Already spent this round: token score, brief flash, stays unlit.
            award(Score.standupRepeat, at: target.position, color: magentaColor)
            target.run(.sequence([
                .run { target.fillColor = NSColor(calibratedWhite: 1, alpha: 0.35) },
                .wait(forDuration: 0.06),
                .run { target.fillColor = .clear },
            ]))
            return
        }
        standupHit[index] = true
        award(Score.standup, at: target.position, color: magentaColor)
        bonusUnits += 25
        burst(at: target.position, color: magentaColor, count: 10, speed: 120, size: 5)
        // Hit: fill goes dark, the thin outline remains as the marker.
        target.run(.sequence([
            .run { target.fillColor = .white },
            .wait(forDuration: 0.08),
            .run { target.fillColor = .clear },
        ]))

        if standupHit.allSatisfy({ $0 }) {
            sounds.play("jackpot", volume: 0.7, jitter: 0)
            burst(at: CGPoint(x: 405, y: 505), color: amberColor, count: 24, speed: 200)
            award(Score.standupSet, at: CGPoint(x: 400, y: 505), color: amberColor)
            if !multiball && locks < 2 && !lockLit {
                lockLit = true
                banner("LOCK LIT AT SAUCER", color: magentaColor)
                sounds.say("locklit", priority: 1, delay: 0.4)
            }
            refreshHUD()
            later(1.0) { [weak self] in self?.resetStandups() }
        }
    }

    private func resetStandups() {
        for (i, target) in standupNodes.enumerated() {
            standupHit[i] = false
            target.fillColor = magentaColor
        }
        sounds.play("target", volume: 0.5)
    }

    // MARK: - Phase 3 reactions

    private func hitRollover(_ sensor: SKNode) {
        guard let index = novaSensors.firstIndex(of: sensor),
              kickAllowed(sensor, cooldown: 0.3) else { return }
        sounds.play("rollover", volume: 0.8, pan: pan(sensor.position.x), jitter: 0)
        if firstLaneForTest == nil { firstLaneForTest = index }
        resolveSkillShot(lane: index)
        award(Score.rollover, at: sensor.position, color: cyanColor)
        bonusUnits += 50
        if !novaLit[index] {
            novaLit[index] = true
            novaLabels[index].fontColor = amberColor
            novaLabels[index].run(.sequence([.scale(to: 1.5, duration: 0.1),
                                             .scale(to: 1.0, duration: 0.15)]))
            burst(at: sensor.position, color: cyanColor, count: 8, speed: 90, size: 5)
        }
        if novaLit.allSatisfy({ $0 }) {
            let points = Score.novaComplete * multiplier
            multiplier = min(8, multiplier + 1)
            sounds.play("jackpot", volume: 0.7, jitter: 0)
            burst(at: CGPoint(x: 220, y: 880), color: amberColor, count: 40, speed: 280)
            flash(amberColor, intensity: 0.12)
            award(points, at: CGPoint(x: 220, y: 840), color: amberColor)
            banner("NOVA!  BONUS \u{00D7}\(multiplier)")
            sounds.say("nova", priority: 2, delay: 0.3)
            novaLit = [false, false, false, false]
            for label in novaLabels { label.fontColor = cyanColor.withAlphaComponent(0.35) }
            // NOVA also raises the outlane guards again (or extends them).
            if !tilted && !gameOver {
                if !guardsUp { banner("GUARDS UP", color: amberColor) }
                guardDeadline = now + guardTime
                setGuards(up: true)
            }
            refreshHUD()
        }
    }

    private func hitSpinner(_ entity: BallEntity) {
        guard let body = entity.node.physicsBody else { return }
        guard kickAllowed(spinnerBar, cooldown: 0.5) else { return }
        let spins = max(3, min(14, Int(abs(body.velocity.dy) / 90)))
        let per = activeMode == .solarFlare ? 500 : Score.spinnerSpin
        award(spins * per, at: CGPoint(x: 48, y: 700), color: amberColor)
        bonusUnits += spins * 10
        spin(spinnerBar, times: spins, panX: L.spinnerCenter.x)
    }

    private func hitRampSpinner(_ entity: BallEntity) {
        guard kickAllowed(rampSpinnerBar, cooldown: 0.5) else { return }
        let spins = max(3, min(14, Int(abs(entity.railV) / 90)))
        let per = activeMode == .solarFlare ? 500 : Score.spinnerSpin
        award(spins * per, at: CGPoint(x: 280, y: 600), color: amberColor)
        bonusUnits += spins * 10
        spin(rampSpinnerBar, times: spins, panX: L.rampSpinnerCenter.x)
    }

    private func hitSaucer(_ entity: BallEntity) {
        guard !saucerBusy, !entity.onRamp, !tilted else { return }
        saucerBusy = true
        sounds.play("saucer", volume: 0.9, pan: pan(L.saucerCenter.x))
        saucerNode.run(.sequence([.scale(to: 1.25, duration: 0.1),
                                  .scale(to: 1.0, duration: 0.2)]))
        burst(at: L.saucerCenter, color: amberColor, count: 12, speed: 110, size: 5)
        removeBall(entity)
        if extraBallLit { collectExtraBall() }

        if !multiball && lockLit && locks < 2 {
            locks += 1
            lockLit = false
            sounds.play("lock", volume: 0.9, jitter: 0)
            award(Score.lock, at: L.saucerCenter, color: magentaColor)
            banner(locks == 2 ? "BALL 2 LOCKED — SAUCER FOR MULTIBALL" : "BALL LOCKED")
            sounds.say("locked", priority: 2, delay: 0.3)
            refreshHUD()
            later(0.9) { [weak self] in
                guard let self else { return }
                self.spawnBall(at: L.ballSpawn)
                self.saucerBusy = false
            }
        } else if !multiball && locks >= 2 {
            startMultiball()
        } else if !multiball && modeLit && activeMode == nil {
            modeLit = false
            startMode()
            pendingEjects += 1
            later(1.1) { [weak self] in self?.ejectFromSaucer() }
        } else {
            let points = activeMode == .gravityWell ? 10000 : Score.saucer
            award(points, at: L.saucerCenter, color: amberColor)
            bonusUnits += 50
            pendingEjects += 1
            later(0.9) { [weak self] in self?.ejectFromSaucer() }
        }
    }

    private(set) var wormholeStatsForTest = (captures: 0, warps: 0)

    private func markWormholeVisited(_ i: Int) {
        guard !extraBallLit, !continuousPlay, !freePlay,
              extraBallsEarned < Tuning.extraBallsPerGame else { return }
        wormholeVisited[i] = true
        if wormholeVisited.allSatisfy({ $0 }) {
            extraBallLit = true
            banner("EXTRA BALL LIT AT SAUCER", color: amberColor)
            // Outranks the warp callout that follows a second later.
            sounds.say("eblit", priority: 3, delay: 0.3)
        }
        refreshHUD()
    }

    private func collectExtraBall() {
        extraBallLit = false
        extraBalls += 1
        extraBallsEarned += 1
        wormholeVisited = [false, false]
        sounds.play("jackpot", volume: 1.0, jitter: 0)
        flash(amberColor, intensity: 0.18)
        burst(at: L.saucerCenter, color: amberColor, count: 36, speed: 260)
        banner("EXTRA BALL!", color: amberColor)
        for plastic in slingPlastics { plastic.flash(amberColor, times: 3) }
        // Priority 4: a mode/lock callout from the same saucer hit must not cut it off.
        sounds.say("extraball", priority: 4, delay: 0.2)
        refreshHUD()
    }

    private func pulseWormhole(_ i: Int) {
        wormholeNodes[i].run(.sequence([.scale(to: 1.3, duration: 0.1),
                                        .scale(to: 1.0, duration: 0.25)]))
        burst(at: L.wormholeCenters[i], color: violetColor, count: 18, speed: 130, size: 5)
    }

    private func hitWormhole(_ entity: BallEntity, index i: Int) {
        guard !wormholeBusy[i], !entity.onRamp, !tilted,
              let v = entity.node.physicsBody?.velocity,
              hypot(v.dx, v.dy) <= Tuning.wormholeMaxSpeed else { return }
        let other = 1 - i
        let warp = !wormholeBusy[other] && Double.random(in: 0..<1) < wormholeWarpChance
        let out = warp ? other : i
        wormholeBusy[i] = true
        wormholeBusy[out] = true
        wormholeStatsForTest.captures += 1
        if warp { wormholeStatsForTest.warps += 1 }

        let center = L.wormholeCenters[i]
        sounds.play("wormhole", volume: 0.9, pan: pan(center.x), jitter: 0.04)
        pulseWormhole(i)
        pendingEjects += 1
        removeBall(entity)
        award(Score.wormhole, at: CGPoint(x: max(center.x, 60), y: center.y), color: violetColor)
        bonusUnits += 50
        markWormholeVisited(i)

        if warp {
            // Hyperspace sweep during the 1 s transit, panned toward the exit.
            let exitPan = pan(L.wormholeCenters[out].x)
            later(0.25) { [weak self] in
                self?.sounds.play("warp", volume: 0.85, pan: exitPan, jitter: 0)
            }
            // Faint beam between the holes while the ball is "in transit".
            let beam = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: center)
            path.addLine(to: L.wormholeCenters[out])
            beam.path = path
            beam.strokeColor = violetColor.withAlphaComponent(0.55)
            beam.lineWidth = 3
            beam.glowWidth = 3
            beam.zPosition = 7
            beam.alpha = 0
            field.addChild(beam)
            beam.run(.sequence([.fadeIn(withDuration: 0.25), .wait(forDuration: 0.5),
                                .fadeOut(withDuration: 0.4), .removeFromParent()]))
        }

        later(1.0) { [weak self] in
            guard let self else { return }
            self.pendingEjects = max(0, self.pendingEjects - 1)
            if warp {
                self.wormholeBusy[i] = false
                self.pulseWormhole(out)
                self.flash(self.violetColor, intensity: 0.15)
                self.banner("WARP!", color: self.violetColor)
                self.sounds.say("warp", priority: 2)
                let c = L.wormholeCenters[out]
                self.award(Score.wormholeWarp, at: CGPoint(x: max(c.x, 60), y: c.y + 24),
                           color: self.violetColor)
            }
            self.ejectFromWormhole(out)
            // The ejecting hole stays closed (dimmed) for a moment, so a ball
            // bouncing straight back — e.g. off the bumpers — rolls over it.
            let node = self.wormholeNodes[out]
            node.run(.fadeAlpha(to: 0.35, duration: 0.15))
            self.later(Tuning.wormholeCooldown) { [weak self] in
                self?.wormholeBusy[out] = false
                node.run(.fadeAlpha(to: 1, duration: 0.3))
            }
        }
    }

    private func ejectFromWormhole(_ i: Int) {
        let c = L.wormholeCenters[i]
        sounds.play("eject", volume: 0.9, pan: pan(c.x))
        if i == 0 {
            spawnBall(at: CGPoint(x: c.x + 12, y: c.y + 8), velocity: Tuning.wormholeEject)
        } else {
            let v = Tuning.wormholeCenterEject
            let sign: CGFloat = Bool.random() ? 1 : -1
            spawnBall(at: c, velocity: CGVector(dx: v.dx * sign, dy: v.dy))
        }
    }

    private func ejectFromSaucer() {
        pendingEjects = max(0, pendingEjects - 1)
        sounds.play("eject", volume: 0.9, pan: pan(L.saucerCenter.x))
        spawnBall(at: CGPoint(x: L.saucerCenter.x - 14, y: L.saucerCenter.y - 8),
                  velocity: Tuning.saucerEject)
        // Brief grace so the ejected ball doesn't instantly re-trigger.
        later(0.5) { [weak self] in self?.saucerBusy = false }
    }

    private func startMultiball() {
        multiball = true
        locks = 0
        sounds.play("multiball", volume: 1.0, jitter: 0)
        banner("MULTIBALL!", color: magentaColor)
        sounds.say("multiball", priority: 3, delay: 0.2)
        flash(magentaColor, intensity: 0.2)
        burst(at: L.saucerCenter, color: magentaColor, count: 40, speed: 300)
        for (i, plastic) in slingPlastics.enumerated() {
            plastic.setStrobe(true, color: magentaColor, phase: Double(i) * 0.25)
        }
        // Bumper rings strobe for the duration of multiball.
        for bumper in bumperNodes {
            bumper.childNode(withName: "ring")?.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.12), .fadeAlpha(to: 1.0, duration: 0.12),
            ])), withKey: "mb")
        }
        refreshHUD()
        refreshLamps()
        // Release the captured ball plus the two locked ones, staggered.
        for i in 0..<3 {
            later(0.6 + Double(i) * 0.4) { [weak self] in
                guard let self else { return }
                self.sounds.play("eject", volume: 0.8)
                self.spawnBall(at: CGPoint(x: L.saucerCenter.x - 14, y: L.saucerCenter.y - 8),
                               velocity: Tuning.saucerEject)
            }
        }
        later(2.0) { [weak self] in self?.saucerBusy = false }
    }

    private func endMultiball() {
        multiball = false
        stopMultiballLights()
        banner("MULTIBALL OVER", color: cyanColor)
        refreshHUD()
        refreshLamps()
    }

    private func stopMultiballLights() {
        for plastic in slingPlastics { plastic.setStrobe(false, color: magentaColor, phase: 0) }
        for bumper in bumperNodes {
            let ring = bumper.childNode(withName: "ring")
            ring?.removeAction(forKey: "mb")
            ring?.alpha = 1
        }
    }

    private func startMode() {
        let mode = Mode.allCases.randomElement()!
        activeMode = mode
        modeEndTime = now + Tuning.modeDuration
        sounds.play("mode", volume: 0.9, jitter: 0)
        flash(cyanColor, intensity: 0.14)
        banner(mode.name, color: cyanColor)
        switch mode {
        case .asteroidStorm: sounds.say("asteroid", priority: 3, delay: 0.3)
        case .solarFlare: sounds.say("solarflare", priority: 3, delay: 0.3)
        case .gravityWell: sounds.say("gravitywell", priority: 3, delay: 0.3)
        }
        later(1.0) { [weak self] in
            self?.banner(mode.hint, color: self?.cyanColor)
        }
        modeLabel.isHidden = false
        refreshHUD()
    }

    private func endMode() {
        activeMode = nil
        modeLabel.isHidden = true
        banner("MODE OVER", color: cyanColor)
    }

    private(set) var rampStatsForTest = (entered: 0, completed: 0)

    private func enterRamp(_ entity: BallEntity, s: CGFloat, along: CGFloat, lateral: CGFloat) {
        rampStatsForTest.entered += 1
        entity.onRamp = true
        entity.railS = s
        entity.railV = min(along, 1400)
        entity.railLateral = lateral
        entity.node.physicsBody?.isDynamic = false   // the rail drives the ball
        // Rolling whir on the wire ramp; louder and higher for faster entries.
        let pace = Float(min(1, max(0, (entity.railV - 300) / 900)))
        sounds.play("ramp", volume: 0.45 + 0.4 * pace, pan: pan(L.rampRailPoints[0].x), jitter: 0)
        entity.node.zPosition = 15
        entity.node.setScale(1.12)
        entity.shadow.zPosition = 13
    }

    private func exitRamp(_ entity: BallEntity, completed: Bool) {
        guard entity.onRamp else { return }
        entity.onRamp = false
        entity.railLateral = 0
        entity.node.physicsBody?.isDynamic = true
        entity.node.zPosition = 10
        entity.node.setScale(1.0)
        entity.shadow.zPosition = 8
        let v = max(abs(entity.railV), 120)
        if completed {
            // Drop off the ramp end aimed down the left inlane.
            let end = entity.node.position
            let ax = L.rampExitAim.x - end.x, ay = L.rampExitAim.y - end.y
            let len = max(hypot(ax, ay), 0.001)
            entity.node.physicsBody?.velocity = CGVector(dx: ax / len * v, dy: ay / len * v)
        } else {
            let dir = rampRail.direction(at: 30)
            entity.node.physicsBody?.velocity = CGVector(dx: -dir.dx * v, dy: -dir.dy * v)
        }
        guard completed else { return }
        rampStatsForTest.completed += 1
        // A tilted ball still rides the ramp but scores nothing, as everywhere
        // else on a tilted table (no jackpot, no ramp award, no bonus).
        guard !tilted else { return }
        if multiball {
            sounds.play("jackpot", volume: 1.0, jitter: 0)
            flash(magentaColor, intensity: 0.2)
            burst(at: CGPoint(x: 80, y: 560), color: magentaColor, count: 44, speed: 320)
            award(Score.jackpot, at: CGPoint(x: 130, y: 580), color: magentaColor)
            banner("JACKPOT!", color: magentaColor)
            for plastic in slingPlastics { plastic.flash(magentaColor, times: 3) }
            sounds.say("jackpot", priority: 3, delay: 0.15)
        } else {
            sounds.play("rollover", volume: 0.9, pan: pan(70), jitter: 0)
            burst(at: CGPoint(x: 80, y: 560), color: amberColor, count: 16, speed: 150)
            let points = activeMode == .solarFlare ? 5000 : Score.ramp
            award(points, at: CGPoint(x: 125, y: 575), color: amberColor)
        }
        bonusUnits += 100
        majorShot(at: CGPoint(x: 140, y: 610))
    }

    /// Slope-accurate motion along the rail: the table's gravity component
    /// along the local rail direction decelerates climbs and accelerates
    /// descents; rolling drag bleeds a little energy. Weak shots stall and
    /// roll back out of the mouth, exactly like an open channel.
    private func updateRailBalls(dt: CGFloat) {
        for entity in balls where entity.onRamp {
            let dir = rampRail.direction(at: entity.railS)
            let slopeAccel = Tuning.gravity * 150 * dir.dy   // pt/s² along rail
            let drag: CGFloat = entity.railV > 0 ? -40 : 40
            entity.railV += (slopeAccel + drag) * dt
            entity.railV = max(min(entity.railV, 1100), -900)
            let previousS = entity.railS
            entity.railS += entity.railV * dt

            if (previousS - L.rampSpinnerS) * (entity.railS - L.rampSpinnerS) < 0 {
                hitRampSpinner(entity)
            }

            if entity.railS <= 0 {
                exitRamp(entity, completed: false)
            } else if entity.railS >= rampRail.total {
                exitRamp(entity, completed: true)
            } else {
                // Ease the entry offset onto the centerline (no snap).
                entity.railLateral *= exp(-14 * dt)
                let p = rampRail.position(at: entity.railS)
                let n = rampRail.normal(at: entity.railS)
                entity.node.position = CGPoint(x: p.x + n.dx * entity.railLateral,
                                               y: p.y + n.dy * entity.railLateral)
            }
        }
    }

    /// A free ball climbs the ramp only if, this frame, it crosses the
    /// mouth lip moving up the ramp, centred in the mouth and travelling
    /// close to the ramp axis. Only the along-axis speed carries onto the
    /// rail. Anything else (glancing, sideways, off-centre) passes under.
    private func checkRampEntry(_ entity: BallEntity, body: SKPhysicsBody, dt: CGFloat) {
        let a = L.rampRailPoints[0]
        let u = rampRail.direction(at: 0)
        let n = rampRail.normal(at: 0)
        let p = entity.node.position
        let rx = p.x - a.x, ry = p.y - a.y
        let s = rx * u.dx + ry * u.dy
        guard s >= L.rampLipS, s <= L.rampLipS + 40 else { return }
        let lateral = rx * n.dx + ry * n.dy
        guard abs(lateral) <= L.rampMouthTolerance else { return }
        let v = body.velocity
        let along = v.dx * u.dx + v.dy * u.dy
        let speed = hypot(v.dx, v.dy)
        guard along > 100, along >= speed * cos(L.rampEntryMaxAngle) else { return }
        guard s - along * dt < L.rampLipS else { return }   // crossed the lip just now
        enterRamp(entity, s: s, along: along, lateral: lateral)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 30)
        lastTime = currentTime
        // Game clock: advances only while running, so timers (modes, ball
        // saver, cooldowns) freeze during a pause.
        if gamePaused { return }
        now += dt

        leftFlipper.drive(pressed: leftPressed && !tilted)
        rightFlipper.drive(pressed: rightPressed && !tilted)

        updateSkillShot()
        updateGuards()
        updateCombo()
        // Keep the banner clear of the tilt text / attract display, which
        // can appear while a banner is already up.
        if let b = currentBanner { b.position.y = bannerY }
        if plungerPressed {
            charge = min(1, charge + CGFloat(dt) * Tuning.chargeRate)
            plunger.position.y = L.plungerRest.y - 24 * charge
            plunger.fillColor = NSColor(calibratedRed: 1.0,
                                        green: 0.72 - 0.42 * charge,
                                        blue: 0.30 - 0.18 * charge, alpha: 1)
        }

        if let mode = activeMode {
            if now > modeEndTime {
                endMode()
            } else {
                modeLabel.text = "\(mode.name)  \(Int(modeEndTime - now))s"
            }
        }

        updateRailBalls(dt: CGFloat(dt))

        var anyLaneRising = false
        var anyTopLeftEntering = false
        var anyTopRightEntering = false

        for entity in balls where !entity.onRamp {
            guard let body = entity.node.physicsBody else { continue }
            checkRampEntry(entity, body: body, dt: CGFloat(dt))
            if entity.onRamp { continue }
            steerSkillBall(entity, body: body)
            let p = entity.node.position
            let v = body.velocity
            let speed = hypot(v.dx, v.dy)

            if p.x > L.laneX - 2 && p.y < L.gateY + 24 && v.dy > 40 { anyLaneRising = true }
            // Climbing the left orbit lane past the spinner: arms "orbit made".
            if p.x < 60 && p.y > 700 && p.y < 820 && v.dy > 200 {
                orbitClimbTime[ObjectIdentifier(entity)] = now
            }
            if p.x > 85 && p.x < 180 && p.y > 865 && v.dx > 30 {
                anyTopLeftEntering = true
                // Orbit made: the ball comes round the left orbit through
                // the top-left gate (once per ball per 1.5 s). It must have
                // been climbing the orbit lane just before: a full plunge
                // sweeps left across the arch and bounces off the closed
                // gate moving rightward through this same zone.
                let key = ObjectIdentifier(entity)
                if p.x < 145 && p.y > 880,
                   now - (orbitClimbTime[key] ?? -10) < 1.5,
                   now - (lastOrbitTime[key] ?? -10) > 1.5 {
                    lastOrbitTime[key] = now
                    majorShot(at: CGPoint(x: 120, y: 860))
                    comboStatsForTest.orbits += 1
                }
            }
            if p.x > 270 && p.x < 355 && p.y > 875 && v.dx < -30 { anyTopRightEntering = true }

            // Anti-tunneling speed clamp.
            if speed > Tuning.maxBallSpeed {
                let k = Tuning.maxBallSpeed / speed
                body.velocity = CGVector(dx: v.dx * k, dy: v.dy * k)
            }

            // Ball search: an idle motionless ball outside the plunger lane
            // gets a small kick free. A held flipper suppresses it.
            let atRest = speed < 10 && p.x < L.laneX && !gameOver
                && !leftPressed && !rightPressed
            if atRest {
                if entity.stuckSince == 0 {
                    entity.stuckSince = now
                } else if now - entity.stuckSince > 4 {
                    // Escalate like a real machine's ball search: each
                    // attempt kicks harder until the ball breaks free.
                    let level = CGFloat(min(entity.searchKicks, 3))
                    let dx = CGFloat.random(in: -1...1) * (5 + 5 * level)
                    body.applyImpulse(CGVector(dx: dx, dy: 8 + 7 * level))
                    entity.searchKicks += 1
                    entity.stuckSince = 0
                }
            } else {
                entity.stuckSince = 0
                if speed > 120 { entity.searchKicks = 0 }
            }

            // Safety net: a ball outside the walls is a bug (tunneling) —
            // snap it home. Below the table is the drain sensor's job.
            if p.y > -40 && (p.x < 6 || p.x > 454 || p.y > 948) {
                entity.node.position = L.ballSpawn
                body.velocity = .zero
            }

            if trackMaxY {
                trackedMaxY = max(trackedMaxY, p.y)
            }

            // Comet trail intensity follows speed.
            entity.trail?.particleBirthRate = speed > 550 ? 60 : (speed > 320 ? 24 : 0)
        }

        // One-way gates: open for balls climbing from below, solid from above.
        if let gateBody = gateNode.physicsBody {
            gateBody.categoryBitMask = anyLaneRising ? 0 : Cat.wall
            let atGate = balls.contains {
                $0.node.position.x > L.laneX - 2 && abs($0.node.position.y - L.gateY) < 34
                    && ($0.node.physicsBody?.velocity.dy ?? 0) > 40
            }
            laneGateFlap.setOpen(atGate)
        }
        if let body = topLeftGateBody {
            body.categoryBitMask = anyTopLeftEntering ? 0 : Cat.wall
            topLeftGateFlap.setOpen(anyTopLeftEntering)
        }
        if let body = topRightGateBody {
            body.categoryBitMask = anyTopRightEntering ? 0 : Cat.wall
            topRightGateFlap.setOpen(anyTopRightEntering)
        }

        tiltHeat = max(0, tiltHeat - dt * 0.45)
    }

    override func didSimulatePhysics() {
        for entity in balls {
            let raised = entity.onRamp
            entity.shadow.position = CGPoint(x: entity.node.position.x + (raised ? 7 : 4),
                                             y: entity.node.position.y - (raised ? 11 : 6))
            entity.shadow.isHidden = entity.node.isHidden
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let ballBody = contact.bodyA.categoryBitMask == Cat.ball ? contact.bodyA
            : (contact.bodyB.categoryBitMask == Cat.ball ? contact.bodyB : nil)
        guard let ballBody, let entity = entity(for: ballBody.node) else { return }
        let other = contact.bodyA === ballBody ? contact.bodyB : contact.bodyA
        guard let node = other.node else { return }

        // An elevated ball only interacts with the ramp itself and the drain.
        if entity.onRamp && other.categoryBitMask != Cat.drain {
            return
        }

        switch other.categoryBitMask {
        case Cat.drain:
            drainBall(entity)
        case Cat.bumper:
            hitBumper(node, ball: entity)
        case Cat.sling:
            if let entry = slingNodes.first(where: { $0.node === node }) {
                hitSling(entry.node, kick: entry.kick, ball: entity)
            }
        case Cat.dropTarget:
            if let target = node as? SKShapeNode { hitDropTarget(target) }
        case Cat.standup:
            if let target = node as? SKShapeNode { hitStandup(target) }
        case Cat.rollover:
            hitRollover(node)
        case Cat.spinner:
            hitSpinner(entity)
        case Cat.saucer:
            hitSaucer(entity)
        case Cat.guardPost:
            if let i = guardBodies.firstIndex(of: node) { kickFromGuard(i, ball: entity) }
        case Cat.wormhole:
            if let name = node.name, let i = Int(name.dropFirst("wormhole".count)) {
                hitWormhole(entity, index: i)
            }
        default:
            break
        }
    }

    private func drainBall(_ entity: BallEntity) {
        sounds.play("drain", volume: 0.9)
        burst(at: CGPoint(x: 215, y: 24), color: railColor, count: 10, speed: 90, size: 5)
        removeBall(entity)

        if multiball && balls.count + pendingEjects == 1 {
            endMultiball()
        }
        guard balls.isEmpty && pendingEjects == 0 else { return }

        if freePlay {
            later(0.9) { [weak self] in
                self?.spawnBall(at: L.ballSpawn)
            }
            return
        }

        // Ball saver: a quick loss right after launch comes back for free
        // (not after a tilt — you rocked it, you lose it).
        if now < ballSaveUntil && !tilted {
            ballSaveUntil = 0
            banner("BALL SAVED", color: cyanColor)
            sounds.say("ballsaved", priority: 2)
            later(0.9) { [weak self] in
                self?.spawnBall(at: L.ballSpawn)
            }
            return
        }

        // A ball really lost (not saved, not one of several in multiball):
        // now and then the ship's computer comments. Lowest priority, so a
        // following "Shoot again!" / "Game over." still gets through.
        if Double.random(in: 0..<1) < lostBallQuipChance,
           sounds.say("balllost", priority: 1, delay: 0.35) {
            quipsForTest += 1
        }
        endOfBall()
    }

    private func endOfBall() {
        if activeMode != nil { endMode() }
        let bonus = bonusUnits * multiplier
        if bonus > 0 && !tilted && !continuousPlay {
            score += bonus
            banner("BONUS \(fmt(bonus))" + (multiplier > 1 ? "  (\u{00D7}\(multiplier))" : ""))
        }
        tilted = false
        tiltHeat = 0
        if !gameOver { messageLabel.isHidden = true }
        bonusUnits = 0
        multiplier = 1
        novaLit = [false, false, false, false]
        for label in novaLabels { label.fontColor = cyanColor.withAlphaComponent(0.35) }
        comboCount = 0
        refreshCombo()
        // Wormhole visits count per ball (a lit Extra Ball stays lit).
        if !extraBallLit { wormholeVisited = [false, false] }
        stopGuardTimer()          // no OUTLANES OPEN between balls
        refreshHUD()

        later(1.2) { [weak self] in
            guard let self else { return }
            if self.extraBalls > 0 && !self.continuousPlay && !self.gameOver {
                self.extraBalls -= 1
                self.resetGuards()
                self.banner("SHOOT AGAIN", color: self.amberColor)
                self.sounds.say("shootagain", priority: 3)
                self.refreshHUD()
                self.spawnBall(at: L.ballSpawn)
            } else if self.continuousPlay {
                self.resetGuards()
                self.refreshHUD()
                self.spawnBall(at: L.ballSpawn)
            } else if self.ballNumber < self.ballsPerGame {
                self.ballNumber += 1
                self.resetGuards()
                self.refreshHUD()
                self.spawnBall(at: L.ballSpawn)
            } else {
                self.endGame()
            }
        }
    }

    private func endGame() {
        gameOver = true
        messageLabel.isHidden = true      // never a TILT left over the attract show
        sounds.play("gameover", volume: 1.0, jitter: 0)

        let isNewBest = score > (highScores.first ?? 0) && score > 0
        if score > 0 {          // a scoreless game is no high score
            highScores = Array((highScores + [score]).sorted(by: >).prefix(5))
            UserDefaults.standard.set(highScores, forKey: "highScores")
        }

        // Game lamps go dark; the result shows on the attract display until
        // the show itself starts (3.5 s, after the voice and any high-score
        // fanfare). Space / Return start a new game after a short lockout.
        gameOverTime = now
        lastGameScore = score
        clearGameLamps()
        showAttractSlide(AttractShow.gameOver(score: score, best: highScores.first ?? score))
        sounds.say("gameover", priority: 4, delay: 0.5)
        if isNewBest {
            banner("NEW HIGH SCORE!", color: magentaColor)
            later(2.1) { [weak self] in self?.sounds.say("highscore", priority: 4) }
            flash(amberColor, intensity: 0.15)
        }
        run(.sequence([
            .wait(forDuration: Tuning.startLockout),
            .run { [weak self] in self?.showStartPrompt() },
            .wait(forDuration: 3.5 - Tuning.startLockout),
            .run { [weak self] in self?.startAttract() },
        ]), withKey: "gameOverShow")
    }

    /// Game over: every game lamp off (a lit lock, mode, Extra Ball, combo or
    /// a skill-shot letter would otherwise keep blinking through the show).
    private func clearGameLamps() {
        disarmSkillShot()
        lockLit = false
        modeLit = false
        extraBallLit = false
        wormholeVisited = [false, false]
        resetGuards(sound: false)
        comboCount = 0
        refreshCombo()          // arrows, sling lamps, lamps and HUD
    }

    // MARK: - Attract mode

    private func startAttract() {
        guard gameOver, !attractRunning else { return }
        attractRunning = true
        attractTitle.isHidden = false
        attractTitle.setScale(1.0)
        for plastic in slingPlastics { plastic.setBreathing(true, color: magentaColor) }
        attractTitle.run(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.8), .scale(to: 1.0, duration: 0.8),
        ])), withKey: "attract")

        startNovaChase()
        for (i, bumper) in bumperNodes.enumerated() {
            bumper.childNode(withName: "ring")?.run(.repeatForever(.sequence([
                .wait(forDuration: Double(i) * 0.3),
                .fadeAlpha(to: 0.2, duration: 0.3),
                .fadeAlpha(to: 1.0, duration: 0.3),
                .wait(forDuration: Double(2 - i) * 0.3),
            ])), withKey: "attract")
        }
        showStartPrompt()
        attractCycle = []
        attractIndex = -1
        turnAttractPage(by: 1)
        scheduleAttractVoice()
    }

    /// Now and then the ship's computer invites a player (callout "attract",
    /// one take per line). Only while the app is in front — a background app
    /// that talks would be a nuisance — and at the lowest priority.
    private func scheduleAttractVoice() {
        let t = attractVoiceTiming
        run(.sequence([
            .wait(forDuration: t.first, withRange: t.first * 0.3),
            .repeatForever(.sequence([
                .run { [weak self] in
                    guard let self, self.attractRunning, NSApp.isActive else { return }
                    self.sounds.say("attract", priority: 1)
                },
                .wait(forDuration: t.every, withRange: t.every * 0.45),
            ])),
        ]), withKey: "attractVoice")
    }

    private func stopAttract() {
        attractRunning = false
        removeAction(forKey: "gameOverShow")
        removeAction(forKey: "attractMsg")
        removeAction(forKey: "attractVoice")
        stopAttractHighlight()
        attractPanel.removeAllActions()
        attractPanel.isHidden = true
        startPrompt.removeAllActions()
        startPrompt.isHidden = true
        for plastic in slingPlastics { plastic.setBreathing(false, color: magentaColor) }
        attractTitle.removeAllActions()
        attractTitle.fontColor = amberColor
        attractTitle.isHidden = true
        stopNovaChase()
        for bumper in bumperNodes {
            let ring = bumper.childNode(withName: "ring")
            ring?.removeAction(forKey: "attract")
            ring?.alpha = 1
        }
    }

    /// Moves the show `delta` pages on: the timer pages forward, the flipper
    /// buttons page by hand (right = next, left = back). Past the last page
    /// a fresh cycle is built; back from the first wraps to the cycle's end.
    /// Every page then gets its full display time.
    private func turnAttractPage(by delta: Int) {
        guard attractRunning else { return }
        var i = attractIndex + delta
        if attractCycle.isEmpty || i >= attractCycle.count {
            attractCycle = AttractShow.cycle(step: attractStep,
                                             highScores: highScores.filter { $0 > 0 },
                                             lastScore: lastGameScore)
            attractStep += 1
            i = 0
        } else if i < 0 {
            i = attractCycle.count - 1
        }
        attractIndex = i
        let slide = attractCycle[i]
        showAttractSlide(slide)
        run(.sequence([
            .wait(forDuration: slide.duration),
            .run { [weak self] in self?.attractPanel.run(.fadeOut(withDuration: 0.18)) },
            .wait(forDuration: 0.22),
            .run { [weak self] in self?.turnAttractPage(by: 1) },
        ]), withKey: "attractMsg")
    }

    private func attractColor(_ tint: AttractSlide.Tint) -> NSColor {
        switch tint {
        case .amber: return amberColor
        case .cyan: return cyanColor
        case .magenta: return magentaColor
        case .white: return .white
        }
    }

    /// Puts a page on the display panel (sized to its text, framed in its
    /// colour, popping in like a banner) and lights what it talks about.
    private func showAttractSlide(_ slide: AttractSlide) {
        stopAttractHighlight()
        let color = attractColor(slide.tint)
        attractText.attributedText = slide.attributedText(titleColor: color)
        attractText.position = .zero
        let f = attractText.frame                     // panel coordinates
        attractText.position = CGPoint(x: -f.midX, y: -f.midY)
        let w = max(224, f.width + 28), h = f.height + 26
        attractPanel.path = CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                                   cornerWidth: 10, cornerHeight: 10, transform: nil)
        attractPanel.strokeColor = color.withAlphaComponent(0.85)
        attractPanel.removeAllActions()
        attractPanel.isHidden = false
        attractPanel.alpha = 0
        attractPanel.setScale(0.85)
        attractPanel.run(.group([.fadeIn(withDuration: 0.12), .scale(to: 1.0, duration: 0.16)]))
        attractSlideForTest = slide.title.replacingOccurrences(of: "\n", with: " ")
        if let h = slide.highlight { startAttractHighlight(h) }
        if slide.flourish { attractFlourish() }
    }

    private func showStartPrompt() {
        guard gameOver, startPrompt.isHidden else { return }
        startPrompt.isHidden = false
        startPrompt.alpha = 1
        startPrompt.run(.repeatForever(.sequence([
            .wait(forDuration: 0.65),
            .fadeAlpha(to: 0.12, duration: 0.15),
            .wait(forDuration: 0.25),
            .fadeAlpha(to: 1.0, duration: 0.08),
        ])), withKey: "blink")
    }

    /// Opening of each cycle: the slings flash, sparks fly off the bumpers
    /// and the title flickers.
    private func attractFlourish() {
        flash(amberColor, intensity: 0.06)
        for (i, plastic) in slingPlastics.enumerated() {
            plastic.flash(i % 2 == 0 ? amberColor : magentaColor, times: 3)
        }
        for (i, bumper) in bumperNodes.enumerated() {
            bumper.run(.sequence([
                .wait(forDuration: 0.12 * Double(i)),
                .run { [weak self] in
                    guard let self else { return }
                    self.burst(at: bumper.position, color: self.amberColor, count: 12, speed: 130, size: 5)
                },
            ]))
        }
        let title = attractTitle!
        title.run(.repeat(.sequence([
            .run { title.fontColor = .white }, .wait(forDuration: 0.07),
            .run { [weak self] in title.fontColor = self?.amberColor }, .wait(forDuration: 0.07),
        ]), count: 3), withKey: "flicker")
    }

    /// NOVA letters light one after another, round and round.
    private func startNovaChase() {
        for (i, label) in novaLabels.enumerated() {
            label.run(.repeatForever(.sequence([
                .wait(forDuration: Double(i) * 0.25),
                .run { [weak self] in label.fontColor = self?.amberColor },
                .wait(forDuration: 0.25),
                .run { [weak self] in
                    label.fontColor = self?.cyanColor.withAlphaComponent(0.35)
                },
                .wait(forDuration: Double(3 - i) * 0.25 + 0.5),
            ])), withKey: "attract")
        }
    }

    private func stopNovaChase() {
        for label in novaLabels {
            label.removeAction(forKey: "attract")
            label.fontColor = cyanColor.withAlphaComponent(0.35)
        }
    }

    /// A rule teaser lights its part of the table, the way the game itself
    /// lights it (same colours and blink styles).
    private func startAttractHighlight(_ highlight: AttractSlide.Highlight) {
        attractHighlight = highlight
        let blink = { (period: TimeInterval) -> SKAction in
            .repeatForever(.sequence([.fadeAlpha(to: 0.15, duration: period),
                                      .fadeAlpha(to: 1.0, duration: period)]))
        }
        let amber = amberColor, dim = cyanColor.withAlphaComponent(0.35)
        switch highlight {
        case .skillShot:
            // Exactly the real thing: one random letter flashes orange.
            stopNovaChase()
            let label = novaLabels[Int.random(in: 0..<novaLabels.count)]
            label.run(.repeatForever(.sequence([
                .run { label.fontColor = amber }, .wait(forDuration: 0.22),
                .run { label.fontColor = dim }, .wait(forDuration: 0.22),
            ])), withKey: "attractHi")
            plunger.run(blink(0.3), withKey: "attractHi")
        case .guards:
            for arch in guardArches { arch.run(blink(0.2), withKey: "attractHi") }
            guardCounter.run(blink(0.3), withKey: "attractHi")
        case .nova:
            // Spelled letter by letter, then the completed word flashes.
            stopNovaChase()
            for (i, label) in novaLabels.enumerated() {
                label.run(.sequence([
                    .wait(forDuration: 0.3 + Double(i) * 0.4),
                    .run { label.fontColor = amber },
                    .wait(forDuration: Double(3 - i) * 0.4 + 0.4),
                    .repeatForever(.sequence([
                        .run { label.fontColor = .white }, .wait(forDuration: 0.12),
                        .run { label.fontColor = amber }, .wait(forDuration: 0.12),
                    ])),
                ]), withKey: "attractHi")
            }
        case .combos:
            rampArrow.strokeColor = .white
            orbitArrow.isHidden = false
            for arrow in [rampArrow!, orbitArrow!] { arrow.run(blink(0.12), withKey: "attractHi") }
            for plastic in slingPlastics { plastic.setChase(true, color: .white) }
        case .extraBall:
            for ring in wormholeVisitRings {
                ring.isHidden = false
                ring.run(blink(0.25), withKey: "attractHi")
            }
            extraBallLabel.isHidden = false
            extraBallLabel.run(blink(0.25), withKey: "attractHi")
        case .multiball:
            saucerNode.strokeColor = magentaColor
            saucerNode.run(blink(0.3), withKey: "attractHi")
            for target in standupNodes { target.run(blink(0.3), withKey: "attractHi") }
        case .modes:
            saucerNode.strokeColor = cyanColor
            saucerNode.run(blink(0.45), withKey: "attractHi")
            for target in dropTargets { target.run(blink(0.3), withKey: "attractHi") }
        }
    }

    private func stopAttractHighlight() {
        guard let highlight = attractHighlight else { return }
        attractHighlight = nil
        let lit: [[SKNode]] = [[rampArrow, orbitArrow, saucerNode, extraBallLabel, plunger],
                               novaLabels, wormholeVisitRings, standupNodes, dropTargets]
        for node in lit.joined() {
            node.removeAction(forKey: "attractHi")
            node.alpha = 1
        }
        for arch in guardArches {
            arch.removeAction(forKey: "attractHi")
            arch.alpha = guardsUp ? 1 : 0
        }
        guardCounter.removeAction(forKey: "attractHi")
        guardCounter.alpha = 1
        if highlight == .skillShot || highlight == .nova {
            stopNovaChase()
            if attractRunning { startNovaChase() }
        }
        refreshCombo()          // arrows and sling lamps back to their state
        refreshLamps(force: true)   // saucer, rings, EB lamp, ramp arrow — redrawn from the game state
    }

    /// Space / Return while no game runs: the start button.
    @discardableResult
    private func pressStart() -> Bool {
        guard gameOver, !freePlay, now - gameOverTime >= Tuning.startLockout else { return false }
        startGame()
        return true
    }

    private func startGame() {
        stopAttract()
        // Whatever the previous game still had scheduled (next ball, ejects,
        // respawns, multiball serves, cooldowns) is void — and so is the
        // state those timers would have restored.
        gameTimers.removeAllActions()
        clearBanners()
        saucerBusy = false
        for node in wormholeNodes { node.removeAllActions(); node.alpha = 1 }
        if multiball { stopMultiballLights() }
        comboCount = 0
        comboDeadline = 0
        ballSaveUntil = 0
        score = 0
        ballNumber = 1
        gameOver = false
        pendingEjects = 0
        wormholeBusy = [false, false]
        wormholeVisited = [false, false]
        extraBallLit = false
        extraBalls = 0
        extraBallsEarned = 0
        multiball = false
        locks = 0
        lockLit = false
        modeLit = false
        bonusUnits = 0
        multiplier = 1
        if activeMode != nil { activeMode = nil; modeLabel.isHidden = true }
        messageLabel.isHidden = true
        for entity in balls { removeBall(entity) }
        resetDropBank()
        resetStandups()
        resetGuards()
        tilted = false          // R during a tilt: the new game starts live
        tiltHeat = 0
        novaLit = [false, false, false, false]
        for label in novaLabels { label.fontColor = cyanColor.withAlphaComponent(0.35) }
        refreshCombo()          // arrows, sling lamps, lamps and HUD back to idle
        spawnBall(at: L.ballSpawn)
        sounds.say("welcome", priority: 1, delay: 0.3)
    }

    // MARK: - Test hooks

    var ballPositionForTest: CGPoint { balls.first?.node.position ?? .zero }
    var scoreForTest: Int { score }
    var ballCountForTest: Int { balls.count }

    var flipperAnglesForTest: (left: CGFloat, right: CGFloat) {
        (leftFlipper.node.zRotation * 180 / .pi, rightFlipper.node.zRotation * 180 / .pi)
    }

    /// Drives a full-strength plunge, for automated verification runs.
    func simulateLaunch() {
        plungerPressed = true
        run(.wait(forDuration: 1.0)) { [weak self] in self?.releasePlunger() }
    }

    func simulateFlip() {
        setFlippersForTest(left: true, right: true)
    }

    func setFlippersForTest(left: Bool, right: Bool) {
        testLeftDown = left
        testRightDown = right
        refreshFlipperInputs()
    }

    var ballSpeedForTest: CGFloat {
        let v = balls.first?.node.physicsBody?.velocity ?? .zero
        return hypot(v.dx, v.dy)
    }

    var trackMaxY = false
    private(set) var trackedMaxY: CGFloat = 0

    /// Reports every physics body on probe rays around the first ball —
    /// for diagnosing invisible resting spots.
    func bodiesBelowBallForTest() -> String {
        guard let first = balls.first else { return "no ball" }
        let b = first.node.position
        let rays: [(String, CGPoint, CGPoint)] = [
            ("down", b, CGPoint(x: b.x, y: b.y - 40)),
            ("left", b, CGPoint(x: b.x - 40, y: b.y)),
            ("right", b, CGPoint(x: b.x + 40, y: b.y)),
        ]
        var out: [String] = []
        for (label, f, t) in rays {
            var found: [String] = []
            physicsWorld.enumerateBodies(alongRayStart: convert(f, from: field),
                                         end: convert(t, from: field)) { body, point, _, _ in
                if body.categoryBitMask != Cat.ball {
                    let p = self.field.convert(point, from: self)
                    found.append("cat=\(body.categoryBitMask)@(\(Int(p.x)),\(Int(p.y)))")
                }
            }
            out.append("\(label): \(found.isEmpty ? "-" : found.joined(separator: ","))")
        }
        let v = first.node.physicsBody?.velocity ?? .zero
        out.append("v=(\(Int(v.dx)),\(Int(v.dy)))")
        return out.joined(separator: "  ")
    }

    /// Places a ball at a point (optionally with initial velocity) so a
    /// verification run can watch where physics takes it.
    func togglePauseForTest() { togglePause() }
    func sayForTest(_ name: String) -> Bool { sounds.say(name, priority: 9) }
    func playForTest(_ name: String) { sounds.play(name, volume: 0.9, jitter: 0) }
    /// First NOVA lane (0…3) rolled over since the last plunge.
    private(set) var firstLaneForTest: Int?
    func launchForTest(charge c: CGFloat) { charge = c; releasePlunger() }
    var comboCountForTest: Int { comboCount }
    private(set) var skillShotsForTest = 0
    var skillLaneForTest: Int? { skillLane }
    /// The playfield (field node only — no HUD, banners or balls) rendered
    /// to an image for the Help window's table map: the field rect plus
    /// `margin` on every side, so field point (x, y) sits at
    /// ((x + margin) / (L.W + 2·margin), (y + margin) / (L.H + 2·margin)) of
    /// the image, y up. (SKView's `crop:` isn't measured from the field's
    /// origin, so the whole node is rendered and cropped here.)
    func playfieldImage(margin m: CGFloat) -> CGImage? {
        guard let view else { return nil }
        let hidden = balls.flatMap { [$0.node, $0.shadow] as [SKNode] }
        for node in hidden { node.isHidden = true }
        defer { for node in hidden { node.isHidden = false } }
        let frame = field.calculateAccumulatedFrame()          // scene coordinates
        guard let full = view.texture(from: field)?.cgImage() else { return nil }
        let s = CGFloat(full.width) / frame.width
        let want = CGRect(x: field.position.x - m, y: field.position.y - m,
                          width: L.W + 2 * m, height: L.H + 2 * m)
        let px = CGRect(x: (want.minX - frame.minX) * s, y: (frame.maxY - want.maxY) * s,
                        width: want.width * s, height: want.height * s).integral
        return full.cropping(to: px)
    }

    func slingLitForTest() { for plastic in slingPlastics { plastic.holdLit(magentaColor) } }
    func bannerForTest(_ text: String, color: NSColor? = nil) { banner(text, color: color) }
    var bannerTextsForTest: [String] {
        children.compactMap { ($0.name == "banner") ? ($0 as? SKLabelNode)?.text : nil }
    }
    func forceSkillLaneForTest(_ lane: Int) { armSkillShot(lane: lane) }
    var extraBallStateForTest: String {
        "visited \(wormholeVisited), lit \(extraBallLit), banked \(extraBalls), "
            + "earned \(extraBallsEarned), ball \(ballNumber), gameOver \(gameOver), HUD \"\(ballLabel.text ?? "")\""
    }
    func restartForTest() { startGame() }
    func nudgeForTest() { nudge(CGVector(dx: 1, dy: 0.3)) }
    func startMultiballForTest() { startMultiball() }
    /// As the saucer starts it: the ball in play is taken, three come out.
    func multiballFromSaucerForTest() {
        for entity in balls { removeBall(entity) }
        saucerBusy = true
        startMultiball()
    }
    func hideHintForTest() { hintShown = false; hintLabel.isHidden = true }
    func majorShotForTest() { majorShot(at: CGPoint(x: 215, y: 400)) }
    var fixStateForTest: String {
        let mbLights = bumperNodes.contains { $0.childNode(withName: "ring")?.action(forKey: "mb") != nil }
        return "multiball \(multiball), mb lights \(mbLights), combo \(comboCount), pending \(pendingEjects), "
            + "tilted \(tilted), saucerBusy \(saucerBusy), wormholeBusy \(wormholeBusy), "
            + "skill \(skillLane.map { L.novaLetters[$0] } ?? "off"), EB lit \(extraBallLit)"
    }
    func lightLockForTest() { lockLit = true; refreshHUD() }
    func awardForTest(_ points: Int) { award(points, at: CGPoint(x: 215, y: 400), color: .white) }
    var saucerAlphaForTest: CGFloat { saucerNode.alpha }
    func simulateAudioOutputChangeForTest() { sounds.simulateOutputChangeForTest() }
    var audioRunningForTest: Bool { sounds.engineRunningForTest }
    var inputStateForTest: String {
        "flippers L \(leftPressed) R \(rightPressed), plunger \(plungerPressed), "
            + "tiltHeat \(Int(tiltHeat * 10))/10"
    }
    var musicMutedForTest: Bool { sounds.musicMuted }
    /// Forces the outlane guards up (timer off) or down, without sound.
    func setGuardsForTest(up: Bool) {
        if up { resetGuards(sound: false) } else { guardDeadline = nil; setGuards(up: false, sound: false) }
    }
    var guardStateForTest: String {
        let left = guardDeadline.map { "\(Int(($0 - now) * 10) / 10)s" } ?? "none"
        return "guards \(guardsUp ? "up" : "down"), time left \(left), "
            + "warning \(guardArches.first?.action(forKey: "warn") != nil)"
    }
    func completeNovaForTest() { for sensor in novaSensors { hitRollover(sensor) } }
    func tiltForTest() { tilt() }
    /// Title of the attract page on the display ("" before the first one).
    private(set) var attractSlideForTest = ""
    var attractStateForTest: String {
        "attract \(attractRunning), panel \(attractPanel.isHidden ? "hidden" : "\"\(attractSlideForTest)\""), "
            + "prompt \(startPrompt.isHidden ? "hidden" : "shown"), highlight \(attractHighlight.map { "\($0)" } ?? "none")"
    }
    /// Presses the start button (Space) as a player would.
    func pressStartForTest() -> Bool { pressStart() }
    var lastVoiceForTest: String? { sounds.lastSpokenForTest }
    var voiceClockForTest: Double? { sounds.voiceClockForTest }
    var voiceTakesForTest: [String: Int] { sounds.voiceTakesForTest }
    func toggleContinuousForTest() { setContinuousPlay(!continuousPlay) }

    /// C: practice on / off. Switching it on mid-ball also drops what only
    /// counts in a real game: an armed skill shot, a lit Extra Ball (and the
    /// wormhole progress toward it) and a running combo.
    private func setContinuousPlay(_ on: Bool) {
        continuousPlay = on
        if on {
            disarmSkillShot()
            extraBallLit = false
            wormholeVisited = [false, false]
            comboCount = 0
        }
        refreshCombo()          // arrows, sling lamps, lamps and HUD
    }
    var gameStateForTest: String {
        "score \(score), ball \(ballNumber), gameOver \(gameOver), HUD \"\(ballLabel.text ?? "")\", "
            + "paused \(gamePaused), balls \(balls.count)"
    }

    func dropBallForTest(at point: CGPoint, velocity: CGVector = .zero) {
        if let first = balls.first {
            first.node.position = point
            first.node.physicsBody?.velocity = velocity
            first.node.physicsBody?.angularVelocity = 0
            if first.onRamp { exitRamp(first, completed: false) }
        } else {
            spawnBall(at: point, velocity: velocity)
        }
    }

    // MARK: - Input

    private func releasePlunger() {
        plungerPressed = false
        let ballInLane = balls.first {
            $0.node.position.x > L.laneX && $0.node.position.y < 140
        }
        if let entity = ballInLane, charge > 0.02, let body = entity.node.physicsBody, !gameOver {
            let impulse = Tuning.launchMin
                + (Tuning.launchMax - Tuning.launchMin) * Tuning.launchStrength(charge)
            body.applyImpulse(CGVector(dx: 0, dy: impulse))
            sounds.play("launch", volume: 0.9, pan: 0.7)
            firstLaneForTest = nil
            if skillLane != nil {
                skillLaunched = true
                skillLaunchTime = now
                skillAimLane = Tuning.skillBandLane(charge)
                skillBall = ObjectIdentifier(entity)
            }
            // The outlane guards drop guardTime after the first launch of a ball.
            if guardsUp && guardDeadline == nil { guardDeadline = now + guardTime }
            if !freePlay && balls.count == 1 {
                ballSaveUntil = now + Tuning.ballSaveWindow
            }
            if hintShown {
                hintShown = false
                hintLabel.run(.sequence([.fadeOut(withDuration: 0.8), .removeFromParent()]))
            }
        }
        charge = 0
        plunger.run(.move(to: L.plungerRest, duration: 0.05))
        plunger.fillColor = amberColor
    }

    /// Letter commands follow the letter printed on the key, on any Latin
    /// layout; layouts without Latin letters fall back to the US positions.
    private func commandLetter(_ event: NSEvent) -> Character? {
        if let ch = event.charactersIgnoringModifiers?.lowercased().first, ch.isASCII { return ch }
        let usPositions: [UInt16: Character] = [35: "p", 46: "m", 11: "b", 9: "v", 8: "c", 15: "r"]
        return usPositions[event.keyCode]
    }

    /// Nudge keys go by position — the bottom row's left, middle and right
    /// keys (Z N / on a US keyboard, Y N - on a German one; KeyLabels names
    /// them for Help and the on-table hint). They win over a letter command
    /// that a layout happens to put on the same key.
    private static let nudgeKeys: [UInt16: CGVector] = [
        6: CGVector(dx: 1, dy: 0.3),      // from the left
        45: CGVector(dx: 0, dy: 1.4),     // slap the front
        44: CGVector(dx: -1, dy: 0.3),    // from the right
    ]

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        let push = Self.nudgeKeys[event.keyCode]
        let letter = push == nil ? commandLetter(event) : nil
        if letter == "p" { togglePause(); return }
        if gamePaused {
            // Frozen: only music toggle and new game get through.
            if letter == "m" { _ = sounds.toggleMusic() }
            if letter == "r" { togglePause(); startGame() }
            return
        }
        if let push { nudge(push); return }
        switch event.keyCode {
        case 123: leftArrowDown = true; refreshFlipperInputs()    // left arrow
        case 124: rightArrowDown = true; refreshFlipperInputs()   // right arrow
        case 49, 125, 36, 76:                 // space, down arrow, return, keypad enter
            // No game running: the plunger key (or Return) is the start
            // button. Otherwise Space / ↓ pull the plunger.
            if gameOver && !freePlay { pressStart() }
            else if event.keyCode == 49 || event.keyCode == 125 { plungerPressed = true }
            return
        default: break
        }
        switch letter {
        case "m":                                                 // music on/off
            banner(sounds.toggleMusic() ? "MUSIC OFF" : "MUSIC ON", color: cyanColor)
        case "b":                                                 // backdrop art on/off
            guard backdropArt != nil else { banner("NO BACKDROP ART", color: cyanColor); break }
            backdropEnabled.toggle()
            buildBackground()
            banner(backdropEnabled ? "BACKDROP ART" : "CLASSIC BACKDROP", color: cyanColor)
        case "v":                                                 // voice callouts on/off
            sounds.voiceMuted.toggle()
            banner(sounds.voiceMuted ? "VOICE OFF" : "VOICE ON", color: cyanColor)
        case "c":                                                 // continuous play
            setContinuousPlay(!continuousPlay)
            banner(continuousPlay ? "CONTINUOUS PLAY — NO SCORING" : "NORMAL PLAY", color: cyanColor)
        case "r":                                                 // new game
            if freePlay {
                dropBallForTest(at: L.ballSpawn)
            } else {
                startGame()
            }
        default: break
        }
    }

    /// Focus left the game window (another app, or Help / About / License in
    /// front): a key released there never reaches the game, so let go of
    /// everything held — flippers drop, a plunger pull is cancelled.
    func releaseHeldInputs() {
        leftArrowDown = false
        rightArrowDown = false
        leftShiftDown = false
        rightShiftDown = false
        ctrlDown = false
        refreshFlipperInputs()
        if plungerPressed {
            plungerPressed = false
            charge = 0
            plunger.run(.move(to: L.plungerRest, duration: 0.05))
            plunger.fillColor = amberColor
        }
    }

    /// P: freeze physics, actions, game clock and music; P again resumes.
    private func togglePause() {
        gamePaused.toggle()
        // Rendering continues so the pause label shows; everything else
        // in the scene is frozen.
        for child in children where child !== pauseLabel {
            child.isPaused = gamePaused
        }
        physicsWorld.speed = gamePaused ? 0 : 1
        // Scene-level timed actions (next ball, attract mode) freeze too.
        // Not scene.isPaused: SKView silently unpauses the scene when the
        // app is reactivated.
        speed = gamePaused ? 0 : 1
        pauseLabel.isHidden = !gamePaused
        sounds.setPaused(gamePaused)
        if gamePaused { plungerPressed = false; charge = 0 }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 123: leftArrowDown = false; refreshFlipperInputs()
        case 124: rightArrowDown = false; refreshFlipperInputs()
        case 49, 125: releasePlunger()
        default: break
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Device-dependent modifier bits report each shift key's actual
        // hardware state — recomputed fresh every event, never inferred.
        // Ctrl uses the generic flag: works on keyboards that don't report
        // per-side bits, and is the primary left-flipper key.
        let raw = event.modifierFlags.rawValue
        leftShiftDown = raw & 0x0002 != 0     // NX_DEVICELSHIFTKEYMASK
        rightShiftDown = raw & 0x0004 != 0    // NX_DEVICERSHIFTKEYMASK
        ctrlDown = event.modifierFlags.contains(.control)
        refreshFlipperInputs()
    }
}
