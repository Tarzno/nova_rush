import AVFoundation

/// AVAudioEngine-based sample player: a pool of player→varispeed chains
/// gives every hit slight pitch variation (so repeats don't sound robotic)
/// and stereo panning that follows the playfield position. A separate
/// AVAudioPlayer cycles through the music tracks.
final class SoundBank: NSObject, AVAudioPlayerDelegate {
    private let engine = AVAudioEngine()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var players: [AVAudioPlayerNode] = []
    private var speeds: [AVAudioUnitVarispeed] = []
    private var next = 0
    private var music: AVAudioPlayer?
    private var musicURLs: [URL] = []
    private var musicIndex = 0
    private(set) var musicMuted = false
    private let musicVolume: Float = 0.3

    /// Every effect player runs in this one format; files in any other
    /// format are converted at load (a mismatched buffer would make
    /// scheduleBuffer throw).
    private let effectFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    // Voice callouts (Resources/Voice/*.wav, Kokoro TTS): one dedicated
    // player through a light reverb so the "ship's computer" sits in the
    // room. One line at a time — a new line only cuts in if it is at least
    // as important as the one speaking; otherwise it is dropped (late
    // callouts are worse than none). Music ducks under the voice.
    /// Callout name → its takes. `jackpot.wav`, `jackpot_2.wav`, … are all
    /// takes of "jackpot"; `say` picks one at random for variety.
    private var voices: [String: [AVAudioPCMBuffer]] = [:]
    private let voicePlayer = AVAudioPlayerNode()
    private let voiceReverb = AVAudioUnitReverb()
    private var voiceFormat: AVAudioFormat?      // nil = no voice chain
    private var voiceBusyUntil = Date.distantPast
    private var voicePriority = 0
    private var duckToken = 0
    var voiceMuted = UserDefaults.standard.bool(forKey: "voiceMuted") {
        didSet { UserDefaults.standard.set(voiceMuted, forKey: "voiceMuted") }
    }

