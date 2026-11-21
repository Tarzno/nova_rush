import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private lazy var helpWindowController = HelpWindowController()
    private var scene: GameScene?
    private lazy var licenseWindowController = LicenseWindowController()

    @objc func showLicense(_ sender: Any?) {
        licenseWindowController.showWindow(nil)
        licenseWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private lazy var aboutWindowController = AboutWindowController()

    @objc func showAbout(_ sender: Any?) {
        aboutWindowController.showWindow(nil)
        aboutWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Deliberately NOT named showHelp: — NSApplication has its own
    // showHelp: (the Help Book opener), which sits earlier in the nil-
    // target action chain and would swallow the menu click.
    @objc func showRules(_ sender: Any?) {
        helpWindowController.show(playfield: scene?.playfieldImage(margin: HelpManual.mapMargin))
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 1000)
        let height = min(960, visible.height - 30)
        let width = height * (L.sceneSize.width / L.sceneSize.height)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Nova Rush"
        window.contentAspectRatio = NSSize(width: L.sceneSize.width, height: L.sceneSize.height)

        let view = SKView(frame: window.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = true
        if CommandLine.arguments.contains("--debug") {
            view.showsFPS = true
            view.showsPhysics = true
            view.showsNodeCount = true
        }
        window.contentView = view

        let scene = GameScene(size: L.sceneSize)
        self.scene = scene
        scene.scaleMode = .aspectFit
        // A real launch opens on the attract show; verification runs
        // (--snapshot) start straight into a game unless --attract is given.
        let args = CommandLine.arguments
        scene.startInAttract = !args.contains("--snapshot") || args.contains("--attract")
        // --attracttest: the spoken invitation early (set before the show starts).
        if args.contains("--attracttest") { scene.attractVoiceTiming = (first: 1.5, every: 100) }
        view.presentScene(scene)

        // Deliver keyboard input at the application level, bypassing the
        // responder chain: modifier-only events (shift/ctrl flippers) are
        // otherwise lost when focus drifts off the scene. The scene's input
        // handling is stateless/idempotent, so double delivery via the
        // normal responder path is harmless.
        // Only the game window's keys belong to the game: Help, About and
        // License keep theirs (Space / arrows scroll the manual, and must not
        // fire the plunger behind it).
        let gameWindow = window!
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            if event.window === gameWindow { scene.flagsChanged(with: event) }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.window === gameWindow else { return event }
            if event.modifierFlags.contains(.command) { return event }  // menu shortcuts
            if !event.isARepeat { scene.keyDown(with: event) }
            return nil    // fully handled; stops the system "funk" beep
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { event in
            guard event.window === gameWindow else { return event }
            scene.keyUp(with: event)
            return nil
        }
        // A key released while another app or window has focus never reaches
        // the game — let go of everything held when the game loses focus.
        let release: (Notification) -> Void = { _ in scene.releaseHeldInputs() }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main, using: release)
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                               object: gameWindow, queue: .main, using: release)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(scene)
        // --showlicense: open the License window at launch (verification).
        if CommandLine.arguments.contains("--showlicense") { showLicense(nil) }
        // --showabout: open the About window at launch (verification).
        if CommandLine.arguments.contains("--showabout") { showAbout(nil) }
        // --showhelp: open the Help window shortly after launch (verification).
        if CommandLine.arguments.contains("--showhelp") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.showRules(nil)
                // --helppdf <path>: also save the whole manual as a PDF.
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "--helppdf"), args.count > i + 1 {
                    try? self.helpWindowController.pdfData().write(to: URL(fileURLWithPath: args[i + 1]))
                }
            }
        }

        // Headless-ish verification: render the scene to a PNG and exit.
        // --selftest additionally auto-fires a full-strength plunge first.
        if args.contains(where: { ["--selftest", "--drop", "--cradle"].contains($0) }) {
            scene.freePlay = true
        }
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            let path = args[i + 1]
            let selftest = args.contains("--selftest")
            if selftest {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scene.simulateLaunch()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    scene.simulateFlip()
                }
            }
            // --cradle: trap a ball on the raised left flipper, verify it
            // settles, then release + re-flip and report the shot height.
            if args.contains("--cradle") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scene.setFlippersForTest(left: true, right: false)
                    scene.dropBallForTest(at: CGPoint(x: 185, y: 170))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    let p = scene.ballPositionForTest
                    print("cradle: ball speed \(Int(scene.ballSpeedForTest)) pt/s "
                          + "at (\(Int(p.x)), \(Int(p.y))) — want ~0 on the bat")
                    scene.setFlippersForTest(left: false, right: false)
                }
                // Flip delay after release: how long the ball rolls toward
                // the tip before the shot (player timing). Override with
                // --fliplag <seconds>.
                var lag = 0.8
                if let f = args.firstIndex(of: "--fliplag"), args.count > f + 1,
                   let s = Double(args[f + 1]) {
                    lag = s
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + lag) {
                    scene.trackMaxY = true
                    scene.setFlippersForTest(left: true, right: false)
                }
            }

            // --drop <x> <y> [vx vy]: release a ball at a point (optionally
            // moving) and report where it settles (geometry stuck-spot and
            // kicker checks).
            var dropping = false
            if let d = args.firstIndex(of: "--drop"), args.count > d + 2,
               let x = Double(args[d + 1]), let y = Double(args[d + 2]) {
                dropping = true
                var vel = CGVector.zero
                if args.count > d + 4,
                   let vx = Double(args[d + 3]), let vy = Double(args[d + 4]) {
                    vel = CGVector(dx: vx, dy: vy)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scene.dropBallForTest(at: CGPoint(x: x, y: y), velocity: vel)
                }
            }
            // --pausetest: drop a falling ball, pause mid-fall, verify it
            // stays frozen, resume, verify it moves again.
            let pauseTest = args.contains("--pausetest")
            if pauseTest {
                var p1 = CGPoint.zero
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scene.dropBallForTest(at: CGPoint(x: 160, y: 650))   // clear of the centre wormhole
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    scene.togglePauseForTest()
                    p1 = scene.ballPositionForTest
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                    let p2 = scene.ballPositionForTest
                    print("pause: \(scene.gameStateForTest)")
                    print("pause: ball moved \(Int(hypot(p2.x - p1.x, p2.y - p1.y)))pt in 1.5s "
                          + "while paused (want 0)")
                    scene.togglePauseForTest()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    let p3 = scene.ballPositionForTest
                    print("pause: ball moved \(Int(hypot(p3.x - p1.x, p3.y - p1.y)))pt in 0.3s "
                          + "after resume (want > 0)")
                }
            }
            // --continuoustest: in a real (non-free-play) game, drain 4 balls
            // in continuous mode (want ball 1, no game over), then switch back
            // and drain 3 more (want game over).
            let continuousTest = args.contains("--continuoustest")
            if continuousTest {
                let drain = { scene.dropBallForTest(at: CGPoint(x: 215, y: 6),
                                                    velocity: CGVector(dx: 0, dy: -300)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scene.toggleContinuousForTest()
                }
                for t in [1.0, 4.0, 7.0, 10.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: drain)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 12.5) {
                    print("continuous (4 drains): \(scene.gameStateForTest)")
                    scene.toggleContinuousForTest()
                    print("normal again: \(scene.gameStateForTest)")
                }
                for t in [13.0, 16.0, 19.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: drain)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 21.5) {
                    print("normal (3 more drains): \(scene.gameStateForTest)")
                    print("quips spoken on lost balls: \(scene.quipsForTest)")
                }
            }
            // --starttest (with --attract): the launch show is running with
            // no ball; pressing start begins ball 1 and says "welcome".
            // --startat <s> presses later, e.g. while a teaser lights the
            // table (the snapshot then shows whether the lamps came back).
            if args.contains("--starttest") {
                var at = 1.5
                if let k = args.firstIndex(of: "--startat"), args.count > k + 1,
                   let s = Double(args[k + 1]) { at = s }
                DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                    print("start: before: \(scene.gameStateForTest)")
                    print("start: before: \(scene.attractStateForTest)")
                    print("start: press start → \(scene.pressStartForTest() ? "game started" : "ignored")")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + at + 2.0) {
                    let p = scene.ballPositionForTest
                    print("start: after: \(scene.gameStateForTest), ball at (\(Int(p.x)), \(Int(p.y)))")
                    print("start: after: \(scene.attractStateForTest), "
                          + "voice \(scene.lastVoiceForTest ?? "none")")
                }
            }
            // --attracttest (with --attract): flipper buttons page the show
            // (right = next, left = back, wrapping), a hand-turned page keeps
            // its full time, and the spoken invitation comes early (1.5 s).
            // Needs --wait ≈ 6.
            if args.contains("--attracttest") {
                let presses: [(Double, String, Bool)] = [
                    (1.2, "right", true), (1.6, "right", true), (2.0, "left", false),
                    (2.2, "left", false), (2.4, "left", false), (2.6, "right", true),
                ]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("attract: page \"\(scene.attractSlideForTest)\"")
                }
                for (t, side, right) in presses {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        scene.setFlippersForTest(left: !right, right: right)
                        scene.setFlippersForTest(left: false, right: false)
                        print("attract: \(side) flipper → page \"\(scene.attractSlideForTest)\"")
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.4) {
                    print("attract: 2.8 s after the last press → page \"\(scene.attractSlideForTest)\" "
                          + "(want unchanged)")
                    print("attract: voice \(scene.lastVoiceForTest ?? "none") (want attract; app active \(NSApp.isActive)), "
                          + "\(scene.gameStateForTest)")
                }
            }
            // --keytest: letter commands by the letter on the key, nudge keys by
            // position, held keys released when Help takes focus, and keys in
            // the Help window not reaching the game. Needs --wait ≈ 4.
            if args.contains("--keytest") {
                let key = { (code: UInt16, chars: String, type: NSEvent.EventType, win: NSWindow) in
                    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: win.windowNumber, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars,
                                     isARepeat: false, keyCode: code)!
                }
                let game = window!
                let steps: [(Double, String, () -> Void)] = [
                    (0.5, "nudge key labels \(KeyLabels.nudge)", {}),
                    (0.6, "\"m\" on the AZERTY M position (41) → music toggles", {
                        let before = scene.musicMutedForTest
                        scene.keyDown(with: key(41, "m", .keyDown, game))
                        print("key: music \(before) → \(scene.musicMutedForTest) (want changed)")
                        scene.keyDown(with: key(41, "m", .keyDown, game)) }),
                    (0.8, "\",\" on the US M position (46) → no toggle", {
                        let before = scene.musicMutedForTest
                        scene.keyDown(with: key(46, ",", .keyDown, game))
                        print("key: music \(before) → \(scene.musicMutedForTest) (want unchanged)") }),
                    (1.0, "German Y (6) → nudge from the left", {
                        scene.keyDown(with: key(6, "y", .keyDown, game)) }),
                    (1.2, "hold → (right flipper)", {
                        scene.keyDown(with: key(124, "\u{F703}", .keyDown, game)) }),
                    (1.5, "open Help (game window resigns key)", { self.showRules(nil) }),
                    (1.9, "want flippers released", {}),
                    (2.0, "Space into the Help window", {
                        let help = NSApp.keyWindow ?? game
                        print("key: key window is \(help === game ? "GAME (bad)" : "Help")")
                        NSApp.postEvent(key(49, " ", .keyDown, help), atStart: false) }),
                    (2.3, "want plunger false", {}),
                    (2.4, "Space key-up into Help", {
                        NSApp.postEvent(key(49, " ", .keyUp, NSApp.keyWindow ?? game), atStart: false) }),
                    (2.8, "back to the game window", { game.makeKeyAndOrderFront(nil) }),
                    (3.0, "Space into the game window", {
                        NSApp.postEvent(key(49, " ", .keyDown, game), atStart: false) }),
                    (3.3, "want plunger true", {}),
                    (3.4, "Space key-up → launch", {
                        NSApp.postEvent(key(49, " ", .keyUp, game), atStart: false) }),
                    (3.9, "want the ball launched (y > 64)", {}),
                ]
                for (t, label, action) in steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        action()
                        let p = scene.ballPositionForTest
                        print("key: \(label): \(scene.inputStateForTest), ball (\(Int(p.x)), \(Int(p.y)))")
                    }
                }
            }
            // --fixtest: code-review fixes in a real game — R right after a
            // drain and R during a wormhole hold (no stray balls, ball 1),
            // nudges between balls (ignored: no tilt carried over), R during
            // multiball with a combo running (lights off, combo 0), practice
            // switched on mid-ball (skill shot off). Needs --wait ≈ 10.5.
            if args.contains("--fixtest") {
                scene.lostBallQuipChance = 0
                let drain = { scene.dropBallForTest(at: CGPoint(x: 215, y: 6),
                                                    velocity: CGVector(dx: 0, dy: -300)) }
                let steps: [(Double, String, () -> Void)] = [
                    (0.5, "A: drain ball 1", drain),
                    (1.0, "A: R within the 1.2 s gap", { scene.restartForTest() }),
                    (2.5, "A: want ball 1, balls 1", {}),
                    (3.0, "B: into the left wormhole", { scene.dropBallForTest(at: CGPoint(x: 22, y: 430)) }),
                    (3.4, "B: held? (want balls 0, pending 1)", {}),
                    (3.5, "B: R while it is held", { scene.restartForTest() }),
                    (5.0, "B: want balls 1, pending 0, wormholes free", {}),
                    (5.5, "C: drain", drain),
                    (5.8, "C: nudge ×3 between balls", {
                        scene.nudgeForTest(); scene.nudgeForTest(); scene.nudgeForTest() }),
                    (7.2, "C: want ball 2, tilted false", {}),
                    (7.5, "D: multiball + a combo shot", {
                        scene.startMultiballForTest(); scene.majorShotForTest() }),
                    (7.7, "D: want mb lights true, combo 1", {}),
                    (7.8, "D: R", { scene.restartForTest() }),
                    (9.6, "D: want balls 1, mb lights false, combo 0", {}),
                    (9.8, "E: want skill shot armed", {}),
                    (9.9, "E: continuous play on", { scene.toggleContinuousForTest() }),
                    (10.0, "E: want skill off", { scene.toggleContinuousForTest() }),
                ]
                for (t, label, action) in steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        action()
                        print("fix: \(label): \(scene.gameStateForTest.replacingOccurrences(of: ", paused false", with: ""))")
                        print("fix:   \(scene.fixStateForTest)")
                    }
                }
            }
            // --lamptest: LOCK LIT on, then 100 points every 0.1 s for 3 s —
            // the saucer lamp must keep blinking (alpha swinging 0.35 … 1),
            // not sit dim. Needs --wait ≈ 4.
            if args.contains("--lamptest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { scene.lightLockForTest() }
                for k in 0..<30 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(k) * 0.1) {
                        scene.awardForTest(100)
                    }
                }
                var lo: CGFloat = 1, hi: CGFloat = 0
                for k in 0..<40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6 + Double(k) * 0.05) {
                        lo = min(lo, scene.saucerAlphaForTest)
                        hi = max(hi, scene.saucerAlphaForTest)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) {
                    print("lamp: saucer alpha during rapid scoring \(Int(lo * 100))…\(Int(hi * 100)) % "
                          + "(want ≈35…100)")
                }
            }
            // --audiotest: an output-device change stops the engine; the bank
            // must restart it and keep playing. Needs --wait ≈ 1.5.
            if args.contains("--audiotest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("audio: running \(scene.audioRunningForTest) — simulating an output change")
                    scene.simulateAudioOutputChangeForTest()
                    print("audio: right after: running \(scene.audioRunningForTest) (stopped)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    scene.playForTest("flipper")
                    print("audio: 0.5 s later: running \(scene.audioRunningForTest) (want true), "
                          + "voice \(scene.sayForTest("welcome") ? "ok" : "DROPPED")")
                }
            }
            // --tiltat <s>: tilt the table at that time (e.g. with a ramp drop:
            // the ramp must then score nothing).
            if let k = args.firstIndex(of: "--tiltat"), args.count > k + 1, let s = Double(args[k + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + s) { scene.tiltForTest() }
            }
            // --gameovertest: drain all 3 balls of a real game, then check the
            // game-over page, the start lockout, the attract show starting,
            // and a new game from it. Needs --wait ≈ 16.
            if args.contains("--gameovertest") {
                scene.lostBallQuipChance = 0
                let drain = { scene.dropBallForTest(at: CGPoint(x: 215, y: 6),
                                                    velocity: CGVector(dx: 0, dy: -300)) }
                for t in [0.5, 3.0, 5.5] {          // game over ≈ 6.7 s
                    DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: drain)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                    print("gameover: \(scene.gameStateForTest)")
                    print("gameover: \(scene.attractStateForTest)")
                    print("gameover: start within lockout → "
                          + (scene.pressStartForTest() ? "STARTED (want ignored)" : "ignored"))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    print("gameover: after lockout: \(scene.attractStateForTest)")
                }
                for t in [11.0, 14.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        print("gameover: show: \(scene.attractStateForTest)")
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 14.2) {
                    print("gameover: press start → \(scene.pressStartForTest() ? "game started" : "ignored")")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.6) {
                    print("gameover: new game: \(scene.gameStateForTest), "
                          + "voice \(scene.lastVoiceForTest ?? "none")")
                    print("gameover: new game: \(scene.attractStateForTest)")
                }
            }
            // --voicetest: speak every callout in turn (audition + check
            // that each one is bundled and plays). Needs --wait ≈ 30.
            if args.contains("--voicetest") {
                let lines = ["welcome", "multiball", "jackpot", "warp", "ballsaved", "tilt",
                             "asteroid", "solarflare", "gravitywell", "modelit", "locklit",
                             "locked", "nova", "gameover", "highscore", "eblit", "extraball", "shootagain", "skillshot", "superskill", "combo", "supercombo", "balllost", "attract"]
                // Playback-speed check on the longest line: player clock vs wall clock.
                var c0: Double?
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { c0 = scene.voiceClockForTest }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    if let a = c0, let b = scene.voiceClockForTest {
                        print(String(format: "voice: playback speed %.2f× (want 1.00)", (b - a) / 0.5))
                    }
                }
                for (k, name) in lines.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(k) * 1.7) {
                        let takes = scene.voiceTakesForTest[name] ?? 0
                        print("voice: \(name) \(scene.sayForTest(name) ? "ok" : "MISSING") (\(takes) takes)")
                    }
                }
            }
            // --ebtest: Extra Ball in a real game — left wormhole, centre
            // wormhole (lights it), saucer (collects), drain (shoot again:
            // same ball number), drain again (ball 2). Needs --wait ≈ 12.
            if args.contains("--ebtest") {
                scene.wormholeWarpChance = 0
                let steps: [(Double, String, CGPoint?)] = [
                    // Each hole holds the ball 1 s, then ejects it; the test
                    // re-grabs the ejected ball before it can drain.
                    (0.5, "drop left wormhole", CGPoint(x: 22, y: 430)),
                    (2.3, "drop centre wormhole", CGPoint(x: 215, y: 657)),
                    (3.9, "before saucer (want lit true)", nil),
                    (4.0, "drop saucer", CGPoint(x: 368, y: 660)),
                    (5.5, "after saucer (want lit false, banked 1)", nil),
                    (5.7, "drop drain", CGPoint(x: 215, y: 60)),
                    (8.6, "after 1st drain (want ball 1, banked 0)", nil),
                    (8.8, "drop drain", CGPoint(x: 215, y: 60)),
                    (11.8, "after 2nd drain (want ball 2)", nil),
                ]
                for (t, label, p) in steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        if let p { scene.dropBallForTest(at: p) }
                        print("eb: \(label): \(scene.extraBallStateForTest)")
                    }
                }
            }
            // --combotest: ramp shot, then orbit, then ramp again — each fired
            // as soon as the previous ball is back in reach (the test re-grabs
            // it). Expect combos 2, best 3. Needs --wait ≈ 10.
            if args.contains("--combotest") {
                let shots: [(Double, CGPoint, CGVector, String)] = [
                    (0.5, CGPoint(x: 305, y: 400), CGVector(dx: 20, dy: 1200), "ramp"),
                    (3.3, CGPoint(x: 20, y: 350), CGVector(dx: 0, dy: 1200), "orbit"),
                    (6.0, CGPoint(x: 305, y: 400), CGVector(dx: 20, dy: 1200), "ramp"),
                ]
                for (t, p, v, name) in shots {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        print("combo: shoot \(name) (chain so far \(scene.comboCountForTest))")
                        scene.dropBallForTest(at: p, velocity: v)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
                    let cs = scene.comboStatsForTest
                    print("combo: orbits \(cs.orbits), combos \(cs.combos), best \(cs.best), "
                          + "ramps \(scene.rampStatsForTest.completed), score \(scene.scoreForTest)")
                }
            }
            // --plunge <charge 0…1>: plunge the waiting ball at that strength
            // and report the first NOVA lane it rolls through (skill shot map).
            if let k = args.firstIndex(of: "--plunge"), args.count > k + 1,
               let c = Double(args[k + 1]) {
                // --when <lane 0…3>: force the skill-shot target to that
                // lane (N=0 … A=3) before launching.
                var when: Int?
                if let w = args.firstIndex(of: "--when"), args.count > w + 1 { when = Int(args[w + 1]) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if let when { scene.forceSkillLaneForTest(when) }
                    scene.launchForTest(charge: CGFloat(c))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                    let lane = scene.firstLaneForTest.map { L.novaLetters[$0] } ?? "none"
                    print("plunge \(c): first lane \(lane), skill shots \(scene.skillShotsForTest), orbits \(scene.comboStatsForTest.orbits), "
                          + "score \(scene.scoreForTest)")
                }
            }
            // --bannertest: the typical end-of-ball burst (MODE OVER + BONUS
            // at once, SHOOT AGAIN 1.2 s later, a duplicate). Expect at most 1
            // banner on screen at any time, all three shown in order.
            if args.contains("--bannertest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scene.bannerForTest("MODE OVER", color: .cyan)
                    scene.bannerForTest("BONUS 12,500")
                    scene.bannerForTest("BONUS 12,500")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                    scene.bannerForTest("SHOOT AGAIN")
                }
                var seen: [String] = []
                for k in 0..<100 {      // sample every 50 ms for 5 s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(k) * 0.05) {
                        for t in scene.bannerTextsForTest where seen.last != t { seen.append(t) }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) {
                    print("banner: shown in order \(seen), max on screen at once "
                          + "\(scene.maxBannersOnScreenForTest) (want 1)")
                }
            }
            // --slinglit: hold the sling plastics' lights on (snapshot aid).
            if args.contains("--slinglit") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scene.slingLitForTest() }
            }
            // README pictures (Tools/readme_images.swift): --nohint hides the
            // on-table key hint (its nudge keys depend on the keyboard layout);
            // --multiball <s> starts multiball as a saucer shot would at <s>;
            // --helpmap <png> also saves the Help window's numbered table map.
            if args.contains("--nohint") { scene.hideHintForTest() }
            if let k = args.firstIndex(of: "--multiball"), args.count > k + 1, let s = Double(args[k + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + s) { scene.multiballFromSaucerForTest() }
            }
            // --sfxtest: play the generated effects (Resources/SFX), each
            // twice, for auditioning. Needs --wait ≈ 20.
            if args.contains("--sfxtest") {
                let fx = ["flipper", "bumper", "eject", "launch", "drain", "wormhole", "warp", "ramp"]
                for (k, name) in fx.enumerated() {
                    for r in 0..<2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(k) * 2.4 + Double(r) * 0.8) {
                            if r == 0 { print("sfx: \(name)") }
                            scene.playForTest(name)
                        }
                    }
                }
            }
            // --quip <chance>: override the lost-ball quip chance (0…1).
            if let q = args.firstIndex(of: "--quip"), args.count > q + 1,
               let c = Double(args[q + 1]) {
                scene.lostBallQuipChance = c
            }
            // --guards <0|1>: force the outlane guards down / up (timer off).
            if let g = args.firstIndex(of: "--guards"), args.count > g + 1 {
                scene.setGuardsForTest(up: args[g + 1] != "0")
            }
            // --guardtest: a real ball with guardTime 6 s — launch, cradle the
            // ball, watch the warning and the drop, NOVA raises them again,
            // a tilt drops them, the next ball brings them back. --wait ≈ 11.
            if args.contains("--guardtest") {
                scene.guardTime = 6
                let steps: [(Double, String, () -> Void)] = [
                    (0.5, "launch (weak pull)", { scene.launchForTest(charge: 0.3) }),
                    (0.8, "cradle on the left flipper", {
                        scene.setFlippersForTest(left: true, right: false)
                        scene.dropBallForTest(at: CGPoint(x: 185, y: 170)) }),
                    (2.0, "want up, ≈4.5 s left, no warning", {}),
                    (4.2, "want warning true", {}),
                    (7.0, "want down (OUTLANES OPEN)", {}),
                    (7.2, "spell NOVA", { scene.completeNovaForTest() }),
                    (7.4, "want up again, ≈5.8 s left", {}),
                    (8.0, "tilt", { scene.tiltForTest() }),
                    (8.2, "want down, no timer", {}),
                    (8.4, "drain", {
                        scene.setFlippersForTest(left: false, right: false)
                        scene.dropBallForTest(at: CGPoint(x: 215, y: 6), velocity: CGVector(dx: 0, dy: -300)) }),
                    (10.4, "next ball: want up, no timer", {}),
                ]
                var banners: [String] = []
                for k in 0..<200 {      // collect banner texts every 50 ms
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.05) {
                        for t in scene.bannerTextsForTest where banners.last != t { banners.append(t) }
                    }
                }
                for (t, label, action) in steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        action()
                        print("guard: \(label): \(scene.guardStateForTest), ball \(scene.gameStateForTest)")
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
                    print("guard: banners \(banners)")
                }
            }
            // --warp <chance>: override the wormhole warp chance (0…1).
            if let w = args.firstIndex(of: "--warp"), args.count > w + 1,
               let c = Double(args[w + 1]) {
                scene.wormholeWarpChance = c
            }
            var wait = (selftest || dropping) ? 3.0 : (pauseTest ? 3.0 : (continuousTest ? 22.0 : 1.5))
            if let w = args.firstIndex(of: "--wait"), args.count > w + 1,
               let s = Double(args[w + 1]) {
                wait = s
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                if dropping {
                    let p = scene.ballPositionForTest
                    print("ball settled at (\(Int(p.x)), \(Int(p.y))), score \(scene.scoreForTest)")
                    print("wormhole: captures \(scene.wormholeStatsForTest.captures), "
                          + "warps \(scene.wormholeStatsForTest.warps)")
                    print("ramp: entered \(scene.rampStatsForTest.entered), "
                          + "completed \(scene.rampStatsForTest.completed)")
                    let cs = scene.comboStatsForTest
                    print("combo: orbits \(cs.orbits), combos \(cs.combos), best \(cs.best)")
                    let os = scene.outlaneStatsForTest
                    print("outlane: entries \(os.entries), saves \(os.saves), passes from below \(os.passesFromBelow), "
                          + scene.guardStateForTest)
                    print("below ball: \(scene.bodiesBelowBallForTest())")
                }
                if args.contains("--cradle") {
                    print("cradle shot: max height \(Int(scene.trackedMaxY)) "
                          + "of \(Int(L.H)) — want ≥ 700 (bumper nest)")
                }
                if selftest {
                    let p = scene.ballPositionForTest
                    let a = scene.flipperAnglesForTest
                    print("ball at (\(Int(p.x)), \(Int(p.y)))")
                    print("flippers raised: left \(Int(a.left))°, right \(Int(a.right))° "
                          + "(expect ≈ +22 / −22)")
                }
                if let tex = view.texture(from: scene) {
                    let rep = NSBitmapImageRep(cgImage: tex.cgImage())
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path))
                }
                if let k = args.firstIndex(of: "--helpmap"), args.count > k + 1,
                   let playfield = scene.playfieldImage(margin: HelpManual.mapMargin) {
                    let map = HelpManual.mapImage(playfield: playfield, width: 400)
                    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800,
                                               pixelsHigh: Int((map.size.height * 2).rounded()),
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0)!
                    rep.size = map.size
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    map.draw(in: NSRect(origin: .zero, size: map.size))
                    NSGraphicsContext.restoreGraphicsState()
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: args[k + 1]))
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// --license: print the built-in license text (build-app.sh diffs it
// against the LICENSE file) and exit before any window opens.
if CommandLine.arguments.contains("--license") {
    print(License.text)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "About Nova Rush",
                           action: #selector(AppDelegate.showAbout(_:)),
                           keyEquivalent: ""))
appMenu.addItem(NSMenuItem(title: "License",
                           action: #selector(AppDelegate.showLicense(_:)),
                           keyEquivalent: ""))
appMenu.addItem(.separator())
appMenu.addItem(NSMenuItem(title: "Quit Nova Rush",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
appMenuItem.submenu = appMenu

let helpMenuItem = NSMenuItem()
mainMenu.addItem(helpMenuItem)
let helpMenu = NSMenu(title: "Help")
helpMenu.addItem(NSMenuItem(title: "Nova Rush Help",
                            action: #selector(AppDelegate.showRules(_:)),
                            keyEquivalent: "?"))
helpMenuItem.submenu = helpMenu
app.helpMenu = helpMenu
app.mainMenu = mainMenu

app.run()
