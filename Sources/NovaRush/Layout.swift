import CoreGraphics
import Foundation

/// All table geometry lives here, in playfield coordinates:
/// origin at the bottom-left of the playfield, y up, 460 x 954 points
/// representing the classic 20.25" x 42" Williams playfield.
enum L {
    static let sceneSize = CGSize(width: 500, height: 1000)
    static let fieldOrigin = CGPoint(x: 20, y: 16)
    static let W: CGFloat = 460
    static let H: CGFloat = 954
    static let ballRadius: CGFloat = 12   // 1-1/16" at 22.7 pt/inch

    // Flippers (standard two-flipper Italian bottom), centered like the
    // rest of the lower playfield on x = 215 — the true playfield center
    // between left wall (0) and shooter-lane divider (430).
    static let leftPivot = CGPoint(x: 132, y: 85)
    static let rightPivot = CGPoint(x: 298, y: 85)
    static let flipperRestAngle: CGFloat = 26 * .pi / 180
    static let flipperStroke: CGFloat = 48 * .pi / 180

    // Shooter lane
    static let laneX: CGFloat = 430
    static let plungerRest = CGPoint(x: 445, y: 37)
    static let ballSpawn = CGPoint(x: 445, y: 66)
    static let gateY: CGFloat = 690

    // Drain hole lips: the rounded bottom curves converge on a visible
    // 60pt opening centered on the playfield (x = 215); lost balls fall
    // through it out of the table.
    static let holeLipLeft = CGPoint(x: 185, y: 10)
    static let holeLipRight = CGPoint(x: 245, y: 10)

