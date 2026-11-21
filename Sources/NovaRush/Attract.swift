import AppKit

/// One page of the attract show: the display panel cycles through these
/// while no game is running (at launch and after game over), like a real
/// machine inviting players. Rule teasers light the part of the table they
/// talk about (`highlight`, driven by GameScene).
struct AttractSlide {
    enum Tint { case amber, cyan, magenta, white }
    enum Highlight { case skillShot, guards, combos, extraBall, multiball, modes, nova }

    let title: String              // big, in the tint colour; may span lines
    var body: String = ""          // smaller white lines, "\n"-separated
    var tint: Tint = .amber        // title and panel frame
    var duration: TimeInterval = 3.8
    var highlight: Highlight?
    var flourish = false           // opening lamp show of a cycle

    /// Title large in `titleColor`, body below in white, all centred.
    /// Lines are kept ≤ 20 characters so they fit the panel.
    func attributedText(titleColor: NSColor) -> NSAttributedString {
        let titleFont = NSFont(name: "Menlo-Bold", size: 22) ?? .boldSystemFont(ofSize: 22)
        let bodyFont = NSFont(name: "Menlo-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
        let plain = NSMutableParagraphStyle()
        plain.alignment = .center
        let spaced = plain.mutableCopy() as! NSMutableParagraphStyle
        spaced.paragraphSpacing = 7     // gap between title and body

        let out = NSMutableAttributedString()
        let titleLines = title.components(separatedBy: "\n")
        let bodyLines = body.isEmpty ? [] : body.components(separatedBy: "\n")
        for (i, line) in titleLines.enumerated() {
            let last = i == titleLines.count - 1
            out.append(NSAttributedString(
                string: line + (last && bodyLines.isEmpty ? "" : "\n"),
                attributes: [.font: titleFont, .foregroundColor: titleColor,
                             .paragraphStyle: last && !bodyLines.isEmpty ? spaced : plain]))
        }
        for (i, line) in bodyLines.enumerated() {
            out.append(NSAttributedString(
                string: line + (i == bodyLines.count - 1 ? "" : "\n"),
                attributes: [.font: bodyFont, .foregroundColor: NSColor(calibratedWhite: 0.93, alpha: 1),
                             .paragraphStyle: plain]))
        }
        return out
    }
}

/// What the attract show says. Values come from `Score` so the teasers stay
/// in step with the rules (Help.swift has its own hand-written copy).
enum AttractShow {
    /// Rule teasers, two per cycle, rotating.
    static let teasers: [AttractSlide] = [
        AttractSlide(title: "SKILL SHOT",
                     body: "AIM THE PLUNGER AT\nTHE FLASHING LETTER\nUP TO \(Score.format(Score.superSkillShot))",
                     tint: .white, highlight: .skillShot),
        AttractSlide(title: "OUTLANE GUARDS",
                     body: "UP FOR THE FIRST\n\(Int(Tuning.guardTime)) SECONDS OF A BALL\nSPELL NOVA: UP AGAIN",
                     tint: .cyan, highlight: .guards),
        AttractSlide(title: "COMBOS",
                     body: "RAMP \u{2192} ORBIT \u{2192} RAMP\nCHAIN THEM FAST",
                     tint: .white, highlight: .combos),
        AttractSlide(title: "EXTRA BALL",
                     body: "SINK THE BALL IN\nBOTH WORMHOLES,\nTHEN HIT THE SAUCER",
                     tint: .amber, highlight: .extraBall),
        AttractSlide(title: "MULTIBALL",
                     body: "STANDUPS LIGHT LOCK\nLOCK 2 BALLS\nJACKPOT \(Score.format(Score.jackpot))",
                     tint: .magenta, highlight: .multiball),
        AttractSlide(title: "SPELL NOVA",
                     body: "ROLL ALL 4 TOP LANES\nBONUS UP TO \u{00D7}8",
                     tint: .cyan, highlight: .nova),
        AttractSlide(title: "COSMIC MODES",
                     body: "CLEAR THE DROPS,\nTHEN HIT THE SAUCER",
                     tint: .cyan, highlight: .modes),
    ]

    /// One cycle of the show: a motto (with the lamp-show flourish), the
    /// high scores, two rule teasers and — once a game has been played —
    /// that game's result. `step` rotates mottos and teasers between cycles.
    static func cycle(step: Int, highScores: [Int], lastScore: Int?) -> [AttractSlide] {
        var slides = [motto(step: step, best: highScores.first)]
        if !highScores.isEmpty { slides.append(highScoreTable(highScores)) }
        for k in 0..<2 { slides.append(teasers[(step * 2 + k) % teasers.count]) }
        if let lastScore { slides.append(gameOver(score: lastScore, best: highScores.first ?? lastScore)) }
        return slides
    }

    static func motto(step: Int, best: Int?) -> AttractSlide {
        var mottos = ["READY FOR\nLAUNCH?", "FEEL THE\nRUSH!"]
        if let best, best > 0 { mottos.append("CAN YOU BEAT\n\(Score.format(best))?") }
        return AttractSlide(title: mottos[step % mottos.count], tint: .amber,
                            duration: 3.0, flourish: true)
    }

    static func highScoreTable(_ scores: [Int]) -> AttractSlide {
        let texts = scores.prefix(5).map(Score.format)
        let width = texts.map(\.count).max() ?? 0
        let lines = texts.enumerated().map { "\($0.offset + 1).  " + pad($0.element, to: width) }
        return AttractSlide(title: "HIGH SCORES", body: lines.joined(separator: "\n"),
                            tint: .magenta, duration: 4.5)
    }

    static func gameOver(score: Int, best: Int) -> AttractSlide {
        let s = Score.format(score), b = Score.format(best)
        let width = max(s.count, b.count)
        return AttractSlide(title: "GAME OVER",
                            body: "SCORE  " + pad(s, to: width) + "\n BEST  " + pad(b, to: width),
                            tint: .amber, duration: 3.5)
    }

    /// Right-aligns numbers in the monospaced font.
    private static func pad(_ s: String, to width: Int) -> String {
        String(repeating: " ", count: max(0, width - s.count)) + s
    }
}
