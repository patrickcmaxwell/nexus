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
    private let silenceThreshold: Float = 0.010   // raw RMS below this = silence
    private let shortPauseDelay: TimeInterval = 1.0    // sentence-final punctuation
    private let mediumPauseDelay: TimeInterval = 1.4
    private let longPauseDelay: TimeInterval = 1.9
    private let connectorPauseDelay: TimeInterval = 2.4   // trailing "and", "but", "so", etc.
    private let minSpeakDuration: TimeInterval = 0.5     // must have spoken for at least this long
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

        latestPartial = ""
        lastTranscriptUpdate = Date()
        lastSpeechTime = Date()
        firstSpeechTime = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

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

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    DispatchQueue.main.async {
                        self?.latestPartial = ""
                        self?.lastTranscriptUpdate = Date()
                        self?.onAudioLevel?(0)
                        if !text.isEmpty { self?.onTranscriptFinal?(text) }
                    }
                    self?.stopEngine()
                } else if !text.isEmpty {
                    self?.latestPartial = text
                    self?.lastTranscriptUpdate = Date()
                    DispatchQueue.main.async { self?.onTranscriptPartial?(text) }
                }
            }
            if error != nil { self?.stopEngine() }
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
        let pending = latestPartial
        latestPartial = ""
        lastTranscriptUpdate = Date()
        stopEngine()
        onAudioLevel?(0)
        if !pending.isEmpty { onTranscriptFinal?(pending) }
    }

    func stopListening() {
        let pending = latestPartial
        latestPartial = ""
        lastTranscriptUpdate = Date()
        stopEngine()
        onAudioLevel?(0)
        if !pending.isEmpty {
            DispatchQueue.main.async { self.onTranscriptFinal?(pending) }
        }
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
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            // If the data isn't playable, fall back to system speech with a generic
            fallbackSystemSpeak("Voice playback failed.")
        }
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
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        speakCompletion?()
        speakCompletion = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.finishSpeaking()
        }
    }

    // MARK: - AVAudioPlayerDelegate (for ElevenLabs MP3 playback)

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
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