    /// Outer boundary: rounded bottom-left curve into the drain hole lip,
    /// left wall, top arch, shooter lane outer wall, lane floor, divider.
    static func outerPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: holeLipLeft)
        p.addQuadCurve(to: CGPoint(x: 0, y: 170), control: CGPoint(x: 0, y: 10))
        p.addLine(to: CGPoint(x: 0, y: 740))
        p.addQuadCurve(to: CGPoint(x: 230, y: 954), control: CGPoint(x: 0, y: 954))
        p.addQuadCurve(to: CGPoint(x: 460, y: 740), control: CGPoint(x: 460, y: 954))
        p.addLine(to: CGPoint(x: 460, y: 6))
        p.addLine(to: CGPoint(x: 430, y: 6))
        p.addLine(to: CGPoint(x: 430, y: 650))
        return p
    }

    /// Rounded bottom-right curve, from the lane divider down to the
    /// right drain hole lip — mirror of the bottom-left curve.
    static func bottomRightPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 430, y: 170))
        p.addQuadCurve(to: holeLipRight, control: CGPoint(x: 430, y: 10))
        return p
    }

    /// Inlane/outlane dividers. Straight segments with generous clearances:
    /// every gap in the lower playfield is either sealed (narrower than the
    /// ball, so it can never enter) or a real path (wider than the ball
    /// everywhere along it, so it can never wedge). The outlane dividers
    /// continue as return walls that run to the flipper bases, so a ball
    /// either feeds a flipper or drains behind it — nothing in between.
    static func guidePaths() -> [CGPath] {
        // The return walls end just above the flipper base circles (sealed
        // 3pt gap, clear of the bat's sweep) so a cradled ball nests in
        // front of the pivot — never behind it, where the bat couldn't
        // launch it. Corners are rounded for looks and smoother rebounds.
        [
            // Outlane divider tops raised to narrow the outlane entrance
            // window against the wall bumps (outlane difficulty tuning).
            roundedPolyline([CGPoint(x: 45, y: 292), CGPoint(x: 45, y: 150),
                             CGPoint(x: 58, y: 128), CGPoint(x: 134, y: 101)], radius: 14),
            roundedPolyline([CGPoint(x: 84, y: 262), CGPoint(x: 84, y: 155),
                             CGPoint(x: 94, y: 148)], radius: 10),
            roundedPolyline([CGPoint(x: 385, y: 292), CGPoint(x: 385, y: 150),
                             CGPoint(x: 372, y: 128), CGPoint(x: 296, y: 101)], radius: 14),
            roundedPolyline([CGPoint(x: 347, y: 262), CGPoint(x: 347, y: 155),
                             CGPoint(x: 336, y: 148)], radius: 10),
        ]
    }

    /// Polyline with rounded corners: every interior vertex becomes a quad
    /// curve. Used for both the visuals and the physics edges, so smoothed
    /// rails also collide smoothly.
    static func roundedPolyline(_ pts: [CGPoint], radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        guard pts.count > 1 else { return p }
        p.move(to: pts[0])
        for i in 1..<(pts.count - 1) {
            let prev = pts[i - 1], v = pts[i], next = pts[i + 1]
            let l1 = hypot(v.x - prev.x, v.y - prev.y)
            let l2 = hypot(next.x - v.x, next.y - v.y)
            let r = max(0.5, min(radius, l1 / 2 - 1, l2 / 2 - 1))
            let a = CGPoint(x: v.x - (v.x - prev.x) / l1 * r, y: v.y - (v.y - prev.y) / l1 * r)
            let b = CGPoint(x: v.x + (next.x - v.x) / l2 * r, y: v.y + (next.y - v.y) / l2 * r)
            p.addLine(to: a)
            p.addQuadCurve(to: b, control: v)
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    /// Outlane guards: a retractable steel arch standing in a chrome-rimmed
    /// slot along the middle of each outlane (centres; the outlanes run
    /// x 0–45 and 385–430). Raised, it leaves 20pt either side — less than
    /// the ball — so it blocks the lane. A passive post there would hold
    /// the ball on top of it against the wall, so a raised arch kicks every
    /// ball that touches it back up into the inlane (`Tuning.guardKick`).
    static let guardPosts = [CGPoint(x: 22.5, y: 245), CGPoint(x: 407.5, y: 245)]
    static let guardLength: CGFloat = 40      // along the lane
    static let guardWidth: CGFloat = 5

    /// Slingshot bodies (static walls in phase 1; kickers arrive in phase 2).
    /// Inner edges run near-parallel to the inlane dividers with sub-ball
    /// gaps so a ball can never wedge between sling and divider.
    /// Bottom tips sit high above the flipper sweep (>35pt clearance over
    /// the bat) so a ball rolling along a flipper can never be pinched
    /// between bat and sling.
    /// Both slings hug their inlane dividers with sealed sub-ball gaps —
    /// exact mirrors about the playfield center (x = 215).
    /// Vertices [top, kicking-face bottom tip, outer bottom] — the kicking
    /// face (toward the playfield) is [0] → [1].
    static let slingTriangles: [[CGPoint]] = [
        [CGPoint(x: 95, y: 195), CGPoint(x: 128, y: 142), CGPoint(x: 92, y: 152)],
        [CGPoint(x: 335, y: 195), CGPoint(x: 302, y: 142), CGPoint(x: 338, y: 152)],
    ]
    static func slingPaths() -> [CGPath] {
        slingTriangles.map { pts in
            let p = CGMutablePath()
            p.addLines(between: pts)
            p.closeSubpath()
            return p
        }
    }

    /// One-way gate at the top of the shooter lane, slanted so a returning
    /// ball rolls off into the playfield.
    static func gatePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: laneX, y: gateY - 2))
        p.addLine(to: CGPoint(x: 460, y: gateY + 6))
        return p
    }

    // MARK: Phase 2 furniture

    /// Pop bumper nest — high in the playfield, as on real machines, so
    /// bumper kicks randomize through the mid-field instead of firing
    /// straight into the outlanes.
    static let bumpers: [CGPoint] = [
        CGPoint(x: 150, y: 782), CGPoint(x: 280, y: 782), CGPoint(x: 215, y: 714),
    ]
    static let bumperRadius: CGFloat = 26

    // (Both side rails are gone: the top gates and the standup cap took
    // over their jobs as the layout evolved.)

    /// Drop-target bank, mid-left, angled to face the flippers. Shifted
    /// right of the ramp's return leg, which descends the corridor at
    /// x ≈ 50–85 to its left.
    static let dropTargetCenters: [CGPoint] = [
        CGPoint(x: 122, y: 455), CGPoint(x: 152, y: 470), CGPoint(x: 182, y: 485),
    ]
    static let dropTargetAngle: CGFloat = atan2(30, 60)
    static let dropTargetSize = CGSize(width: 22, height: 8)

    /// Backboard behind the drop bank: caps and rail keep the pocket behind
    /// a dropped target sealed (shallower than the ball).
    static func dropBankBackPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 109, y: 449))
        p.addLine(to: CGPoint(x: 102, y: 463))
        p.addLine(to: CGPoint(x: 187, y: 506))
        p.addLine(to: CGPoint(x: 195, y: 491))
        return p
    }

    // MARK: Phase 3 — upper playfield

    /// NOVA rollover lanes hanging in the top arch.
    static let novaDividerXs: [CGFloat] = [150, 185, 220, 255, 290]
    static let novaLaneBottom: CGFloat = 855
    static let novaLaneTop: CGFloat = 905
    static let novaLetters = ["N", "O", "V", "A"]
    static var novaLaneCenters: [CGFloat] {
        (0..<4).map { (novaDividerXs[$0] + novaDividerXs[$0 + 1]) / 2 }
    }

    /// Left orbit: lower aiming guide, a gap where the one-way rail gate
    /// crosses, then the upper guide sweeping around the arch to feed the
    /// NOVA lanes from above.
    static func orbitGuidePaths() -> [CGPath] {
        // No lower guide: it blocked left-side shots more than it aimed
        // them (playtest). The upper guide alone defines the channel, and
        // it exits low and early — converging any closer to the arch
        // pinches the channel below ball width (learned the hard way).
        let upper = CGMutablePath()
        upper.move(to: CGPoint(x: 40, y: 640))
        upper.addLine(to: CGPoint(x: 40, y: 740))
        upper.addQuadCurve(to: CGPoint(x: 140, y: 900), control: CGPoint(x: 40, y: 900))
        return [upper]
    }

    /// Top containment gates: one-way flaps sealing the arch left and
    /// right of the NOVA lanes, so a ball reaching the top must exit
    /// down through the lanes into the bumpers. Left gate admits orbit
    /// balls (rightward); right gate admits plunged balls (leftward).
    // Both gates hinge on their lane divider tops (hinging away from the
    // divider leaves a V-pocket between gate edge and divider tip), tips
    // resting against the arch — symmetric, like matched hardware.
    static let topLeftGateHinge = CGPoint(x: 150, y: 905)
    static let topLeftGateTip = CGPoint(x: 118, y: 937)
    static let topRightGateHinge = CGPoint(x: 290, y: 905)
    static let topRightGateTip = CGPoint(x: 327, y: 940)
    static let spinnerCenter = CGPoint(x: 20, y: 690)   // above the rail gate
    static let spinnerSize = CGSize(width: 34, height: 6)

    /// Nebula saucer (mode start / ball lock) in the right pocket between
    /// the ramp's ascending leg and the shooter divider — a deliberate
    /// left-flipper target that no through-lane crosses.
    static let saucerCenter = CGPoint(x: 368, y: 600)
    static let saucerRadius: CGFloat = 16

    /// Wormholes: a linked pair of capture holes. [0] against the left wall
    /// above the left outlane (in the orbit corridor); [1] just below the
    /// middle bumper. Speed-gated (Tuning.wormholeMaxSpeed) so fast balls
    /// skip over them. A captured ball usually comes back out of the same
    /// hole, but with Tuning.wormholeWarpChance it warps out of the other.
    static let wormholeCenters = [CGPoint(x: 22, y: 382), CGPoint(x: 215, y: 645)]
    static let wormholeRadius: CGFloat = 16

    /// Comet ramp: entrance mid-right, climbing over the bumper nest,
    /// return leg down the left corridor into the left inlane. Elevated
    /// layer — its walls only collide with a ball that entered the mouth.
    /// Gentle dome arc (per playtest feedback): up the right, sweeping
    /// under the NOVA lanes over the top bumpers, down the left. Walls are
    /// visual; the rail below defines the physics.
    static func rampOuterWall() -> CGPath {
        roundedPolyline([
            CGPoint(x: 325, y: 450), CGPoint(x: 338, y: 560), CGPoint(x: 342, y: 660),
            CGPoint(x: 329, y: 750), CGPoint(x: 297, y: 822), CGPoint(x: 247, y: 868),
            CGPoint(x: 182, y: 863), CGPoint(x: 130, y: 812), CGPoint(x: 97, y: 737),
            CGPoint(x: 76, y: 644), CGPoint(x: 66.3, y: 560),
        ], radius: 40)
    }
    static func rampInnerWall() -> CGPath {
        roundedPolyline([
            CGPoint(x: 287, y: 455), CGPoint(x: 299, y: 562), CGPoint(x: 303, y: 658),
            CGPoint(x: 292, y: 738), CGPoint(x: 264, y: 797), CGPoint(x: 224, y: 832),
            CGPoint(x: 190, y: 827), CGPoint(x: 151, y: 787), CGPoint(x: 124, y: 722),
            CGPoint(x: 105, y: 635), CGPoint(x: 95.7, y: 560),
        ], radius: 34)
    }
    /// Solid sections of the ramp where its deck is at playfield level:
    /// - Entry: side walls from the mouth up to spinner height (y≈590),
    ///   flared at the bottom into a funnel (mostly on the inner side —
    ///   left-flipper shots arrive from the lower left; the outer flare
    ///   stays small so the left-flipper saucer shot still clears it),
    ///   capped by a peaked roof: above it the deck is elevated and free
    ///   balls pass under; below it they cannot get between the walls.
    /// - Exit: a short solid end (y 560–600) where the drop-off meets the
    ///   playfield, capped the same way. Kept short and high so the
    ///   lower-left corridor (orbit shots, wormhole) stays open.
    /// Peaked caps (not flat bars) so a ball landing on one rolls off.
    static func rampSolidWallPaths() -> [CGPath] {
        [
            // Entry inner wall, funnel flare at the bottom.
            [CGPoint(x: 274, y: 432), CGPoint(x: 287, y: 455), CGPoint(x: 299, y: 562),
             CGPoint(x: 300.2, y: 590)],
            // Entry outer wall, small flare.
            [CGPoint(x: 329, y: 437), CGPoint(x: 325, y: 450), CGPoint(x: 338, y: 560),
             CGPoint(x: 339.2, y: 590)],
            // Entry cap.
            [CGPoint(x: 300.2, y: 590), CGPoint(x: 319.7, y: 602), CGPoint(x: 339.2, y: 590)],
            // Exit end: side walls + cap.
            [CGPoint(x: 70.9, y: 600), CGPoint(x: 66.3, y: 560)],
            [CGPoint(x: 100.7, y: 600), CGPoint(x: 95.7, y: 560)],
            [CGPoint(x: 70.9, y: 600), CGPoint(x: 85.8, y: 612), CGPoint(x: 100.7, y: 600)],
        ].map { pts in
                let p = CGMutablePath()
                p.addLines(between: pts)
                return p
            }
    }
    static func rampCenterline() -> CGPath {
        roundedPolyline(rampRailPoints, radius: 36)
    }
    /// Ramp entry gate (see GameScene.checkRampEntry): arc position of the
    /// mouth lip on the first rail segment, how far off-centre the ball's
    /// centre may be (mouth 38pt wide, ball 24pt → ±7pt clean, a little
    /// slack), and the maximum angle between ball velocity and ramp axis.
    static let rampLipS: CGFloat = 22
    static let rampMouthTolerance: CGFloat = 12
    static let rampEntryMaxAngle: CGFloat = 40 * .pi / 180

    /// Densified centerline for rail-guided ramp traversal. While on the
    /// ramp the ball follows this polyline with slope-accurate physics —
    /// 2D edge containment cannot reliably hold a fast ball through a
    /// 180° turn, so like the classic pinball sims, the ramp is a rail.
    /// The ramp ends high (y≈560), right of the orbit guide, as an elevated
    /// drop-off (wireform style): the ball drops onto the playfield aimed
    /// down the left inlane, and free balls pass under the end. Nothing
    /// solid sits in the lower-left corridor (an earlier low exit chute
    /// steered falling balls into the outlane and blocked orbit shots).
    static let rampRailPoints: [CGPoint] = [
        CGPoint(x: 306, y: 452), CGPoint(x: 318, y: 560), CGPoint(x: 322, y: 660),
        CGPoint(x: 310, y: 745), CGPoint(x: 280, y: 810), CGPoint(x: 235, y: 850),
        CGPoint(x: 185, y: 845), CGPoint(x: 140, y: 800), CGPoint(x: 110, y: 730),
        CGPoint(x: 90, y: 640), CGPoint(x: 80.4, y: 560),
    ]
    /// The completed-ramp ball leaves the rail end aimed here: the middle
    /// of the left inlane mouth (between the dividers at x 45 and 84).
    static let rampExitAim = CGPoint(x: 64, y: 292)

    /// Ramp spinner just past the mouth: triggered by rail position.
    static let rampSpinnerS: CGFloat = 135
    static let rampSpinnerCenter = CGPoint(x: 319, y: 588)
    static let rampSpinnerAngle: CGFloat = atan2(100, 4) - .pi / 2

    /// Standup targets against the shooter-lane divider, facing the field
    /// (sealed 8pt gap behind them — no hidden path into the outlane).
    static let standupCenters: [CGPoint] = [
        CGPoint(x: 418, y: 470), CGPoint(x: 418, y: 505), CGPoint(x: 418, y: 540),
    ]
    static let standupSize = CGSize(width: 8, height: 22)

    /// Rubber bumps protruding from the walls over the outlane entrances
    /// (a fairness feature on most real machines): wall-hugging balls
    /// bounce back toward the inlanes instead of falling straight into
    /// the outlane. Smooth wall-attached bulges — no flat top a ball
    /// could balance on.
    /// Outlane protection bumps; one-way to enable the around-the-horn
    /// pass (see GameScene's bump logic).
    static func outlaneBumpPaths() -> [CGPath] {
        // Symmetric rubber bulges — the only shape that has never produced
        // a resting spot (every asymmetric taper variant did). They are plain
        // solid rubber: a ball going around the horn climbs past them into
        // open field. Raised above the outlane entrance, at the original proportions —
        // enlarging the bulge flattens its top into a resting shelf
        // (verified by probes), so size stays as proven.
        // 36pt is the stability threshold: any larger (even proportionally
        // scaled) and the apex flattens enough for a ball to rest on.
        // Outlane difficulty is tuned via the divider tops instead.
        let l = CGMutablePath()
        l.move(to: CGPoint(x: 0, y: 348))
        l.addQuadCurve(to: CGPoint(x: 0, y: 312), control: CGPoint(x: 36, y: 330))
        l.closeSubpath()
        let r = CGMutablePath()
        r.move(to: CGPoint(x: 430, y: 348))
        r.addQuadCurve(to: CGPoint(x: 430, y: 312), control: CGPoint(x: 394, y: 330))
        r.closeSubpath()
        return [l, r]
    }

    /// Deflector cap above the standup stack: a ball dropping down the
    /// divider corridor is shed into the field instead of coming to rest
    /// on top of the highest target.
    static func standupCapPath() -> CGPath {
        // Steep (64°) and spanning the whole divider corridor: a ball
        // dropping in slides off to the left; nothing can rest on it.
        // (The old shallower cap plus the since-removed side rail shared
        // this job.)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 430, y: 596))
        p.addLine(to: CGPoint(x: 408, y: 550))
        return p
    }

    /// Closed playfield silhouette used to clip the background texture —
    /// follows the walls exactly, including the rounded bottom.
    static func fieldSilhouette() -> CGPath {
        let p = CGMutablePath()
        p.move(to: holeLipLeft)
        p.addQuadCurve(to: CGPoint(x: 0, y: 170), control: CGPoint(x: 0, y: 10))
        p.addLine(to: CGPoint(x: 0, y: 740))
        p.addQuadCurve(to: CGPoint(x: 230, y: 954), control: CGPoint(x: 0, y: 954))
        p.addQuadCurve(to: CGPoint(x: 460, y: 740), control: CGPoint(x: 460, y: 954))
        p.addLine(to: CGPoint(x: 460, y: 6))
        p.addLine(to: CGPoint(x: 430, y: 6))
        p.addLine(to: CGPoint(x: 430, y: 170))
        p.addQuadCurve(to: holeLipRight, control: CGPoint(x: 430, y: 10))
        p.closeSubpath()
        return p
    }
}

