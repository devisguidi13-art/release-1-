import AVFoundation
import Foundation
import YouTubeKit

/// Previously resolved stream URLs can be reused for nearby queue items. Signed URLs
/// are temporary: never persist them to disk or assume they remain valid indefinitely.
private actor StreamURLCache {
    static let shared = StreamURLCache()
    private var items: [String: (URL, Date)] = [:]
    func get(_ id: String) -> URL? {
        guard let value = items[id], Date().timeIntervalSince(value.1) < 8 * 60 else { return nil }
        return value.0
    }
    func put(_ id: String, url: URL) {
        items[id] = (url, Date())
        if items.count > 90 { items.removeAll() }
    }
}

/// Retains the existing (unofficial) iPhone audio resolver used by 0.8.
/// A resolved URL does not guarantee that the origin will start buffering instantly.
struct AudioResolver {
    enum ResolveError: LocalizedError {
        case noAudio
        var errorDescription: String? {
            "La sorgente non ha fornito uno stream audio compatibile per questo brano."
        }
    }

    func playerItem(for track: MusicTrack) async throws -> AVPlayerItem {
        let url: URL
        if track.isAudius {
            guard let direct = AudiusSource.streamURL(for: track) else { throw ResolveError.noAudio }
            let item = AVPlayerItem(url: direct)
            item.preferredForwardBufferDuration = 5
            return item
        }
        if let cached = await StreamURLCache.shared.get(track.id) {
            url = cached
        } else {
            let streams = try await YouTube(videoID: track.id).streams
            guard let stream = streams
                .filterAudioOnly()
                .filter({ $0.isNativelyPlayable })
                .highestAudioBitrateStream() else {
                throw ResolveError.noAudio
            }
            url = stream.url
            await StreamURLCache.shared.put(track.id, url: url)
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5
        return item
    }
}
