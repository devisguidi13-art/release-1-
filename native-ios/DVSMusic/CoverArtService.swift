import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Identifies a recording independently from its YouTube thumbnail/channel.
/// Never uses generative art: only an actual MusicBrainz-linked release cover.
enum CoverArtMatching {
    static func identity(_ track: MusicTrack) -> (artist: String, title: String)? {
        guard MusicMetadata.isMusic(track) else { return nil }
        var info = MusicMetadata.identity(for: track)
        // A reupload may identify its author as the uploader. For album lookup,
        // use the artist-title separator visible in the VIDEO TITLE when present.
        let normalizedTitle = track.title.replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
        if let separator = normalizedTitle.range(of: " - ") {
            let left = String(normalizedTitle[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(normalizedTitle[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if left.count >= 2 && left.count <= 55 && !right.isEmpty &&
                !["official", "lyrics", "audio", "video"].contains(MusicMetadata.normalized(left)) {
                info = (left, right)
            }
        }
        // A title made only of generic placeholders must not trigger a DB lookup.
        let artist = info.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = info.title.replacingOccurrences(
            of: "\\s*[\\(\\[][^\\)\\]]*(official|lyric|audio|video|visualizer)[^\\)\\]]*[\\)\\]]",
            with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard artist.count >= 2, title.count >= 2,
              !["youtube", "brano youtube", "unknown"].contains(MusicMetadata.normalized(artist)) else { return nil }
        return (artist, title)
    }

    /// Parse a MusicBrainz recording-search JSON response without assuming every
    /// record has release metadata. Reject wrong artists, covers, live releases,
    /// and compilation reissues when a genuine artist release exists.
    static func releaseGroupIDs(from data: Data, artist: String, title: String) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let recordings = root["recordings"] as? [[String: Any]] else { return [] }
        var ranked: [(String, Double)] = []
        for recording in recordings {
            guard let name = recording["title"] as? String,
                  MusicMetadata.titleMatch(title, candidate: name) >= 0.85 else { continue }
            let credits = (recording["artist-credit"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            let creditedNames: [String] = credits.flatMap { item -> [String] in
                var result = [item["name"] as? String].compactMap { $0 }
                if let artistObj = item["artist"] as? [String: Any], let name = artistObj["name"] as? String {
                    result.append(name)
                }
                return result
            }
            let expected = MusicMetadata.normalized(artist)
            let matchingCredit = creditedNames.contains { candidate in
                let actual = MusicMetadata.normalized(candidate)
                return actual == expected || actual.hasPrefix(expected + " feat") ||
                    expected.hasPrefix(actual + " feat")
            }
            guard matchingCredit else { continue }
            let recordScore = Double((recording["score"] as? Int) ?? 80) / 100
            for release in recording["releases"] as? [[String: Any]] ?? [] {
                guard let group = release["release-group"] as? [String: Any],
                      let groupID = group["id"] as? String,
                      UUID(uuidString: groupID) != nil else { continue }
                let secondary = (group["secondary-types"] as? [String] ?? []).map(MusicMetadata.normalized)
                if secondary.contains("live") || secondary.contains("compilation") || secondary.contains("remix") { continue }
                let primaryType = MusicMetadata.normalized(group["primary-type"] as? String ?? "")
                let groupName = group["title"] as? String ?? ""
                let isSingleForTrack = MusicMetadata.titleMatch(title, candidate: groupName) >= 0.85
                let status = MusicMetadata.normalized(release["status"] as? String ?? "")
                if ["bootleg", "pseudo-release"].contains(status) { continue }
                let typeScore = primaryType == "single" ? 12.0 : (primaryType == "album" ? 8.0 : 6.0)
                let score = recordScore * 100 + typeScore + (isSingleForTrack ? 25 : 0) +
                    (status == "official" ? 8 : 0)
                ranked.append((groupID, score))
            }
        }
        var seen = Set<String>()
        return ranked.sorted { $0.1 > $1.1 }.compactMap { seen.insert($0.0).inserted ? $0.0 : nil }
    }

    static func frontThumbnailURL(from data: Data) -> URL? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let images = root["images"] as? [[String: Any]],
              let front = images.first(where: { ($0["front"] as? Bool) == true }),
              let thumbnails = front["thumbnails"] as? [String: Any],
              let raw = (thumbnails["500"] ?? thumbnails["250"]) as? String,
              var parts = URLComponents(string: raw) else { return nil }
        if parts.scheme == "http" { parts.scheme = "https" }
        guard parts.scheme == "https", parts.host == "coverartarchive.org" ||
              parts.host?.hasSuffix(".coverartarchive.org") == true else { return nil }
        return parts.url
    }
}

/// Cache + request coalescing; album metadata loads separately from audio playback.
/// No paid API, no Apple promotional artwork licensing dependency.
actor CoverArtService {
    static let shared = CoverArtService()
    private var cache: [String: (Date, URL?)] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private var nextMusicBrainzRequest = Date.distantPast
    private var savedURLs: [String: String] = UserDefaults.standard.dictionary(forKey: "dvs-cover-art-v102") as? [String: String] ?? [:]

    func artworkURL(for track: MusicTrack) async -> URL? {
        guard let info = CoverArtMatching.identity(track) else { return nil }
        let key = MusicMetadata.canonicalKey(artist: info.artist, title: info.title)
        if let value = cache[key], value.0 > Date() { return value.1 }
        if let saved = savedURLs[key], let address = URL(string: saved), address.scheme == "https" {
            return address
        }
        if let task = inflight[key] { return await task.value }
        let task = Task<URL?, Never> { [self] in
            await lookup(artist: info.artist, title: info.title)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        cache[key] = (Date().addingTimeInterval(result == nil ? 2 * 3600 : 30 * 86400), result)
        if let result {
            savedURLs[key] = result.absoluteString
            if savedURLs.count > 200 { savedURLs = [key: result.absoluteString] }
            UserDefaults.standard.set(savedURLs, forKey: "dvs-cover-art-v102")
        }
        if cache.count > 350 { cache.removeAll(keepingCapacity: true) }
        return result
    }

    private func lookup(artist: String, title: String) async -> URL? {
        guard var parts = URLComponents(string: "https://musicbrainz.org/ws/2/recording/") else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(title)\" AND artist:\"\(artist)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let address = parts.url else { return nil }
        // MusicBrainz requires <= 1 request/second per app; reserve each slot
        // BEFORE awaiting so actor re-entrancy cannot create a burst.
        let scheduled = max(Date(), nextMusicBrainzRequest)
        nextMusicBrainzRequest = scheduled.addingTimeInterval(1.2)
        let delay = scheduled.timeIntervalSinceNow
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        guard !Task.isCancelled else { return nil }
        var request = URLRequest(url: address)
        request.timeoutInterval = 7
        request.setValue("DVS-Music/1.0.2 (personal music metadata client)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let candidates = CoverArtMatching.releaseGroupIDs(from: data, artist: artist, title: title)
        for id in candidates.prefix(3) {
            guard !Task.isCancelled, let url = URL(string: "https://coverartarchive.org/release-group/\(id)") else { return nil }
            var coverRequest = URLRequest(url: url)
            coverRequest.timeoutInterval = 5
            coverRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (coverData, response) = try? await URLSession.shared.data(for: coverRequest),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let imageURL = CoverArtMatching.frontThumbnailURL(from: coverData) {
                return imageURL
            }
        }
        return nil
    }
}
