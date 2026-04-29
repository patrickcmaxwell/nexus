import AVFoundation
import Speech
import Foundation
import AVFAudio

class EveVoiceManager: NSObject, AVSpeechSynthesizerDelegate {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    var onTranscriptFinal: ((String) -> Void)?
    var onTranscriptPartial: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onReadyToListen: (() -> Void)?

    private var speakCompletion: (() -> Void)?
    private var latestPartial = ""

    // Silence detection — main-thread timer samples lastSpeechTime every 200ms
    private var lastSpeechTime: Date = Date()
    private var firstSpeechTime: Date? = nil      // set when first voice activity detected
    private var silenceWatchdog: Timer?
    private let silenceThreshold: Float = 0.012   // raw RMS below this = silence
    private let silenceDelay: TimeInterval = 2.2  // seconds of silence before auto-submit
    private let minSpeakDuration: TimeInterval = 1.0  // must have spoken for at least this long

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Listening

    func startListening() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else { return }
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                guard status == .authorized else { return }
                DispatchQueue.main.async { self?.beginRecognition() }
            }
        }
    }

    private func beginRecognition() {
        stopEngine()

        latestPartial = ""
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
                        self?.onAudioLevel?(0)
                        if !text.isEmpty { self?.onTranscriptFinal?(text) }
                    }
                    self?.stopEngine()
                } else if !text.isEmpty {
                    self?.latestPartial = text
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
        let silentFor = Date().timeIntervalSince(lastSpeechTime)
        if silentFor >= silenceDelay {
            submitPartialAndStop()
        }
    }

    private func submitPartialAndStop() {
        let pending = latestPartial
        latestPartial = ""
        stopEngine()
        onAudioLevel?(0)
        if !pending.isEmpty { onTranscriptFinal?(pending) }
    }

    func stopListening() {
        let pending = latestPartial
        latestPartial = ""
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

    func speak(_ text: String, completion: @escaping () -> Void) {
        synthesizer.stopSpeaking(at: .immediate)
        speakCompletion = completion

        let clean = text
            .replacingOccurrences(of: #"\*\*|__|_|\*|`"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let utterance = AVSpeechUtterance(string: String(clean.prefix(600)))

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
        speakCompletion?()
        speakCompletion = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.speakCompletion?()
            self?.speakCompletion = nil
            self?.onReadyToListen?()
        }
    }
}
