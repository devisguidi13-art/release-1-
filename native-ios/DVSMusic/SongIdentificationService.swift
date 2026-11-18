import AVFoundation
import Combine
import Foundation
import ShazamKit

/// ShazamKit uses the device microphone; it does not extract the app's stream.
final class SongIdentificationService: NSObject, ObservableObject, SHSessionDelegate {
    @Published private(set) var listening = false
    @Published private(set) var status = ""
    @Published private(set) var identifiedQuery: String? = nil
    private var engine: AVAudioEngine?
    private var session: SHSession?
    private var timeout: Task<Void, Never>?
    var onStopped: (() -> Void)?

    func start() {
        if listening { stop(); return }
        identifiedQuery = nil
        status = "Richiesta accesso al microfono..."
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if allowed { self.begin() }
                else {
                    self.status = "Microfono negato. Attivalo nelle Impostazioni."
                    self.onStopped?()
                }
            }
        }
    }

    private func begin() {
        let engine = AVAudioEngine()
        let session = SHSession()
        session.delegate = self
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default)
            try audio.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak session] buffer, time in
                session?.matchStreamingBuffer(buffer, at: time)
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.session = session
            self.listening = true
            self.status = "Ascolto la musica intorno a te..."
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 22_000_000_000)
                if !Task.isCancelled, let self, self.listening {
                    self.stop()
                    self.status = "Nessun brano riconosciuto. Riprova."
                }
            }
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            status = "Impossibile ascoltare: \(error.localizedDescription)"
            restorePlaybackSession()
            onStopped?()
        }
    }

    func stop() {
        timeout?.cancel(); timeout = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        session?.delegate = nil
        session = nil
        listening = false
        restorePlaybackSession()
        onStopped?()
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let media = match.mediaItems.first, let title = media.title else { return }
        let query = [media.artist, title].compactMap { $0 }.joined(separator: " ")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.listening else { return }
            self.stop()
            self.identifiedQuery = query
            self.status = "Trovato: \(media.artist ?? "") — \(title)"
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.listening else { return }
            self.stop()
            self.status = error?.localizedDescription ?? "Brano non riconosciuto. Riprova."
        }
    }

    private func restorePlaybackSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .default)
        try? audio.setActive(true)
    }
}
