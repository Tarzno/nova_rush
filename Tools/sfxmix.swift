// Layers two sounds (e.g. a generated thump under the synthesized "pling"):
// both are downmixed to mono 44.1 kHz, aligned at their onsets, mixed with
// the given gains (dB) and written as a WAV that sfxprep.swift can finish.
// Usage: swift Tools/sfxmix.swift <out.wav> <a>@<gainDB> <b>@<gainDB>
import AVFoundation

let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
func load(_ path: String) -> [Float] {
    let f = try! AVAudioFile(forReading: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    let raw = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try! f.read(into: raw)
    let ch = Int(raw.format.channelCount), n = Int(raw.frameLength)
    let mono = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32,
        sampleRate: raw.format.sampleRate, channels: 1, interleaved: false)!, frameCapacity: AVAudioFrameCount(n))!
    mono.frameLength = AVAudioFrameCount(n)
    for i in 0..<n { var s: Float = 0; for c in 0..<ch { s += raw.floatChannelData![c][i] }; mono.floatChannelData![0][i] = s / Float(ch) }
    var buf = mono
    if mono.format.sampleRate != 44100 {
        let conv = AVAudioConverter(from: mono.format, to: fmt)!
        let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(n) * 44100 / mono.format.sampleRate) + 1024)!
        var fed = false; var err: NSError?
        _ = conv.convert(to: out, error: &err) { _, st in if fed { st.pointee = .endOfStream; return nil }; fed = true; st.pointee = .haveData; return mono }
        buf = out
    }
    let x = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    let peak = x.map(abs).max() ?? 1
    let onset = x.firstIndex { abs($0) > peak * 0.05 } ?? 0
    return Array(x[max(0, onset - 44)...]).map { $0 / peak }      // onset-aligned, peak 1
}
let args = Array(CommandLine.arguments.dropFirst())
let layers = args.dropFirst().map { a -> [Float] in
    let p = a.split(separator: "@").map(String.init)
    let g = Float(pow(10, (Double(p[1]) ?? 0) / 20))
    return load(p[0]).map { $0 * g }
}
var mix = [Float](repeating: 0, count: layers.map(\.count).max() ?? 0)
for l in layers { for i in l.indices { mix[i] += l[i] } }
let m = mix.map(abs).max() ?? 1
let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(mix.count))!
out.frameLength = AVAudioFrameCount(mix.count)
for i in mix.indices { out.floatChannelData![0][i] = mix[i] / m * 0.9 }
let dst = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath)
try? FileManager.default.removeItem(at: dst)
// Write inside a function: a top-level AVAudioFile in a script is never
// deinitialized, so the WAV would never be finalized (0 frames).
func save() {
    let w = try! AVAudioFile(forWriting: dst, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
    try! w.write(from: out)
}
save()
print("mixed \(layers.count) layers → \(dst.lastPathComponent), \(String(format: "%.2f", Double(mix.count) / 44100))s")
