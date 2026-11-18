import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Existing public catalog lookup. Sources are independent and may be unavailable/rate-limited.
/// Concurrent requests avoid the previous 4 x 12 s worst-case serial wait.
private actor CatalogCache {
    static let shared = CatalogCache()
    private var searches: [String: (Date, [MusicTrack])] = [:]
    private var related: [String: (Date, [MusicTrack])] = [:]
    func search(_ key: String) -> [MusicTrack]? {
        guard let e = searches[key], Date().timeIntervalSince(e.0) < 25 * 60 else { return nil }
        return e.1
    }
    func suggest(_ key: String) -> [MusicTrack]? {
        guard let e = related[key], Date().timeIntervalSince(e.0) < 25 * 60 else { return nil }
        return e.1
    }
    func putSearch(_ key: String, _ tracks: [MusicTrack]) {
        searches[key] = (Date(), tracks)
        if searches.count > 180 { searches.removeAll() }
    }
    func putSuggest(_ key: String, _ tracks: [MusicTrack]) {
        related[key] = (Date(), tracks)
        if related.count > 120 { related.removeAll() }
    }
}

struct CatalogService {
    private let instances = [
        "https://inv.nadeko.net", "https://invidious.nerdvpn.de",
        "https://yt.chocolatemoo53.com", "https://invidious.tiekoetter.com"
    ]

    func search(_ text: String, preferOfficial: Bool = true) async throws -> [MusicTrack] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if let videoID = Self.videoID(from: query) {
            return [MusicTrack(id: videoID, title: "Brano YouTube", artist: "YouTube", duration: 0)]
        }
        let cacheKey = MusicMetadata.normalized(query)
        if let cached = await CatalogCache.shared.search(cacheKey) {
            return OfficialCatalog.order(cached, query: query, preferOfficial: preferOfficial)
        }
        // Search the ordinary query and a targeted music-distribution query in
        // parallel. A Topic/VEVO match should win over a random user reupload,
        // but no remote verification badge is implied by a channel's text name.
        let directed = MusicMetadata.normalized(query).contains("topic") ? query : query + " topic"
        let searches = preferOfficial ? [query, directed] : [query]
        let tracks = await withTaskGroup(of: [MusicTrack].self, returning: [MusicTrack].self) { group in
            for instance in instances {
                for text in searches {
                    group.addTask {
                        guard var components = URLComponents(string: instance + "/api/v1/search") else { return [] }
                        components.queryItems = [URLQueryItem(name: "q", value: text),
                                                 URLQueryItem(name: "type", value: "video"),
                                                 URLQueryItem(name: "region", value: "IT")]
                        guard let url = components.url,
                              let videos: [InvidiousVideo] = try? await fetch(url) else { return [] }
                        return unique(videos.compactMap { $0.asTrack() })
                    }
                }
            }
            var fallback: [MusicTrack] = []
            for await response in group where !response.isEmpty {
                fallback.append(contentsOf: response)
                let sorted = OfficialCatalog.order(fallback, query: query, preferOfficial: preferOfficial)
                // Early exit only when the track is genuinely relevant AND has a
                // strong music distributor channel hint (Topic or matched VEVO).
                if !preferOfficial || sorted.first.map({
                    OfficialCatalog.sourceConfidence($0) >= 90 &&
                    OfficialCatalog.queryRelevance($0, query: query) >= 0.94
                }) == true {
                    group.cancelAll()
                    return sorted
                }
            }
            return OfficialCatalog.order(fallback, query: query, preferOfficial: preferOfficial)
        }
        if tracks.isEmpty { throw CatalogError.serviceUnavailable }
        await CatalogCache.shared.putSearch(cacheKey, tracks)
        return tracks
    }

    static func videoID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoID(text) { return text }
        guard let url = URLComponents(string: text), let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let candidate: String?
        if ["youtu.be", "www.youtu.be"].contains(host) { candidate = parts.first }
        else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
                 "youtube-nocookie.com", "www.youtube-nocookie.com"].contains(host) {
            if url.path == "/watch" { candidate = url.queryItems?.first(where: { $0.name == "v" })?.value }
            else if parts.count >= 2 && ["shorts", "embed", "live"].contains(parts[0]) { candidate = parts[1] }
            else { candidate = nil }
        } else { candidate = nil }
        return candidate.flatMap { isVideoID($0) ? $0 : nil }
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.count == 11 && value.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(String(scalar)) || ("a"..."z").contains(String(scalar)) ||
            ("0"..."9").contains(String(scalar)) || scalar == "-" || scalar == "_"
        }
    }

    func suggested(near track: MusicTrack) async -> [MusicTrack] {
        if let cached = await CatalogCache.shared.suggest(track.id) { return cached }
        let tracks = await withTaskGroup(of: [MusicTrack].self, returning: [MusicTrack].self) { group in
            for instance in instances {
                group.addTask {
                    guard let url = URL(string: "\(instance)/api/v1/videos/\(track.id)"),
                          let detail: InvidiousVideoDetail = try? await fetch(url) else { return [] }
                    return unique((detail.recommendedVideos ?? []).compactMap { $0.asTrack() })
                }
            }
            for await result in group where !result.isEmpty {
                group.cancelAll()
                return result
            }
            return []
        }
        if !tracks.isEmpty { await CatalogCache.shared.putSuggest(track.id, tracks) }
        return tracks
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CatalogError.serviceUnavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func unique(_ tracks: [MusicTrack]) -> [MusicTrack] {
        var ids: Set<String> = []
        return tracks.filter { ids.insert($0.id).inserted }
    }
}

enum CatalogError: LocalizedError {
    case noResults, serviceUnavailable
    var errorDescription: String? {
        switch self {
        case .noResults: return "Nessun brano trovato. Prova con artista e titolo."
        case .serviceUnavailable: return "Catalogo momentaneamente non disponibile. Riprovare più tardi."
        }
    }
}