/// Physics feel. Everything here is a candidate for play-testing adjustment.
enum Tuning {
    static let gravity: CGFloat = -7.3        // TUNE: effective table pitch
    static let flipOmega: CGFloat = 34        // rad/s power stroke
    static let returnOmega: CGFloat = 16      // rad/s spring return
    static let flipperHoldOmega: CGFloat = 0.8 // gentle press against the stop
    static let flipperHoldBand: CGFloat = 0.03 // rad from stop = "at the stop"
    static let ballMass: CGFloat = 0.08       // 80 g steel ball
    static let ballRestitution: CGFloat = 0.3
    static let ballFriction: CGFloat = 0.06   // slick playfield
    static let ballLinearDamping: CGFloat = 0.07
    static let ballAngularDamping: CGFloat = 0.06
    static let maxBallSpeed: CGFloat = 2400   // anti-tunneling safety
    static let launchMin: CGFloat = 40        // plunger impulse range
    static let launchMax: CGFloat = 128   // full plunge crests into the NOVA lanes
    static let chargeRate: CGFloat = 1.1      // full pull per second
    static let bumperKick: CGFloat = 46       // impulse per bumper hit
    static let slingKick: CGFloat = 32        // impulse per slingshot fire
    static let kickerCooldown: TimeInterval = 0.07
    static let saucerEject = CGVector(dx: -330, dy: -130)   // kick toward midfield
    static let wormholeEject = CGVector(dx: 90, dy: 0)       // left hole: gentle roll into the left inlane
    static let wormholeCenterEject = CGVector(dx: 260, dy: 380) // centre hole: up into the bumpers (x sign random)
    static let wormholeWarpChance = 0.4
    static let wormholeCooldown: TimeInterval = 2.5          // hole closed after ejecting (no instant recapture)
    static let wormholeMaxSpeed: CGFloat = 550              // faster balls skip over
    static let extraBallsPerGame = 2      // cap on extra balls earned per game
    static let lostBallQuipChance = 0.10  // voice quip ("Oh no!", "Gravity wins." …) on a lost ball
    /// Plunger curve: pull fraction → launch strength (0…1 of launchMin…Max).
    /// The upper part is stretched so lanes can be aimed: from
    /// `skillBandStart` pull the ball always crests into the arch, and the
    /// rest of the pull is split into four equal bands A, V, O, N (weak →
    /// strong). Below that, plunges are weak (saucer, rollback) as before.
    static let skillBandStart: CGFloat = 0.45
    static let skillCrestStrength: CGFloat = 0.875  // weakest launch that still crests the right top gate
    static func launchStrength(_ pull: CGFloat) -> CGFloat {
        if pull < skillBandStart { return pull / skillBandStart * 0.86 }
        return skillCrestStrength + (pull - skillBandStart) / (1 - skillBandStart) * (1 - skillCrestStrength)
    }
    /// The NOVA lane (0 = N … 3 = A) a pull is aimed at, nil below the bands.
    static func skillBandLane(_ pull: CGFloat) -> Int? {
        guard pull >= skillBandStart else { return nil }
        let band = Int((pull - skillBandStart) / ((1 - skillBandStart) / 4))
        return 3 - min(3, band)
    }
    static let skillWindow: TimeInterval = 4.0   // after launch, resolve or expire
    static let comboWindow: TimeInterval = 5.0   // next major shot within this keeps the chain
    static let modeDuration: TimeInterval = 30
    static let ballSaveWindow: TimeInterval = 8
    static let maxBalls = 3
    /// After game over, Space / Return only start a new game after this
    /// long, so a stray press can't skip the game-over moment (R always works).
    static let startLockout: TimeInterval = 1.0
    /// Outlane guards: up at every new ball, down this long after the launch
    /// (spelling NOVA raises them again for as long); they blink for the
    /// last `guardWarning` seconds. A tilt drops them at once.
    static let guardTime: TimeInterval = 30
    static let guardWarning: TimeInterval = 3
    /// A raised guard fires a touching ball up and toward the inlane (left
    /// guard; x mirrored on the right) — a velocity, so every save is alike.
    static let guardKick = CGVector(dx: 76, dy: 300)
}

