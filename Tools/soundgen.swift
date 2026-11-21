// Regenerates the synthesized sound assets (the fallbacks for every effect;
// generated replacements in Resources/SFX win at runtime).
// Usage: swift Tools/soundgen.swift [output-dir]
// SOUNDGEN_ONLY=name,name writes just those files — the recipes use random
// noise, so a full run changes every existing sound slightly.
import Foundation

let sr = 44100
let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/NovaRush/Resources/Sounds"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let only = ProcessInfo.processInfo.environment["SOUNDGEN_ONLY"]?
    .split(separator: ",").map(String.init)

func writeWav(_ samples: [Float], _ name: String) {
    if let only, !only.contains(name) { return }
    let pcm: [Int16] = samples.map { Int16(max(-1.0, min(1.0, $0)) * 32000) }
    var data = Data()
    func ascii(_ s: String) { data.append(s.data(using: .ascii)!) }
    func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
    let byteCount = pcm.count * 2
    ascii("RIFF"); u32(UInt32(36 + byteCount)); ascii("WAVE")
    ascii("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
    ascii("data"); u32(UInt32(byteCount))
    pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    let path = outDir + "/" + name + ".wav"
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func seconds(_ d: Float) -> Range<Int> { 0..<Int(Float(sr) * d) }

// Flipper: mechanical clack — filtered noise snap plus a low solenoid thump.
var flipper = [Float]()
var lp: Float = 0
for i in seconds(0.10) {
    let t = Float(i) / Float(sr)
    let noise = Float.random(in: -1...1)
    lp += 0.4 * (noise - lp)
    let thump = sin(2 * Float.pi * 85 * t) * exp(-t / 0.03)
    let snap = lp * exp(-t / 0.012)
    flipper.append(0.9 * snap + 0.7 * thump)
}
writeWav(flipper, "flipper")

// Bumper: low "pop" (downward pitch sweep) plus a bright bell of partials.
var bumper = [Float]()
var phase: Float = 0
for i in seconds(0.4) {
    let t = Float(i) / Float(sr)
    let freq = 70 + 200 * exp(-t * 22)
    phase += 2 * Float.pi * freq / Float(sr)
    let pop = sin(phase) * exp(-t / 0.05)
    var bell: Float = 0
    for (f, a): (Float, Float) in [(1180, 0.5), (1740, 0.35), (2390, 0.25)] {
        bell += a * sin(2 * Float.pi * f * t) * exp(-t / 0.11)
    }
    bumper.append(0.85 * pop + 0.5 * bell)
}
writeWav(bumper, "bumper")

// Slingshot: sharp elastic kick — quick upward chirp with a noise transient.
var sling = [Float]()
phase = 0
for i in seconds(0.15) {
    let t = Float(i) / Float(sr)
    let freq = 180 + 900 * t
    phase += 2 * Float.pi * freq / Float(sr)
    let chirp = sin(phase) * exp(-t / 0.035)
    let snap = Float.random(in: -1...1) * exp(-t / 0.006)
    sling.append(0.8 * chirp + 0.5 * snap)
}
writeWav(sling, "slingshot")

// Drain: hollow falling thud.
var drain = [Float]()
phase = 0
for i in seconds(0.45) {
    let t = Float(i) / Float(sr)
    let freq = 50 + 130 * exp(-t * 9)
    phase += 2 * Float.pi * freq / Float(sr)
    let body = sin(phase) * exp(-t / 0.14)
    let knock = Float.random(in: -1...1) * exp(-t / 0.01)
    drain.append(0.8 * body + 0.3 * knock)
}
writeWav(drain, "drain")

// Target: bright zap ping for standup/drop target hits.
var target = [Float]()
for i in seconds(0.09) {
    let t = Float(i) / Float(sr)
    var s = sin(2 * Float.pi * 2400 * t) * exp(-t / 0.02)
    s += 0.5 * sin(2 * Float.pi * 3620 * t) * exp(-t / 0.012)
    s += 0.4 * Float.random(in: -1...1) * exp(-t / 0.004)
    target.append(0.7 * s)
}
writeWav(target, "target")

// Drop: mechanical target-drop thunk.
var dropSnd = [Float]()
phase = 0
for i in seconds(0.16) {
    let t = Float(i) / Float(sr)
    let freq = 90 + 160 * exp(-t * 30)
    phase += 2 * Float.pi * freq / Float(sr)
    let thunk = sin(phase) * exp(-t / 0.05)
    let rattle = Float.random(in: -1...1) * exp(-t / 0.015)
    dropSnd.append(0.85 * thunk + 0.35 * rattle)
}
writeWav(dropSnd, "drop")

// Launch: rising spring whoosh for the plunger.
var launch = [Float]()
phase = 0
var lpn: Float = 0
for i in seconds(0.28) {
    let t = Float(i) / Float(sr)
    let freq = 140 + 850 * t
    phase += 2 * Float.pi * freq / Float(sr)
    let sweep = sin(phase) * exp(-t / 0.1)
    let noise = Float.random(in: -1...1)
    lpn += 0.25 * (noise - lpn)
    launch.append(0.6 * sweep + 0.35 * lpn * min(t / 0.02, 1) * exp(-t / 0.12))
}
writeWav(launch, "launch")

// Game over: three slow descending notes.
var gameover = [Float]()
for (n, f) in [392.0, 329.6, 261.6].enumerated() {
    let dur: Float = n == 2 ? 0.42 : 0.2
    for i in seconds(dur) {
        let t = Float(i) / Float(sr)
        var s = sin(2 * Float.pi * Float(f) * t)
        s += 0.35 * sin(2 * Float.pi * Float(f) * 2 * t)
        s = tanh(1.5 * s)
        let e = min(t / 0.01, 1) * exp(-t / (n == 2 ? 0.18 : 0.4))
        gameover.append(0.5 * s * e)
    }
}
writeWav(gameover, "gameover")

// Spinner: soft muted tick, played once per revolution — low-passed and
// quiet so rapid spins don't get aggressive.
var spinner = [Float]()
var lpTick: Float = 0
for i in seconds(0.03) {
    let t = Float(i) / Float(sr)
    let noise = Float.random(in: -1...1)
    lpTick += 0.18 * (noise - lpTick)
    var s = 0.5 * lpTick * exp(-t / 0.007)
    s += 0.3 * sin(2 * Float.pi * 850 * t) * exp(-t / 0.01)
    spinner.append(0.55 * s)
}
writeWav(spinner, "spinner")

// Rollover: soft lane ding.
var rollover = [Float]()
for i in seconds(0.18) {
    let t = Float(i) / Float(sr)
    var s = sin(2 * Float.pi * 880 * t) * exp(-t / 0.06)
    s += 0.4 * sin(2 * Float.pi * 1760 * t) * exp(-t / 0.03)
    rollover.append(0.55 * s)
}
writeWav(rollover, "rollover")

// Saucer: ball swallowed — descending blip.
var saucer = [Float]()
phase = 0
for i in seconds(0.24) {
    let t = Float(i) / Float(sr)
    let freq = 180 + 520 * exp(-t * 14)
    phase += 2 * Float.pi * freq / Float(sr)
    saucer.append(0.6 * sin(phase) * exp(-t / 0.1))
}
writeWav(saucer, "saucer")

// Eject: kicker pop.
var eject = [Float]()
phase = 0
for i in seconds(0.1) {
    let t = Float(i) / Float(sr)
    let freq = 130 + 340 * t
    phase += 2 * Float.pi * freq / Float(sr)
    var s = 0.8 * sin(phase) * exp(-t / 0.03)
    s += 0.4 * Float.random(in: -1...1) * exp(-t / 0.005)
    eject.append(s)
}
writeWav(eject, "eject")

// Lock: two-note rising confirmation.
var lock = [Float]()
for (n, f) in [659.25, 987.77].enumerated() {
    for i in seconds(n == 1 ? 0.3 : 0.13) {
        let t = Float(i) / Float(sr)
        var s = sin(2 * Float.pi * Float(f) * t)
        s += 0.4 * sin(2 * Float.pi * Float(f) * 2 * t)
        s = tanh(1.4 * s)
        lock.append(0.45 * s * min(t / 0.008, 1) * exp(-t / 0.14))
    }
}
writeWav(lock, "lock")

// Multiball: grand six-note fanfare into a held shimmering chord.
var multiball = [Float]()
let mbNotes: [Float] = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0]
for (n, f) in mbNotes.enumerated() {
    let dur: Float = n == mbNotes.count - 1 ? 0.7 : 0.09
    for i in seconds(dur) {
        let t = Float(i) / Float(sr)
        let vib = n == mbNotes.count - 1 ? 1 + 0.008 * sin(2 * Float.pi * 6 * t) : 1
        var s = sin(2 * Float.pi * f * vib * t)
        s += 0.5 * sin(2 * Float.pi * f * 0.5 * t)
        s += 0.3 * sin(2 * Float.pi * f * 2 * t)
        s = tanh(1.5 * s)
        let e = min(t / 0.006, 1) * exp(-t / (n == mbNotes.count - 1 ? 0.3 : 0.6))
        multiball.append(0.5 * s * e)
    }
}
writeWav(multiball, "multiball")

// Mode start: alarm riser.
var mode = [Float]()
phase = 0
for i in seconds(0.55) {
    let t = Float(i) / Float(sr)
    let freq = 220 + 660 * t
    phase += 2 * Float.pi * freq / Float(sr)
    var s = sin(phase)
    s += 0.35 * sin(phase * 2)
    s = tanh(1.6 * s)
    mode.append(0.45 * s * min(t / 0.02, 1) * exp(-t / 0.5))
}
writeWav(mode, "mode")

// Music: 8-bar synth loop in A minor (Am Am F F C C G G) at 112 BPM —
// bass eighths, arpeggio sixteenths, soft pad, hats, snare on 2 & 4.
let beatDur: Float = 60.0 / 112.0
let chordRoots: [Float] = [110, 110, 87.31, 87.31, 130.81, 130.81, 98, 98]
let chordArps: [[Float]] = [
    [440, 523.25, 659.25], [440, 523.25, 659.25],
    [349.23, 440, 523.25], [349.23, 440, 523.25],
    [523.25, 659.25, 783.99], [523.25, 659.25, 783.99],
    [392, 493.88, 587.33], [392, 493.88, 587.33],
]
let padChords: [[Float]] = [
    [220, 261.63, 329.63], [220, 261.63, 329.63],
    [174.61, 220, 261.63], [174.61, 220, 261.63],
    [261.63, 329.63, 392], [261.63, 329.63, 392],
    [196, 246.94, 293.66], [196, 246.94, 293.66],
]
var music = [Float](repeating: 0, count: Int(Float(sr) * beatDur * 32))

func mixInto(start: Float, dur: Float, _ gen: (Float) -> Float) {
    let s0 = Int(start * Float(sr))
    let n = Int(dur * Float(sr))
    for i in 0..<n where s0 + i < music.count {
        music[s0 + i] += gen(Float(i) / Float(sr))
    }
}

for bar in 0..<8 {
    let barStart = Float(bar) * beatDur * 4
    let root = chordRoots[bar]
    let arp = chordArps[bar]
    let pad = padChords[bar]

    mixInto(start: barStart, dur: beatDur * 4) { t in
        var s: Float = 0
        for f in pad { s += sin(2 * Float.pi * f * t) }
        let e = min(t / 0.4, 1) * max(min((beatDur * 4 - t) / 0.6, 1), 0)
        return 0.014 * s * e
    }
    for b in 0..<4 {
        let bs = barStart + Float(b) * beatDur
        for h in 0..<2 {
            let ns = bs + Float(h) * beatDur / 2
            mixInto(start: ns, dur: beatDur * 0.45) { t in
                var s = sin(2 * Float.pi * root * t) + 0.4 * sin(2 * Float.pi * root * 2 * t)
                s = tanh(1.8 * s)
                return 0.15 * s * min(t / 0.008, 1) * exp(-t / (beatDur * 0.45))
            }
            mixInto(start: ns, dur: 0.05) { t in
                (h == 1 ? 0.045 : 0.028) * Float.random(in: -1...1) * exp(-t / 0.012)
            }
        }
        if b % 2 == 1 {
            mixInto(start: bs, dur: 0.14) { t in
                0.08 * (Float.random(in: -1...1) * exp(-t / 0.045)
                        + 0.5 * sin(2 * Float.pi * 190 * t) * exp(-t / 0.05))
            }
        }
        for q in 0..<4 {
            let ns = bs + Float(q) * beatDur / 4
            let f = arp[(b * 4 + q) % 3] * (q == 3 ? 2 : 1)
            mixInto(start: ns, dur: beatDur * 0.21) { t in
                var s = sin(2 * Float.pi * f * t) + 0.3 * sin(2 * Float.pi * f * 2 * t)
                s = tanh(1.3 * s)
                return 0.06 * s * min(t / 0.004, 1) * exp(-t / (beatDur * 0.16))
            }
        }
    }
}
writeWav(music, "music")

// Nudge: deep cabinet thump.
var nudgeSnd = [Float]()
phase = 0
for i in seconds(0.13) {
    let t = Float(i) / Float(sr)
    let freq = 55 + 60 * exp(-t * 40)
    phase += 2 * Float.pi * freq / Float(sr)
    var s = 0.9 * sin(phase) * exp(-t / 0.05)
    s += 0.25 * Float.random(in: -1...1) * exp(-t / 0.008)
    nudgeSnd.append(s)
}
writeWav(nudgeSnd, "nudge")

// Jackpot: rising retro arpeggio (C5 E5 G5 C6) into a shimmering held note.
var jackpot = [Float]()
let notes: [Float] = [523.25, 659.25, 783.99, 1046.5]
for (n, f) in notes.enumerated() {
    let dur: Float = n == notes.count - 1 ? 0.5 : 0.11
    for i in seconds(dur) {
        let t = Float(i) / Float(sr)
        let vib = n == notes.count - 1 ? 1 + 0.006 * sin(2 * Float.pi * 6 * t) : 1
        var s = sin(2 * Float.pi * f * vib * t)
        s += 0.4 * sin(2 * Float.pi * f * 2 * t)
        s = tanh(1.6 * s)
        let e = min(t / 0.005, 1) * exp(-t / (n == notes.count - 1 ? 0.22 : 0.5))
        jackpot.append(0.5 * s * e)
    }
}
writeWav(jackpot, "jackpot")

// Wormhole (capture): the ball is swallowed — a falling "gulp" (low sine
// sweeping down) under a dark noise whoosh that closes in.
var wormholeSnd = [Float]()
phase = 0
var wlp: Float = 0
for i in seconds(0.6) {
    let t = Float(i) / Float(sr)
    let freq = 60 + 240 * exp(-t * 6)
    phase += 2 * Float.pi * freq / Float(sr)
    let gulp = sin(phase) * min(t / 0.01, 1) * exp(-t / 0.22)
    wlp += (0.02 + 0.25 * exp(-t * 5)) * (Float.random(in: -1...1) - wlp)
    let whoosh = wlp * sin(Float.pi * min(t / 0.6, 1))
    wormholeSnd.append(0.8 * gulp + 0.9 * whoosh)
}
writeWav(wormholeSnd, "wormhole")

// Warp: hyperspace jump — a rising glide with a slight chorus (two detuned
// voices) and a soft octave below, swelling and fading.
var warpSnd = [Float]()
var pa: Float = 0, pb: Float = 0, pc: Float = 0
for i in seconds(0.8) {
    let t = Float(i) / Float(sr)
    let freq = 110 * pow(2, 2.2 * t / 0.8)
    pa += 2 * Float.pi * freq / Float(sr)
    pb += 2 * Float.pi * freq * 1.012 / Float(sr)
    pc += 2 * Float.pi * freq * 0.5 / Float(sr)
    let env = sin(Float.pi * min(t / 0.8, 1)) * (0.6 + 0.4 * sin(2 * Float.pi * 9 * t))
    warpSnd.append(0.32 * (sin(pa) + sin(pb)) * env + 0.35 * sin(pc) * env)
}
writeWav(warpSnd, "warp")

// Ramp: the ball rolls up the ramp — a low rumble whose pitch rises, over
// lowpassed rolling noise.
var rampSnd = [Float]()
phase = 0
var rlp: Float = 0
for i in seconds(0.55) {
    let t = Float(i) / Float(sr)
    let freq = 70 + 90 * t / 0.55
    phase += 2 * Float.pi * freq / Float(sr)
    let rumble = (sin(phase) + 0.4 * sin(2 * phase)) * (0.7 + 0.3 * sin(2 * Float.pi * 23 * t))
    rlp += 0.05 * (Float.random(in: -1...1) - rlp)
    let env = min(t / 0.04, 1) * exp(-max(t - 0.3, 0) / 0.12)
    rampSnd.append((0.55 * rumble + 1.2 * rlp) * env)
}
writeWav(rampSnd, "ramp")