    init(_ names: [String]) {
        super.init()
        for name in names {
            // Generated (Stable Audio 3) effects in Resources/SFX win over
            // the synthesized ones in Resources/Sounds, which stay as the
            // fallback (and which Tools/soundgen.swift may regenerate).
            guard let url = Bundle.resources.url(forResource: name, withExtension: "wav",
                                                 subdirectory: "Resources/SFX")
                    ?? Bundle.resources.url(forResource: name, withExtension: "wav",
                                            subdirectory: "Resources/Sounds"),
                  let file = try? AVAudioFile(forReading: url),
                  let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: raw)) != nil else { continue }
            let buffer = raw.format == effectFormat ? raw : Self.convert(raw, to: effectFormat)
            if let buffer { buffers[name] = buffer }
        }
        // The reverb cannot convert sample rates (fed a 24 kHz clip, its
        // output stays at the engine rate, so the voice played ~1.8× fast)
        // and rejects a 24 kHz output format (-10868). So every clip is
        // converted once, at load, to the engine's own rate in stereo; the
        // whole voice chain then runs in that format.
        let engineRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let voiceFormat = AVAudioFormat(standardFormatWithSampleRate: engineRate > 0 ? engineRate : 44100,
                                        channels: 2)!
        for url in Bundle.resources.urls(forResourcesWithExtension: "wav",
                                         subdirectory: "Resources/Voice") ?? [] {
            guard let file = try? AVAudioFile(forReading: url),
                  let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: raw)) != nil,
                  let converted = Self.convert(raw, to: voiceFormat) else { continue }
            var name = url.deletingPathExtension().lastPathComponent
            if let r = name.range(of: #"_\d+$"#, options: .regularExpression) {
                name.removeSubrange(r)
            }
            voices[name, default: []].append(converted)
        }
        if !voices.isEmpty {
            self.voiceFormat = voiceFormat
            engine.attach(voicePlayer)
            engine.attach(voiceReverb)
            voiceReverb.loadFactoryPreset(.mediumRoom)
            voiceReverb.wetDryMix = 14
        }
        guard !buffers.isEmpty || !voices.isEmpty else { return }
        for _ in 0..<(buffers.isEmpty ? 0 : 10) {
            let player = AVAudioPlayerNode()
            let speed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(speed)
            players.append(player)
            speeds.append(speed)
        }
        connectNodes()
        engine.prepare()
        try? engine.start()
        // A new output device (headphones, AirPods, a display's speakers)
        // stops the engine; without a restart every effect and callout would
        // stay silent for the rest of the session.
        NotificationCenter.default.addObserver(self, selector: #selector(engineConfigurationChanged),
                                               name: .AVAudioEngineConfigurationChange, object: engine)
    }

    private func connectNodes() {
        for (player, speed) in zip(players, speeds) {
            engine.connect(player, to: speed, format: effectFormat)
            engine.connect(speed, to: engine.mainMixerNode, format: effectFormat)
        }
        if let voiceFormat {
            // Stays at the rate the clips were converted to; the main mixer
            // resamples if the new device runs at another rate.
            engine.connect(voicePlayer, to: voiceReverb, format: voiceFormat)
            engine.connect(voiceReverb, to: engine.mainMixerNode, format: voiceFormat)
        }
    }

    @objc private func engineConfigurationChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.restartEngine() }
    }

    private func restartEngine() {
        engine.stop()
        connectNodes()
        engine.prepare()
        try? engine.start()
        voiceBusyUntil = .distantPast          // whatever was speaking has stopped
    }

    /// Test hook: what a device change does — the engine stops and posts
    /// the configuration-change notification.
    func simulateOutputChangeForTest() {
        engine.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }
    var engineRunningForTest: Bool { engine.isRunning }

    /// `pan` −1…1 across the table; `jitter` is the random pitch spread
    /// (use 0 for melodic cues that must stay in tune).
    func play(_ name: String, volume: Float = 1.0, pan: Float = 0, jitter: Float = 0.06) {
        guard let buffer = buffers[name], engine.isRunning, !players.isEmpty else { return }
        let i = next
        next = (next + 1) % players.count
        players[i].stop()
        speeds[i].rate = jitter > 0 ? Float.random(in: (1 - jitter)...(1 + jitter)) : 1
        players[i].volume = volume
        players[i].pan = max(-0.9, min(0.9, pan))
        players[i].scheduleBuffer(buffer, at: nil)
        players[i].play()
    }

    /// Speak a callout. `priority`: 1 = info, 2 = notable, 3 = big moment,
    /// 4 = must hear (tilt, game over). `delay` defers the line (e.g. to let
    /// a sound effect land first). Returns false if it was dropped.
    @discardableResult
    func say(_ name: String, priority: Int = 2, delay: TimeInterval = 0) -> Bool {
        guard !voiceMuted, let buffer = voices[name]?.randomElement(), engine.isRunning else { return false }
        let now = Date()
        if now < voiceBusyUntil && priority < voicePriority { return false }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        voiceBusyUntil = now.addingTimeInterval(delay + duration)
        voicePriority = priority
        voicePlayer.stop()
        voicePlayer.volume = 1.0
        if delay > 0 {
            let t = AVAudioTime(hostTime: mach_absolute_time()
                                + AVAudioTime.hostTime(forSeconds: delay))
            voicePlayer.scheduleBuffer(buffer, at: t)
        } else {
            voicePlayer.scheduleBuffer(buffer, at: nil)
        }
        voicePlayer.play()
        duckMusic(from: delay, for: duration)
        lastSpokenForTest = name
        return true
    }

    /// Test hook: the last callout that was accepted for playback.
    private(set) var lastSpokenForTest: String?

    /// Sample-rate / channel conversion of a whole clip (e.g. 24 kHz mono →
    /// 48 kHz stereo).
    private static func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: input.format, to: format) else { return nil }
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return input
        }
        return status == .error ? nil : output
    }

    /// Test hook: number of takes per callout.
    var voiceTakesForTest: [String: Int] { voices.mapValues(\.count) }

    /// Test hook: seconds of voice audio consumed so far (player clock).
    /// Compared against wall-clock time it reveals a sample-rate mismatch
    /// (1.0 = correct speed; ≈1.8 = 24 kHz clips running at 44.1 kHz).
    var voiceClockForTest: Double? {
        guard let nodeTime = voicePlayer.lastRenderTime,
              let t = voicePlayer.playerTime(forNodeTime: nodeTime) else { return nil }
        return Double(t.sampleTime) / t.sampleRate
    }

    private func duckMusic(from delay: TimeInterval, for duration: TimeInterval) {
        duckToken += 1
        let token = duckToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, token == self.duckToken else { return }
            self.music?.setVolume(self.musicVolume * 0.35, fadeDuration: 0.12)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.15) { [weak self] in
            guard let self, token == self.duckToken else { return }
            self.music?.setVolume(self.musicVolume, fadeDuration: 0.5)
        }
    }

    /// Background music: cycles (shuffled) through the bundled tracks,
    /// falling back to the synthesized loop if none are present.
    func startMusic() {
        guard music == nil else { return }
        musicURLs = (Bundle.resources.urls(forResourcesWithExtension: "m4a",
                                           subdirectory: "Resources/Music") ?? []).shuffled()
        if musicURLs.isEmpty,
           let fallback = Bundle.resources.url(forResource: "music", withExtension: "wav",
                                               subdirectory: "Resources/Sounds") {
            musicURLs = [fallback]
        }
        playNextTrack()
    }

    private func playNextTrack() {
        guard !musicURLs.isEmpty else { return }
        let url = musicURLs[musicIndex % musicURLs.count]
        musicIndex += 1
        music = try? AVAudioPlayer(contentsOf: url)
        music?.delegate = self
        music?.numberOfLoops = musicURLs.count == 1 ? -1 : 0
        music?.volume = musicVolume
        if !musicMuted { music?.play() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playNextTrack()
    }

    /// Pause/resume music for the game's pause (independent of mute).
    func setPaused(_ paused: Bool) {
        if paused {
            voicePlayer.pause()
            music?.pause()
        } else {
            if voicePlayer.engine != nil { voicePlayer.play() }
            if !musicMuted { music?.play() }
        }
    }

    /// Returns true if music is now muted.
    func toggleMusic() -> Bool {
        musicMuted.toggle()
        if musicMuted {
            music?.pause()
        } else if music == nil {
            playNextTrack()
        } else {
            music?.play()
        }
        return musicMuted
    }
}
