import AVFoundation
import Speech
import Foundation
import AVFAudio

class EveVoiceManager: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?

    var onTranscriptFinal: ((String) -> Void)?
    var onTranscriptPartial: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onReadyToListen: (() -> Void)?
    /// Fires when the Director starts speaking while Eve is mid-reply.
    /// Subscriber should stop showing Eve as speaking and prepare for the
    /// recognizer to produce the user's incoming utterance.
    var onBargeIn: (() -> Void)?

    private var speakCompletion: (() -> Void)?
    private var latestPartial = ""
    private var lastTranscriptUpdate = Date()

    // Silence detection — main-thread timer samples lastSpeechTime every 200ms.
    // Bumped delays after Director feedback: Eve was interrupting mid-thought.
    // Now Eve waits longer before assuming you're finished, especially when
    // the trailing word is a connector ("and", "but", "so", "because", …).
    private var lastSpeechTime: Date = Date()
    private var firstSpeechTime: Date? = nil      // set when first voice activity detected
    private var silenceWatchdog: Timer?
    // RMS-based "is the mic hearing sound" detector. Lowered substantially
    // because the previous 0.012 dropped below the floor between syllables
    // and the watchdog mistook normal speech rhythm for silence. Partial
    // transcript updates are now the PRIMARY end-of-speech signal; RMS only
    // catches activity the recognizer hasn't transcribed yet (mumbles,
    // breaths, starts of utterances).
    private let silenceThreshold: Float = 0.004
    // Pause windows tuned for FLUID conversation. Director was being cut off
    // mid-thought; SFSpeechRecognizer's own `isFinal` callback is now ignored
    // as a submit trigger so these delays are the SOLE arbiter of end-of-utterance.
    private let shortPauseDelay: TimeInterval = 1.8        // sentence-final punctuation (was 1.0)
    private let mediumPauseDelay: TimeInterval = 2.6       // typical mid-utterance (was 1.4)
    private let longPauseDelay: TimeInterval = 3.4         // very short fragment (was 1.9)
    private let connectorPauseDelay: TimeInterval = 4.2    // trailing "and"/"but"/"so" (was 2.4)
    private let minSpeakDuration: TimeInterval = 0.4       // must have spoken for at least this long

    /// Buffer that survives recognizer restarts. SFSpeechRecognizer ends the
    /// recognition task whenever it decides `isFinal` (often after <1s pause)
    /// — to keep listening, we restart the task and concat each burst of
    /// recognized text into this buffer. The Director sees a continuous
    /// transcript regardless of how many internal restarts happened.
    private var accumulatedFinal: String = ""
    // Words that mean the Director is mid-thought when they trail a phrase.
    private let connectorWords: Set<String> = [
        "and", "but", "or", "so", "then", "because", "cause",
        "with", "for", "to", "from", "as", "if", "when", "while",
        "that", "which", "who", "where", "until", "since", "though",
        "although", "however", "therefore", "thus", "also", "the", "a", "an",
    ]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Listening

    func startListening() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let recordPermission = AVAudioApplication.shared.recordPermission

        if speechStatus == .authorized && recordPermission == .granted {
            beginRecognition()
            return
        }

        if recordPermission == .undetermined {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                guard granted else { return }
                self?.requestSpeechAuthorizationIfNeeded()
            }
            return
        }

        guard recordPermission == .granted else { return }
        requestSpeechAuthorizationIfNeeded()
    }

    private func requestSpeechAuthorizationIfNeeded() {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized {
            DispatchQueue.main.async { [weak self] in self?.beginRecognition() }
            return
        }

        guard status == .notDetermined else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            guard authorization == .authorized else { return }
            DispatchQueue.main.async { self?.beginRecognition() }
        }
    }

    private func beginRecognition() {
        stopEngine()

        accumulatedFinal = ""
        latestPartial = ""
        lastTranscriptUpdate = Date()
        lastSpeechTime = Date()
        firstSpeechTime = nil

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData, frameLength > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameLength { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(frameLength))

            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(min(rms * 20, 1.0))
            }

            // Track first and last speech time for silence detection
            if rms >= (self?.silenceThreshold ?? 0.012) {
                let now = Date()
                self?.lastSpeechTime = now
                if self?.firstSpeechTime == nil { self?.firstSpeechTime = now }
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            return
        }

        // Watchdog fires every 200ms on main thread — checks elapsed silence
        silenceWatchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkSilence()
        }

        startRecognitionTask()
    }

    /// Start (or restart) the SFSpeechRecognizer task. Called once at engine
    /// start and again whenever the recognizer fires `isFinal` (which it does
    /// after even a brief pause). The audio tap keeps appending to the
    /// current `recognitionRequest`, so audio flow is uninterrupted across
    /// restarts — the Director never gets cut off.
    private func startRecognitionTask() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation   // long-form, patient endpointing
        recognitionRequest = req

        recognitionTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    // Apple's recognizer thinks we're done — it isn't authoritative.
                    // Fold this burst into the accumulated transcript and rekick
                    // recognition so the user can keep talking. The silence
                    // watchdog (real audio RMS) is the only thing that ends an
                    // utterance now.
                    DispatchQueue.main.async {
                        self.foldIsFinal(text)
                    }
                } else if !text.isEmpty {
                    let combined = self.accumulatedFinal.isEmpty
                        ? text
                        : "\(self.accumulatedFinal) \(text)"
                    DispatchQueue.main.async {
                        // Partial transcript = authoritative proof user is
                        // still speaking. Refresh BOTH timers so the watchdog
                        // can't fire while text is still being added.
                        let now = Date()
                        self.latestPartial = combined
                        self.lastTranscriptUpdate = now
                        self.lastSpeechTime = now
                        if self.firstSpeechTime == nil { self.firstSpeechTime = now }
                        self.onTranscriptPartial?(combined)
                    }
                }
            }
            if error != nil {
                // Don't kill the engine — restart the task. Common transient
                // errors are timeouts after silence, which we recover from.
                DispatchQueue.main.async {
                    if self.silenceWatchdog != nil {
                        self.startRecognitionTask()
                    }
                }
            }
        }
    }

    /// Called when SFSpeechRecognizer fires `isFinal`. Append the burst to
    /// `accumulatedFinal`, push a partial-transcript update so the UI stays
    /// in sync, then restart the recognizer so audio continues to flow.
    private func foldIsFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // The recognizer producing a final burst = unambiguous proof of
            // recent speech. Refresh the watchdog clocks so the restart
            // window can't trigger a false silence detection.
            let now = Date()
            accumulatedFinal = accumulatedFinal.isEmpty
                ? trimmed
                : "\(accumulatedFinal) \(trimmed)"
            latestPartial = accumulatedFinal
            lastTranscriptUpdate = now
            lastSpeechTime = now
            onTranscriptPartial?(accumulatedFinal)
        }
        // Critical: restart the recognizer so subsequent audio is still
        // recognized. Cancel the old task first to avoid duplicate callbacks.
        recognitionTask?.cancel()
        recognitionTask = nil
        if silenceWatchdog != nil {
            startRecognitionTask()
        }
    }

    private func checkSilence() {
        guard !latestPartial.isEmpty else { return }
        guard let firstSpoke = firstSpeechTime else { return }
        // Must have spoken for at least minSpeakDuration before silence can trigger submit
        let spokenFor = Date().timeIntervalSince(firstSpoke)
        guard spokenFor >= minSpeakDuration else { return }
        let quietSinceTranscriptUpdate = Date().timeIntervalSince(lastTranscriptUpdate)
        guard quietSinceTranscriptUpdate >= 0.3 else { return }
        let silentFor = Date().timeIntervalSince(lastSpeechTime)
        if silentFor >= pauseDelay(for: latestPartial) {
            submitPartialAndStop()
        }
    }

    private func pauseDelay(for transcript: String) -> TimeInterval {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return mediumPauseDelay }

        let words = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) }

        // If the trailing word is a connector ("and", "but", "so"…) the Director
        // is almost certainly mid-thought. Give them a long runway.
        if let lastWord = words.last, connectorWords.contains(lastWord) {
            return connectorPauseDelay
        }

        // Sentence-final punctuation — they probably finished a thought, but
        // still give a comfortable beat in case of follow-up.
        if let last = trimmed.last, ".!?".contains(last) {
            return shortPauseDelay
        }

        // Very short fragment — they're probably still warming up.
        if words.count <= 3 {
            return longPauseDelay
        }

        return mediumPauseDelay
    }

    private func submitPartialAndStop() {
        // Combine accumulated bursts (from prior isFinal callbacks) with the
        // current partial. This is the FULL transcript the Director just spoke.
        let combined = mergedTranscript()
        accumulatedFinal = ""
        latestPartial = ""
        lastTranscriptUpdate = Date()
        stopEngine()
        onAudioLevel?(0)
        if !combined.isEmpty { onTranscriptFinal?(combined) }
    }

    func stopListening() {
        let combined = mergedTranscript()
        accumulatedFinal = ""
        latestPartial = ""
        lastTranscriptUpdate = Date()
        stopEngine()
        onAudioLevel?(0)
        if !combined.isEmpty {
            DispatchQueue.main.async { self.onTranscriptFinal?(combined) }
        }
    }

    /// Pick the fuller of the two — `latestPartial` already incorporates
    /// `accumulatedFinal` in normal operation, but if a partial hasn't fired
    /// yet after the latest restart, `accumulatedFinal` alone is the source
    /// of truth.
    private func mergedTranscript() -> String {
        let p = latestPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = accumulatedFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.count >= a.count { return p }
        return a
    }

    private func stopEngine() {
        silenceWatchdog?.invalidate()
        silenceWatchdog = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - Speaking

    /// Speaks `text` aloud. Tries nexus-web's ElevenLabs route first
    /// (human-sounding voice). Falls back to the system synthesizer if the
    /// network call fails — Eve still talks if offline, just sounds robotic.
    func speak(_ text: String, completion: @escaping () -> Void) {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        speakCompletion = completion

        let clean = text
            .replacingOccurrences(of: #"\*\*|__|_|\*|`"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let speakable = String(clean.prefix(600))

        Task { [weak self] in
            guard let self else { return }
            if let mp3 = await self.fetchEveTTS(text: speakable) {
                await MainActor.run { self.playMP3(mp3) }
            } else {
                await MainActor.run { self.fallbackSystemSpeak(speakable) }
            }
        }
    }

    /// Hits nexus-web /api/eve/tts. Returns nil on any failure so caller
    /// can decide whether to fall back to system TTS.
    private func fetchEveTTS(text: String) async -> Data? {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/tts") else { return nil }
        guard let cookie = LumenAPIManager.shared.sessionCookie, !cookie.isEmpty else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("application/json",     forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)",     forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text":     text,
            "voice_id": LumenAPIManager.shared.voiceId,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func playMP3(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.isMeteringEnabled = true   // <- enable level metering for the orb
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            startTTSMetering()
            startBargeInMonitor()  // Director can interrupt Eve mid-reply
        } catch {
            // If the data isn't playable, fall back to system speech with a generic
            fallbackSystemSpeak("Voice playback failed.")
        }
    }

    // MARK: - Barge-in detection
    //
    // Lightweight VAD on the mic while Eve is speaking. Fires `onBargeIn`
    // when sustained user voice is detected, allowing the caller to stop
    // Eve's playback and switch to listening — natural-conversation pattern.
    //
    // Implemented via AVAudioRecorder (level metering only, audio discarded)
    // rather than a second AVAudioEngine, because two engines tapping the
    // mic simultaneously throws Core Audio -10877 errors all over the
    // console. Recorder + a 30Hz polling timer is much lighter and doesn't
    // collide with the speech-recognition engine when it's idle.
    //
    // Disable-able: set `bargeInEnabled = false` (defaults true) to skip
    // entirely if the mic is unavailable or the user prefers no interrupt.

    private var bargeInRecorder: AVAudioRecorder?
    private var bargeInTimer: Timer?
    private var bargeInVoiceFrames: Int = 0
    private let bargeInRMSThreshold: Float = 0.05    // linear (0…1) — high to avoid Eve's own playback
    private let bargeInSustainedFrames: Int = 6
    private let bargeInTempURL: URL = URL(
        fileURLWithPath: NSTemporaryDirectory() + "lumen-barge.caf"
    )
    var bargeInEnabled: Bool = true   // toggle off if it ever causes issues

    private func startBargeInMonitor() {
        guard bargeInEnabled,
              recognitionTask == nil,
              bargeInRecorder == nil
        else { return }

        let settings: [String: Any] = [
            AVFormatIDKey:           Int(kAudioFormatLinearPCM),
            AVSampleRateKey:         16000,
            AVNumberOfChannelsKey:   1,
            AVLinearPCMBitDepthKey:  16,
            AVLinearPCMIsFloatKey:   false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: bargeInTempURL, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else { return }
            bargeInRecorder = recorder
            bargeInVoiceFrames = 0

            // Poll meter at ~30Hz. Lighter than installing an audio tap; no
            // engine collision with AVSpeechSynthesizer / AVAudioPlayer.
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.pollBargeInMeter()
            }
            RunLoop.main.add(timer, forMode: .common)
            bargeInTimer = timer
        } catch {
            // Recorder couldn't start — common when mic is in use elsewhere.
            // Silently degrade. Director won't get barge-in this turn but
            // nothing crashes.
            bargeInRecorder = nil
        }
    }

    private func pollBargeInMeter() {
        guard let r = bargeInRecorder else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)   // -160 … 0
        // Convert dB to linear amplitude
        let clamped = max(-50, min(0, db))
        let linear = pow(10.0, Float(clamped) / 20.0)

        if linear >= bargeInRMSThreshold {
            bargeInVoiceFrames += 1
            if bargeInVoiceFrames >= bargeInSustainedFrames {
                handleBargeIn()
            }
        } else {
            bargeInVoiceFrames = max(0, bargeInVoiceFrames - 1)
        }
    }

    private func stopBargeInMonitor() {
        bargeInTimer?.invalidate()
        bargeInTimer = nil
        bargeInRecorder?.stop()
        bargeInRecorder = nil
        bargeInVoiceFrames = 0
    }

    /// Director made noise while Eve was speaking. Per the Director's spec:
    /// interrupt = "shut up so I can move on" — NOT "start listening."
    /// Going silent during Eve's reply means "I'm letting you finish, keep
    /// going." So we just stop her playback and idle out. The Director can
    /// hit the mic explicitly when they're ready to speak.
    private func handleBargeIn() {
        guard bargeInRecorder != nil else { return }
        stopBargeInMonitor()
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        stopTTSMetering()
        let completion = speakCompletion
        speakCompletion = nil
        onBargeIn?()        // listener flips eveStatus to .idle
        completion?()       // unblock anyone awaiting end-of-speech
    }

    /// 60Hz metering loop. While `audioPlayer` is alive, samples the average
    /// power on channel 0 and pushes a normalized 0…1 amplitude through
    /// `onAudioLevel`. This is what makes the EveOrb pulse with Eve's TTS
    /// voice (ElevenLabs MP3) instead of going dead during her replies.
    private var ttsMeterTimer: Timer?
    private func startTTSMetering() {
        ttsMeterTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer, player.isPlaying else {
                self?.stopTTSMetering()
                return
            }
            player.updateMeters()
            // averagePower returns dB in [-160, 0]. Map to linear 0…1 with a
            // perceptual curve — most speech sits in [-30, -10] dB so we
            // expand that range.
            let db = player.averagePower(forChannel: 0)
            let clamped = max(-50, min(0, db))
            let linear = pow(10.0, Float(clamped) / 20.0)        // 0…1
            // Boost a bit so quiet speech still drives visible motion
            let boosted = min(1.0, linear * 2.4)
            self.onAudioLevel?(boosted)
        }
        RunLoop.main.add(timer, forMode: .common)
        ttsMeterTimer = timer
    }

    private func stopTTSMetering() {
        ttsMeterTimer?.invalidate()
        ttsMeterTimer = nil
        onAudioLevel?(0)
    }

    private func fallbackSystemSpeak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let preferredVoices = [
            "com.apple.ttsbundle.siri_female_en-US_compact",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.ttsbundle.Samantha-compact",
        ]
        utterance.voice = preferredVoices
            .compactMap { AVSpeechSynthesisVoice(identifier: $0) }
            .first ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.08
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        startBargeInMonitor()  // Director can interrupt system synth too
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        stopTTSMetering()
        stopBargeInMonitor()
        speakCompletion?()
        speakCompletion = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // System synth: no isMeteringEnabled equivalent. We can't drive the
        // orb from real amplitude here, but barge-in still works (lifecycle
        // hooks fire stopBargeInMonitor on finish).
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.stopBargeInMonitor()
            self?.finishSpeaking()
        }
    }

    // MARK: - AVAudioPlayerDelegate (for ElevenLabs MP3 playback)

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stopTTSMetering()
            self?.stopBargeInMonitor()
            self?.finishSpeaking()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.finishSpeaking()
        }
    }

    private func finishSpeaking() {
        speakCompletion?()
        speakCompletion = nil
        audioPlayer = nil
        onReadyToListen?()
    }
}
