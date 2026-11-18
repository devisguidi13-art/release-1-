import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct LastFMSimilarTrack {
    let artist: String
    let title: String
    let match: Double
}

private actor LastFMCache {
    static let shared = LastFMCache()
    private var stored: [String: (Date, [LastFMSimilarTrack])] = [:]
    func get(_ key: String) -> [LastFMSimilarTrack]? {
        guard let found = stored[key], Date().timeIntervalSince(found.0) < 12 * 3600 else { return nil }
        return found.1
    }
    func set(_ key: String, tracks: [LastFMSimilarTrack]) {
        stored[key] = (Date(), tracks)
        if stored.count > 120 { stored = stored.filter { Date().timeIntervalSince($0.value.0) < 3600 } }
    }
}

/// Optional personal API key: no paid model, no bundled credentials and no secret logs.
struct LastFMService {
    private struct Response: Decodable {
        struct Similar: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                let name: String
                let artist: Artist
                let match: String?
            }
            let track: [Item]?
        }
        let similartracks: Similar?
    }

    func similar(to track: MusicTrack, apiKey: String) async -> [LastFMSimilarTrack] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let identity = MusicMetadata.identity(for: track)
        guard !identity.artist.isEmpty && MusicMetadata.normalized(identity.artist) != "youtube" else { return [] }
        let cacheKey = key + "|" + MusicMetadata.canonicalKey(track)
        if let cached = await LastFMCache.shared.get(cacheKey) { return cached }
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        components.queryItems = [
            URLQueryItem(name: "method", value: "track.getSimilar"),
            URLQueryItem(name: "artist", value: identity.artist),
            URLQueryItem(name: "track", value: identity.title),
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "autocorrect", value: "1"),
            URLQueryItem(name: "limit", value: "35"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        var deduped: [LastFMSimilarTrack] = []
        var seen: Set<String> = []
        for item in decoded.similartracks?.track ?? [] {
            let canonical = MusicMetadata.canonicalKey(artist: item.artist.name, title: item.name)
            guard !item.artist.name.isEmpty, !item.name.isEmpty, seen.insert(canonical).inserted else { continue }
            deduped.append(LastFMSimilarTrack(artist: item.artist.name, title: item.name,
                                               match: min(1, max(0, Double(item.match ?? "0") ?? 0))))
        }
        await LastFMCache.shared.set(cacheKey, tracks: deduped)
        return deduped
    }
}