enum Score {
    static let bumper = 100
    static let sling = 10
    static let dropTarget = 500
    static let dropBank = 5000
    static let standup = 300
    static let standupRepeat = 50
    static let standupSet = 3000
    static let rollover = 500
    static let novaComplete = 5000
    static let spinnerSpin = 100
    static let ramp = 1000
    static let saucer = 1500
    static let wormhole = 2500
    static let wormholeWarp = 2500   // extra, when the ball warps to the other hole
    static let lock = 5000
    static let jackpot = 25000
    static let skillShot = 10000        // first lane = the lit insert (full plunge → N)
    static let superSkillShot = 25000   // …via O/V/A: needs a precise partial plunge
    static let combo = 5000             // × (chain length − 1): 5k, 10k, 15k, …

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // Latin digits, whatever the region
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.secondaryGroupingSize = 3                     // not the Indian 1,23,45,678
        return f
    }()

    /// 12345 → "12,345" (the table's display style, independent of locale).
    static func format(_ n: Int) -> String {
        formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

enum Cat {
    static let ball: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let flipper: UInt32 = 1 << 2
    static let plunger: UInt32 = 1 << 3
    static let drain: UInt32 = 1 << 4
    static let bumper: UInt32 = 1 << 5
    static let sling: UInt32 = 1 << 6
    static let dropTarget: UInt32 = 1 << 7
    static let standup: UInt32 = 1 << 8
    static let rampWall: UInt32 = 1 << 9
    static let rollover: UInt32 = 1 << 11
    static let spinner: UInt32 = 1 << 12
    static let saucer: UInt32 = 1 << 13
    static let wormhole: UInt32 = 1 << 14
    static let guardPost: UInt32 = 1 << 15

    static let allKickers = bumper | sling | dropTarget | standup | guardPost
    static let allSensors = rollover | spinner | saucer | wormhole
}
