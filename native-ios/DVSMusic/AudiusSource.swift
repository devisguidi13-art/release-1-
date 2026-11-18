import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Official public Audius catalog. Only tracks exposed as streamable by the API
/// are considered. No embeds, scraped endpoints, foreign players or secret keys.
struct AudiusSource {
    enum APIError: Error { case unavailable }

    private struct Response: Decodable { let data: [Entry] }
    private struct Entry: Decodable {
        let id: String
        let title: String
        let duration: Int?
        let user: User?
        let artwork: Artwork?
        let isStreamable: Bool?
        let isUnlisted: Bool?
        enum CodingKeys: String, CodingKey {
            case id, title, duration, user, artwork
            case isStreamable = "is_streamable"
            case isUnlisted = "is_unlisted"
        }
    }
    private struct User: Decodable { let name: String? }
    private struct Artwork: Decodable {
        let small: String?
        let medium: String?
        let large: String?
        enum CodingKeys: String, CodingKey {
            case small = "150x150", medium = "480x480", large = "1000x1000"
        }
    }

    static func streamURL(for track: MusicTrack) -> URL? {
        guard track.isAudius,
              !track.providerID.isEmpty,
              track.providerID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else { return nil }
        var url = URLComponents(string: "https://api.audius.co/v1/tracks/\(track.providerID)/stream")!
        url.queryItems = [URLQueryItem(name: "app_name", value: "DVS_Music")]
        return url.url
    }

    func search(_ query: String, limit: Int = 30) async throws -> [MusicTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var parts = URLComponents(string: "https://api.audius.co/v1/tracks/search")!
        parts.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 40)))),
            URLQueryItem(name: "app_name", value: "DVS_Music")
        ]
        guard let url = parts.url else { throw APIError.unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 3_000_000 else { throw APIError.unavailable }
        return Self.parse(data: data)
    }

    /// Parse is separate to permit deterministic offline tests.
    static func parse(data: Data) -> [MusicTrack] {
        guard let found = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        var seen = Set<String>()
        return found.data.compactMap { entry in
            guard entry.isStreamable != false, entry.isUnlisted != true,
                  let artist = entry.user?.name, !artist.isEmpty,
                  entry.duration == nil || ((entry.duration ?? 0) >= 65 && (entry.duration ?? 0) <= 660),
                  seen.insert(entry.id).inserted else { return nil }
            let track = MusicTrack(id: "audius:" + entry.id, title: entry.title,
                artist: artist, duration: entry.duration ?? 0,
                artworkLink: entry.artwork?.large ?? entry.artwork?.medium ?? entry.artwork?.small)
            return MusicMetadata.isMusic(track) ? track : nil
        }
    }

    /// Never swap a mainstream original for a similarly named remix or unrelated upload.
    static func exactMatch(to original: MusicTrack, among choices: [MusicTrack]) -> MusicTrack? {
        let wanted = MusicMetadata.identity(for: original)
        let artist = MusicMetadata.normalized(wanted.artist)
        guard !artist.isEmpty && artist != "youtube" else { return nil }
        return choices.filter { choice in
            let info = MusicMetadata.identity(for: choice)
            let candidateArtist = MusicMetadata.normalized(info.artist)
            let isArtist = candidateArtist == artist ||
                candidateArtist.replacingOccurrences(of: " ", with: "") == artist.replacingOccurrences(of: " ", with: "")
            let isTitle = MusicMetadata.titleMatch(wanted.title, candidate: info.title) >= 0.91
            let saneDuration = original.duration == 0 || choice.duration == 0 ||
                abs(original.duration - choice.duration) <= 12
            let text = MusicMetadata.normalized(info.title)
            let unwanted = ["remix", "cover", "sped up", "slowed", "nightcore", "live", "karaoke"]
            return isArtist && isTitle && saneDuration && !unwanted.contains(where: { text.contains($0) })
        }.first
    }
}

