import AVFoundation
import Combine
import Foundation
import Speech

/// Dictation only runs after the user taps the microphone button.
@MainActor
final class VoiceSearchService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorText: String? = nil
    @Published private(set) var finishedText: String? = nil

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    var onStopped: (() -> Void)?

    func start() {
        guard !isListening else { stop(); return }
        errorText = nil
        transcript = ""
        finishedText = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.errorText = "Consenti il riconoscimento vocale dalle Impostazioni iOS."
                    self.onStopped?()
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] permitted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if permitted { self.begin() }
                        else {
                            self.errorText = "Consenti l'accesso al microfono dalle Impostazioni iOS."
                            self.onStopped?()
                        }
                    }
                }
            }
        }
    }

    private func begin() {
        guard recognizer?.isAvailable == true else {
            errorText = "Dettatura non disponibile in questo momento."
            onStopped?()
            return
        }
        let audioEngine = AVAudioEngine()
        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        speechRequest.shouldReportPartialResults = true
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audio.setActive(true)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                speechRequest.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            engine = audioEngine
            request = speechRequest
            isListening = true
            task = recognizer?.recognitionTask(with: speechRequest) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil {
                        if let error, self.transcript.isEmpty { self.errorText = error.localizedDescription }
                        self.stop()
                    }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 13_000_000_000)
                if !Task.isCancelled { self?.stop() }
            }
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            errorText = "Microfono non disponibile: \(error.localizedDescription)"
            restorePlaybackSession()
            onStopped?()
        }
    }

    func stop() {
        timeout?.cancel(); timeout = nil
        guard engine != nil || isListening else { return }
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil; request = nil; engine = nil
        isListening = false
        if !value.isEmpty { finishedText = value }
        restorePlaybackSession()
        onStopped?()
    }

    private func restorePlaybackSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .default)
        try? audio.setActive(true)
    }
}
