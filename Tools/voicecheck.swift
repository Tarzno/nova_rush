// Screens voice clips for failed TTS takes: a good take has ≥ ~0.2 s of
// voiced audio; garbled / silent takes measured ≤ 0.08 s. Usage:
//   swift Tools/voicecheck.swift Sources/NovaRush/Resources/Voice/*.wav
import AVFoundation
// Per file: voiced-frame ratio (energy > -35 dB of peak and ZCR low), mean ZCR, spectral-flatness proxy.
for path in CommandLine.arguments.dropFirst() {
    let f = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try! f.read(into: b); let x = b.floatChannelData![0]; let n = Int(b.frameLength)
    let sr = f.processingFormat.sampleRate; let win = Int(sr * 0.02)
    var peak: Float = 0; for i in 0..<n { peak = max(peak, abs(x[i])) }
    var frames = 0, loud = 0, voiced = 0; var zsum = 0.0
    var i = 0
    while i + win < n {
        var e: Float = 0; var z = 0
        for k in i..<(i+win) { e += x[k]*x[k]; if k > i && (x[k] >= 0) != (x[k-1] >= 0) { z += 1 } }
        let rms = sqrt(e / Float(win)); let zcr = Double(z) / Double(win)
        frames += 1
        if rms > peak * 0.05 { loud += 1; zsum += zcr; if zcr < 0.15 { voiced += 1 } }
        i += win
    }
    let name = (path as NSString).lastPathComponent
    print(String(format: "%@  loud %.2fs  voiced %.2fs  meanZCR %.3f  voicedFrac %.2f", name,
                 Double(loud)*0.02, Double(voiced)*0.02, loud > 0 ? zsum/Double(loud) : 0,
                 loud > 0 ? Double(voiced)/Double(loud) : 0))
}
