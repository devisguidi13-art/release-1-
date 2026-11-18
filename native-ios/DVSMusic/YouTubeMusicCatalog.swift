import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Music-first search, inspired by SimpMusic's separation of a YouTube Music
/// catalog from the audio player. This is an independently written Swift client,
/// NOT SimpMusic's Kotlin code. The YouTube Music web endpoint is unofficial:
/// it may change, decline requests, or be unavailable without notice.
struct YouTubeMusicCatalog {
    enum SearchError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Ricerca YouTube Music temporaneamente non disponibile." }
    }

    private actor WebConfigurationCache {
        static let shared = WebConfigurationCache()
        private var value: (key: String, version: String, date: Date)?

        func configuration() async throws -> (key: String, version: String) {
            if let value, Date().timeIntervalSince(value.date) < 3 * 3600 {
                return (value.key, value.version)
            }
            guard let url = URL(string: "https://music.youtube.com/") else { throw SearchError.unavailable }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("it-IT,it;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count < 4_000_000,
                  let html = String(data: data, encoding: .utf8),
                  let config = YouTubeMusicCatalog.configurationFromHTML(html) else { throw SearchError.unavailable }
            let fresh = (config.key, config.version, Date())
            value = fresh
            return (fresh.0, fresh.1)
        }
    }

    /// Read only the dynamically published web-client configuration.
    /// This endpoint has no stability guarantee and requires no user account.
    static func configurationFromHTML(_ html: String) -> (key: String, version: String)? {
        func find(_ key: String) -> String? {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "\"" + escaped + "\"\\s*:\\s*\"([^\"]+)\""
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
        guard let key = find("INNERTUBE_API_KEY"),
              let version = find("INNERTUBE_CLIENT_VERSION") ?? find("INNERTUBE_CONTEXT_CLIENT_VERSION"),
              !key.isEmpty, key.count < 160, !version.isEmpty, version.count < 90 else { return nil }
        return (key, version)
    }

    func search(_ query: String) async throws -> [MusicTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let config = try await WebConfigurationCache.shared.configuration()
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "key", value: config.key),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]
        guard let url = components.url else { throw SearchError.unavailable }
        let payload: [String: Any] = [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": config.version,
                                    "hl": "it", "gl": "IT"]],
            "query": trimmed
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(config.version, forHTTPHeaderField: "X-Youtube-Client-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 5_000_000 else { throw SearchError.unavailable }
        return Self.parse(data: data)
    }

    /// Handles nested search shelves without depending on the exact position of
    /// one renderer. Only playable song/video rows can become DVS tracks.
    static func parse(data: Data) -> [MusicTrack] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var rows: [[String: Any]] = []
        collectRows(in: root, depth: 0, into: &rows)
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let track = parseRow(row), seen.insert(track.id).inserted else { return nil }
            return track
        }.prefix(60).map { $0 }
    }

    private static func collectRows(in node: Any, depth: Int, into rows: inout [[String: Any]]) {
        guard depth <= 22 && rows.count < 150 else { return }
        if let object = node as? [String: Any] {
            if let row = object["musicResponsiveListItemRenderer"] as? [String: Any] {
                rows.append(row)
                return
            }
            // Search trees can contain huge tracking structures. We traverse
            // only renderer-bearing containers and skip logging/telemetry.
            for (key, child) in object where !key.lowercased().contains("tracking") {
                if child is [String: Any] || child is [Any] {
                    collectRows(in: child, depth: depth + 1, into: &rows)
                }
            }
        } else if let array = node as? [Any] {
            for child in array.prefix(120) { collectRows(in: child, depth: depth + 1, into: &rows) }
        }
    }

    private static func parseRow(_ row: [String: Any]) -> MusicTrack? {
        guard let columns = row["flexColumns"] as? [[String: Any]],
              let first = columns.first,
              let title = textRuns(from: first).first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let second = columns.dropFirst().flatMap { textRuns(from: $0) }
        let pieces = second.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "•" && $0 != "·" }
        let artist = pieces.first(where: { !["song", "brano", "video", "album", "singolo", "single"]
            .contains(MusicMetadata.normalized($0)) && durationSeconds($0) == nil }) ?? ""
        guard !artist.isEmpty else { return nil }
        let duration = pieces.compactMap(durationSeconds).first ?? 0
        let id = (row["playlistItemData"] as? [String: Any])?["videoId"] as? String
            ?? videoID(in: first)
            ?? videoID(in: row)
        guard let id, validVideoID(id) else { return nil }
        let thumbnails = (((row["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let artwork = thumbnails.last?["url"] as? String
        let track = MusicTrack(id: id, title: title, artist: artist, duration: duration,
                               artworkLink: artwork?.hasPrefix("https://") == true ? artwork : nil,
                               catalogOrigin: "youtube-music")
        return MusicMetadata.isMusic(track) ? track : nil
    }

    private static func textRuns(from column: [String: Any]) -> [String] {
        guard let container = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = container["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return [] }
        return runs.compactMap { $0["text"] as? String }
    }

    private static func videoID(in value: Any, depth: Int = 0) -> String? {
        guard depth < 11 else { return nil }
        if let object = value as? [String: Any] {
            if let watch = object["watchEndpoint"] as? [String: Any],
               let id = watch["videoId"] as? String, validVideoID(id) { return id }
            for (key, child) in object where !key.lowercased().contains("tracking") {
                if let id = videoID(in: child, depth: depth + 1) { return id }
            }
        } else if let array = value as? [Any] {
            for item in array.prefix(40) {
                if let id = videoID(in: item, depth: depth + 1) { return id }
            }
        }
        return nil
    }

    private static func validVideoID(_ value: String) -> Bool {
        value.count == 11 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
        }
    }

    private static func durationSeconds(_ text: String) -> Int? {
        let pieces = text.split(separator: ":")
        guard (2...3).contains(pieces.count),
              pieces.allSatisfy({ $0.count >= 1 && $0.count <= 2 && $0.allSatisfy(\.isNumber) }) else { return nil }
        var seconds = 0
        for value in pieces {
            guard let number = Int(value), number < 60 || (seconds == 0 && value == pieces.first) else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds > 0 && seconds <= 10 * 60 ? seconds : nil
    }
}
