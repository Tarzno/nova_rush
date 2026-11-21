// Prepares voice callouts (Kokoro TTS takes) for the game: trims leading/trailing
// silence (keeping a short pad), normalizes the peak to -1 dBFS and writes a
// 16-bit mono WAV into Sources/NovaRush/Resources/Voice/<name>.wav.
//
// Usage: swift Tools/voiceprep.swift <name>=<source.wav> [<name>=<source.wav> ...]
// Source clips come from Tools/kokoro_voices.sh (generated/voices/); the line
// list and voice settings are documented in Tools/voice_lines.txt.
import AVFoundation

let outDir = URL(fileURLWithPath: "Sources/NovaRush/Resources/Voice", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for arg in CommandLine.arguments.dropFirst() {
    let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { print("skip \(arg)"); continue }
    let src = URL(fileURLWithPath: (parts[1] as NSString).expandingTildeInPath)
    let file = try AVAudioFile(forReading: src)
    let fmt = file.processingFormat
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    let n = Int(buf.frameLength)
    let x = buf.floatChannelData![0]
    let sr = fmt.sampleRate

    var peak: Float = 0
    for i in 0..<n { peak = max(peak, abs(x[i])) }
    let gate = peak * 0.03                       // ≈ -30 dB below the peak
    var first = 0, last = n - 1
    while first < n && abs(x[first]) < gate { first += 1 }
    while last > first && abs(x[last]) < gate { last -= 1 }
    let pad = Int(sr * 0.03), tail = Int(sr * 0.12)
    first = max(0, first - pad); last = min(n - 1, last + tail)
    let len = last - first + 1
    let gain = peak > 0 ? 0.891 / peak : 1       // -1 dBFS

    let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false)!
    let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(len))!
    out.frameLength = AVAudioFrameCount(len)
    let y = out.floatChannelData![0]
    let fade = min(Int(sr * 0.04), len / 4)
    for i in 0..<len {
        var g = gain
        if i >= len - fade { g *= Float(len - i) / Float(fade) }   // soft tail
        y[i] = x[first + i] * g
    }
    let dst = outDir.appendingPathComponent("\(parts[0]).wav")
    try? FileManager.default.removeItem(at: dst)
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr,
                                   AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                   AVLinearPCMIsFloatKey: false]
    let w = try AVAudioFile(forWriting: dst, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try w.write(from: out)
    print(String(format: "%-12@ %.2fs (was %.2fs), gain %.1f dB", parts[0] as NSString,
                 Double(len) / sr, Double(n) / sr, 20 * log10(Double(gain))))
}
