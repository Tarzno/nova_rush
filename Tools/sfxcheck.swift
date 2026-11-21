// Spectral profile of short sound effects, for screening generated takes:
//   centroid  — brightness (Hz); "tinny" = high
//   flatness  — 0 = pure tone, 1 = white noise; "rattling/buzzy" = high
//   bass      — share of energy below 250 Hz; "thump" = high
//   pitch     — strongest spectral peak (Hz) in the first 150 ms (the "pling")
// Usage: swift Tools/sfxcheck.swift <file>...
import AVFoundation
import Accelerate

for p in CommandLine.arguments.dropFirst() {
    let f = try! AVAudioFile(forReading: URL(fileURLWithPath: (p as NSString).expandingTildeInPath))
    let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try! f.read(into: b)
    let sr = Float(f.processingFormat.sampleRate), n = Int(b.frameLength)
    let x = b.floatChannelData![0]
    var peak: Float = 0; for i in 0..<n { peak = max(peak, abs(x[i])) }
    var start = 0; while start < n && abs(x[start]) < peak * 0.1 { start += 1 }
    let N = 8192, log2n = vDSP_Length(13)
    var frame = [Float](repeating: 0, count: N)
    let len = min(N, n - start, Int(0.25 * sr))          // first 250 ms after onset
    var win = [Float](repeating: 0, count: len); vDSP_hann_window(&win, vDSP_Length(len), Int32(vDSP_HANN_NORM))
    for i in 0..<len { frame[i] = x[start + i] * win[i] }
    let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    var re = [Float](repeating: 0, count: N / 2), im = [Float](repeating: 0, count: N / 2)
    var mag = [Float](repeating: 0, count: N / 2)
    re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
        frame.withUnsafeBufferPointer { fp in
            fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(N / 2)) } }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &mag, 1, vDSP_Length(N / 2))
    } }
    let hz = sr / Float(N)
    var tot: Float = 0, cen: Float = 0, bass: Float = 0, logSum: Float = 0, cnt: Float = 0
    var best: Float = 0, bestF: Float = 0
    for k in 1..<(N / 2) {
        let fk = Float(k) * hz, m = mag[k]
        tot += m; cen += m * fk
        if fk < 250 { bass += m }
        if fk > 40 && fk < 12000 { logSum += log(m + 1e-12); cnt += 1 }
        if fk > 300 && fk < 6000 && m > best { best = m; bestF = fk }
    }
    var band: Float = 0; var bc: Float = 0
    for k in 1..<(N / 2) { let fk = Float(k) * hz; if fk > 40 && fk < 12000 { band += mag[k]; bc += 1 } }
    let flat = exp(logSum / cnt) / (band / bc)
    print(String(format: "%@  centroid %5.0f Hz  flatness %.3f  bass %4.1f%%  pitch %5.0f Hz",
                 (p as NSString).lastPathComponent, cen / tot, flat, 100 * bass / tot, bestF))
    vDSP_destroy_fftsetup(setup)
}
