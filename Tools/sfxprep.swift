// Prepares generated (Stable Audio 3) sound effects for the game: downmix to
// mono, resample to 44.1 kHz (the format every SoundBank player is wired
// with — all effects must share it), trim leading silence tightly (attack
// matters for flipper/bumper hits), cut to a maximum length with a fade-out,
// normalize the peak, and write 16-bit WAV to Sources/NovaRush/Resources/SFX/.
//
// Usage: swift Tools/sfxprep.swift <name>=<source>[@maxSeconds[@peakDB[@loudDB]]] ...
//   e.g. flipper=<ComfyUI output>/NovaRush/sfx_flipper_00003.flac@0.2@-1@-15
// loudDB (optional): target RMS of the loudest 100 ms. Recorded-style hits
// are much peakier than the synthesized originals, so matching loudness
// needs more gain than the peak allows — the excess goes through a tanh soft
// limiter (adds a little punch, never clips).
// Generated sources: Tools/comfy/stableaudio3_sfx_api.json (see sfx_lines.txt).
import AVFoundation

let outDir = URL(fileURLWithPath: "Sources/NovaRush/Resources/SFX", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

func load(_ url: URL) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: url)
    let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: raw)
    // Downmix by hand (average all channels) so the converter only resamples.
    let ch = Int(raw.format.channelCount), n = Int(raw.frameLength)
    let mono = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: raw.format.sampleRate, channels: 1, interleaved: false)!,
                                frameCapacity: AVAudioFrameCount(n))!
    mono.frameLength = AVAudioFrameCount(n)
    for i in 0..<n {
        var s: Float = 0
        for c in 0..<ch { s += raw.floatChannelData![c][i] }
        mono.floatChannelData![0][i] = s / Float(ch)
    }
    if mono.format.sampleRate == target.sampleRate { return mono }
    let conv = AVAudioConverter(from: mono.format, to: target)!
    let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity:
        AVAudioFrameCount(Double(n) * target.sampleRate / mono.format.sampleRate) + 1024)!
    var fed = false
    var err: NSError?
    _ = conv.convert(to: out, error: &err) { _, st in
        if fed { st.pointee = .endOfStream; return nil }
        fed = true; st.pointee = .haveData; return mono
    }
    return out
}

for arg in CommandLine.arguments.dropFirst() {
    let kv = arg.split(separator: "=", maxSplits: 1).map(String.init)
    guard kv.count == 2 else { print("skip \(arg)"); continue }
    let opts = kv[1].split(separator: "@").map(String.init)
    let src = URL(fileURLWithPath: (opts[0] as NSString).expandingTildeInPath)
    let maxSec = opts.count > 1 ? Double(opts[1]) ?? 1.0 : 1.0
    let peakDB = opts.count > 2 ? Double(opts[2]) ?? -1 : -1
    let loudDB: Double? = opts.count > 3 ? Double(opts[3]) : nil
    let buf = try load(src)
    let x = buf.floatChannelData![0], n = Int(buf.frameLength)
    var peak: Float = 0
    for i in 0..<n { peak = max(peak, abs(x[i])) }
    var first = 0
    while first < n && abs(x[first]) < peak * 0.05 { first += 1 }
    first = max(0, first - 88)                         // 2 ms pre-roll
    let len = min(n - first, Int(maxSec * 44100))
    let fade = min(Int(0.03 * 44100), len / 3)
    let ceiling = Float(pow(10, peakDB / 20))
    var gain = ceiling / max(peak, 1e-6)
    var limit = false
    if let loudDB {
        // Loudest-100 ms RMS of the trimmed clip at unity gain.
        let w = min(len, 4410); var best: Float = 0; var j = 0
        while j + w <= len { var e: Float = 0; for k in j..<(j+w) { e += x[first+k]*x[first+k] }
                             best = max(best, sqrt(e / Float(w))); j += 441 }
        let want = Float(pow(10, loudDB / 20)) / max(best, 1e-6)
        if want > gain { gain = want; limit = true }
    }
    let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(len))!
    out.frameLength = AVAudioFrameCount(len)
    for i in 0..<len {
        var g = gain
        if i >= len - fade { g *= Float(len - i) / Float(fade) }
        var v = x[first + i] * g
        if limit { v = ceiling * tanh(v / ceiling) }
        out.floatChannelData![0][i] = v
    }
    let dst = outDir.appendingPathComponent("\(kv[0]).wav")
    try? FileManager.default.removeItem(at: dst)
    let w = try AVAudioFile(forWriting: dst, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false],
        commonFormat: .pcmFormatFloat32, interleaved: false)
    try w.write(from: out)
    print(String(format: "%-10@ %.2fs (lead trim %.3fs), peak %.0f dB", kv[0] as NSString,
                 Double(len) / 44100, Double(first) / 44100, peakDB))
}