/// Unified search: YouTube Music song metadata, ordinary YouTube results and
/// optional Audius results. Both YouTube searches resolve through the existing
/// YouTubeKit path; this is not a second licensed YouTube audio provider.
struct MultiSourceCatalog {
    private let youtubeMusic = YouTubeMusicCatalog()
    private let youtube = CatalogService()
    private let audius = AudiusSource()

    func search(_ query: String, preferOfficial: Bool = true) async throws -> [MusicTrack] {
        if let id = CatalogService.videoID(from: query) {
            return [MusicTrack(id: id, title: "Brano YouTube", artist: "YouTube", duration: 0)]
        }
        async let music: [MusicTrack] = (try? await youtubeMusic.search(query)) ?? []
        async let videos: [MusicTrack] = (try? await youtube.search(query, preferOfficial: preferOfficial)) ?? []
        async let independent: [MusicTrack] = (try? await audius.search(query)) ?? []
        let (songs, videosFound, audiusFound) = await (music, videos, independent)
        // Song-first matching. Audius is retained for niche/indie tracks, not
        // presented as a replacement for the major-label catalog.
        let combined = songs + videosFound + audiusFound
        guard !combined.isEmpty else { throw CatalogError.serviceUnavailable }
        return OfficialCatalog.order(combined, query: query, preferOfficial: preferOfficial)
    }

    func alternative(to track: MusicTrack) async -> MusicTrack? {
        let metadata = MusicMetadata.identity(for: track)
        guard !metadata.artist.isEmpty, !metadata.title.isEmpty,
              MusicMetadata.normalized(metadata.artist) != "youtube" else { return nil }
        let query = metadata.artist + " " + metadata.title
        // First try a *different video ID* of the same recording. This is much
        // more useful for mainstream music than depending only on Audius.
        async let music: [MusicTrack] = (try? await youtubeMusic.search(query)) ?? []
        async let videos: [MusicTrack] = (try? await youtube.search(query)) ?? []
        let (songs, videoResults) = await (music, videos)
        // Do not canonical-deduplicate here: that would discard alternate
        // video IDs for the SAME recording, defeating the fallback entirely.
        var uniqueIDs = Set<String>()
        let candidates = (songs + videoResults)
            .filter { uniqueIDs.insert($0.id).inserted }
            .filter { Self.sameRecording(track, $0) }
            .sorted {
                let a = OfficialCatalog.sourceConfidence($0)
                let b = OfficialCatalog.sourceConfidence($1)
                return a == b ? $0.id < $1.id : a > b
            }
        if let match = candidates.first { return match }
        guard !track.isAudius else { return nil }
        let other = (try? await audius.search(query, limit: 35)) ?? []
        return AudiusSource.exactMatch(to: track, among: other)
    }

    /// Reject unrelated versions even when their search keywords look similar.
    /// A text/duration check is not acoustic fingerprinting, so it is conservative.
    static func sameRecording(_ original: MusicTrack, _ candidate: MusicTrack) -> Bool {
        guard original.id != candidate.id,
              MusicMetadata.isMusic(candidate),
              !candidate.isAudius else { return false }
        let wanted = MusicMetadata.identity(for: original)
        let found = MusicMetadata.identity(for: candidate)
        guard MusicMetadata.titleMatch(wanted.title, candidate: found.title) >= 0.91,
              MusicMetadata.artistMatch(wanted.artist, candidate: candidate) ||
                MusicMetadata.normalized(found.artist) == MusicMetadata.normalized(wanted.artist),
              original.duration == 0 || candidate.duration == 0 ||
                abs(original.duration - candidate.duration) <= 10 else { return false }
        let modifiers = ["remix", "live", "slowed", "sped up", "nightcore", "acoustic",
                         "karaoke", "instrumental", "cover", "extended", "radio edit"]
        let oldTitle = MusicMetadata.normalized(wanted.title)
        let newTitle = MusicMetadata.normalized(found.title)
        return modifiers.allSatisfy { oldTitle.contains($0) == newTitle.contains($0) }
    }
}
