import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Genre categories shared by the entire UI. New categories only require a descriptor,
/// never a separate implementation of charts or refresh logic.
struct DVSGenre: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let searchTerms: [String]
    let genreHints: [String]
    let artistHints: [String]

    static let all: [DVSGenre] = [
        .init(id: "trap-it", title: "Trap italiana", searchTerms: ["trap italiana", "sfera ebbasta", "shiva rapper"], genreHints: ["hip-hop", "rap", "trap"], artistHints: ["sfera ebbasta", "shiva", "lazza", "capo plaza", "paky", "baby gang", "geolier", "tedua", "tony effe", "ghali"]),
        .init(id: "trap-world", title: "Trap internazionale", searchTerms: ["trap music", "future rapper", "travis scott"], genreHints: ["hip-hop", "rap", "trap"], artistHints: ["future", "travis scott", "young thug", "21 savage", "metro boomin", "gunna", "don toliver", "lil baby"]),
        .init(id: "hiphop", title: "Hip hop / Rap", searchTerms: ["hip hop", "rap hits"], genreHints: ["hip-hop", "rap"], artistHints: []),
        .init(id: "indie", title: "Indie", searchTerms: ["indie music", "indie rock"], genreHints: ["indie", "alternative"], artistHints: []),
        .init(id: "pop", title: "Pop", searchTerms: ["pop music"], genreHints: ["pop"], artistHints: []),
        .init(id: "rnb", title: "R&B / Soul", searchTerms: ["r&b soul", "r&b"], genreHints: ["r&b", "soul", "rhythm and blues"], artistHints: []),
        .init(id: "rock", title: "Rock", searchTerms: ["rock music"], genreHints: ["rock"], artistHints: []),
        .init(id: "techno", title: "Techno", searchTerms: ["techno music", "techno"], genreHints: ["techno", "electronic", "dance"], artistHints: []),
        .init(id: "reggaeton", title: "Reggaeton", searchTerms: ["reggaeton", "latin urbano"], genreHints: ["reggaeton", "urbano latino", "latin"], artistHints: []),
        .init(id: "lofi", title: "Lo-fi", searchTerms: ["lo-fi hip hop", "lofi beats"], genreHints: ["lo-fi", "chillhop", "downtempo", "hip-hop"], artistHints: []),
        .init(id: "chill", title: "Chill", searchTerms: ["chill electronic", "chill music"], genreHints: ["chill", "ambient", "downtempo", "electronic"], artistHints: []),
        .init(id: "dance", title: "Dance / EDM", searchTerms: ["dance edm", "electronic dance"], genreHints: ["dance", "electronic", "house"], artistHints: []),
        .init(id: "house", title: "House", searchTerms: ["house music"], genreHints: ["house", "dance", "electronic"], artistHints: []),
        .init(id: "latin", title: "Latin", searchTerms: ["latin music", "musica latina"], genreHints: ["latin", "latino", "urbano"], artistHints: []),
        .init(id: "jazz", title: "Jazz", searchTerms: ["jazz"], genreHints: ["jazz"], artistHints: []),
        .init(id: "metal", title: "Metal", searchTerms: ["heavy metal", "metal music"], genreHints: ["metal", "hard rock"], artistHints: []),
        .init(id: "classical", title: "Classica", searchTerms: ["classical music"], genreHints: ["classical", "classica"], artistHints: []),
        .init(id: "country", title: "Country", searchTerms: ["country music"], genreHints: ["country"], artistHints: []),
        .init(id: "kpop", title: "K-Pop", searchTerms: ["k-pop"], genreHints: ["k-pop", "korean pop"], artistHints: []),
        .init(id: "afrobeats", title: "Afrobeats", searchTerms: ["afrobeats"], genreHints: ["afrobeats", "afro-pop", "afrobeat"], artistHints: [])
    ]

    /// Never infer niche genres from broad labels alone (e.g. all Hip-Hop is not Trap).
    func matches(genre: String, artist: String, title: String) -> Bool {
        let g = normalized(genre), a = normalized(artist), t = normalized(title)
        if !artistHints.isEmpty { return artistHints.contains { a.contains($0) } || g.contains("trap") }
        if id == "lofi" { return g.contains("lo-fi") || g.contains("chillhop") || t.contains("lofi") || t.contains("lo-fi") }
        if id == "chill" { return g.contains("chill") || g.contains("ambient") || g.contains("downtempo") }
        if id == "techno" { return g.contains("techno") || t.contains("techno") }
        if id == "reggaeton" { return g.contains("reggaeton") || g.contains("urbano") }
        if id == "house" { return g.contains("house") }
        if id == "kpop" { return g.contains("k-pop") || g.contains("korean pop") }
        if id == "afrobeats" { return g.contains("afrobeats") || g.contains("afro-pop") }
        return genreHints.contains { g.contains(normalized($0)) }
    }
}

private func normalized(_ input: String) -> String {
    input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}

struct GenreChartSong: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let genre: String
    let artwork: String?
    let releaseDate: String?
    let link: String?
    let isAlbum: Bool
    /// Source list position only. Never mislabel a derived genre list as an official chart.
    let sourcePosition: Int?
    var artworkURL: URL? { artwork.flatMap(URL.init(string:)) }
    var date: Date? {
        guard let releaseDate else { return nil }
        let dateOnly = String(releaseDate.prefix(10))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: dateOnly)
    }
    var identity: String { normalized(artist) + "|" + normalized(title) }
}

struct GenreChartSnapshot: Codable {
    let genreID: String
    let refreshedAt: Date
    let newReleases: [GenreChartSong]
    let trending: [GenreChartSong]
    let sourceDescription: String
    var isEmpty: Bool { newReleases.isEmpty && trending.isEmpty }
}

private struct AppleRSSResponse: Decodable {
    struct Feed: Decodable {
        struct Item: Decodable {
            struct Genre: Decodable { let name: String? }
            struct Artist: Decodable { let name: String? }
            let id: String
            let name: String
            let artistName: String?
            let artist: Artist?
            let artworkUrl100: String?
            let releaseDate: String?
            let url: String?
            let genres: [Genre]?
        }
        let results: [Item]
    }
    let feed: Feed
}

private struct ITunesResponse: Decodable {
    struct Item: Decodable {
        let kind: String?
        let wrapperType: String?
        let trackId: Int?
        let collectionId: Int?
        let trackName: String?
        let collectionName: String?
        let artistName: String?
        let primaryGenreName: String?
        let artworkUrl100: String?
        let releaseDate: String?
        let trackViewUrl: String?
        let collectionViewUrl: String?
        let trackNumber: Int?
    }
    let results: [Item]
}

private struct LastFMTagResponse: Decodable {
    struct TrackCollection: Decodable {
        struct Track: Decodable {
            struct Artist: Decodable { let name: String }
            struct Image: Decodable {
                let value: String?
                let size: String?
                enum CodingKeys: String, CodingKey { case value = "#text"; case size }
            }
            let name: String
            let artist: Artist
            let url: String?
            let image: [Image]?
        }
        let track: [Track]
    }
    let tracks: TrackCollection?
}

/// No Apple Developer membership or paid API credentials required.
/// Data source: Apple's public promotional RSS charts and iTunes Search API.
/// These are METADATA ONLY and must not be used as unrestricted audio streams.
actor GenreChartsService {
    static let shared = GenreChartsService()
    private var feedCache: [String: (Date, [GenreChartSong])] = [:]
    private let feedTTL: TimeInterval = 6 * 3600

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("DVSMusic/1.0.4 (music discovery)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ChartServiceError.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func rss(country: String, feed: String, media: String) async -> [GenreChartSong] {
        let cacheKey = "\(country)|\(feed)|\(media)"
        if let cached = feedCache[cacheKey], Date().timeIntervalSince(cached.0) < feedTTL { return cached.1 }
        guard let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(country)/music/\(feed)/100/\(media).json"),
              let output: AppleRSSResponse = try? await fetch(url) else { return [] }
        let values = output.feed.results.enumerated().compactMap { index, item -> GenreChartSong? in
            let artist = item.artistName ?? item.artist?.name ?? ""
            guard !artist.isEmpty, !item.name.isEmpty else { return nil }
            return GenreChartSong(id: item.id, title: item.name, artist: artist,
                genre: (item.genres ?? []).compactMap(\.name).joined(separator: ", "),
                artwork: item.artworkUrl100, releaseDate: item.releaseDate, link: item.url,
                isAlbum: media == "albums", sourcePosition: index + 1)
        }
        feedCache[cacheKey] = (Date(), values)
        return values
    }

    private func search(_ term: String, country: String) async -> [GenreChartSong] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let url = components.url, let result: ITunesResponse = try? await fetch(url) else { return [] }
        return result.results.compactMap { item in
            guard item.kind == "song", let name = item.trackName, let artist = item.artistName,
                  !name.isEmpty, !artist.isEmpty, let trackID = item.trackId else { return nil }
            return GenreChartSong(id: String(trackID), title: name, artist: artist,
                genre: item.primaryGenreName ?? "", artwork: item.artworkUrl100,
                releaseDate: item.releaseDate, link: item.trackViewUrl,
                isAlbum: false, sourcePosition: nil)
        }
    }


    private func lastFMTag(_ genre: DVSGenre, apiKey: String) async -> [GenreChartSong] {
        guard !apiKey.isEmpty else { return [] }
        let tags: [String: String] = [
            "trap-it": "italian trap", "trap-world": "trap", "hiphop": "hip-hop",
            "indie": "indie", "pop": "pop", "rnb": "rnb", "rock": "rock",
            "techno": "techno", "reggaeton": "reggaeton", "lofi": "lo-fi",
            "chill": "chillout", "dance": "dance", "house": "house",
            "latin": "latin", "jazz": "jazz", "metal": "metal", "classical": "classical",
            "country": "country", "kpop": "k-pop", "afrobeats": "afrobeats"
        ]
        let tag = tags[genre.id] ?? genre.title
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        components.queryItems = [
            .init(name: "method", value: "tag.getTopTracks"),
            .init(name: "tag", value: tag),
            .init(name: "api_key", value: apiKey),
            .init(name: "limit", value: "75"),
            .init(name: "format", value: "json")
        ]
        guard let url = components.url,
              let data: LastFMTagResponse = try? await fetch(url) else { return [] }
        return (data.tracks?.track ?? []).enumerated().map { idx, item in
            GenreChartSong(id: "lastfm-" + genre.id + "-" + String(idx),
                title: item.name, artist: item.artist.name, genre: tag,
                artwork: item.image?.last(where: { !($0.value ?? "").isEmpty })?.value,
                releaseDate: nil, link: item.url, isAlbum: false, sourcePosition: idx + 1)
        }
    }

    func load(_ genre: DVSGenre, country: String = "it", now: Date = Date(), lastFMKey: String = "") async -> GenreChartSnapshot {
        // Four shared, keyless feeds plus genre-specific discovery. Apple may not expose
        // a genre-specific public chart; do not fabricate such a ranking.
        async let topSongs = rss(country: country, feed: "most-played", media: "songs")
        async let topAlbums = rss(country: country, feed: "most-played", media: "albums")
        async let newAlbums = rss(country: country, feed: "new-releases", media: "albums")
        async let tagTracks = lastFMTag(genre, apiKey: lastFMKey.trimmingCharacters(in: .whitespacesAndNewlines))
        let terms = Array(genre.searchTerms.prefix(2))
        var searchResults: [GenreChartSong] = []
        await withTaskGroup(of: [GenreChartSong].self) { group in
            for term in terms { group.addTask { await self.search(term, country: country) } }
            for await batch in group { searchResults.append(contentsOf: batch) }
        }
        let top = await topSongs
        let albumTop = await topAlbums
        let fresh = await newAlbums
        let tagged = await tagTracks
        return GenreChartRanking.prepare(genre: genre, topSongs: top, topAlbums: albumTop,
                                         newAlbums: fresh, searchResults: searchResults,
                                         tagTracks: tagged, now: now)
    }

    func albumTracks(albumID: String, country: String = "it") async -> [GenreChartSong] {
        guard Int(albumID) != nil else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "id", value: albumID),
                                 URLQueryItem(name: "country", value: country),
                                 URLQueryItem(name: "entity", value: "song"),
                                 URLQueryItem(name: "limit", value: "100")]
        guard let url = components.url, let response: ITunesResponse = try? await fetch(url) else { return [] }
        return response.results.compactMap { item -> GenreChartSong? in
            guard item.kind == "song", let id = item.trackId,
                  let name = item.trackName, let artist = item.artistName else { return nil }
            return GenreChartSong(id: String(id), title: name, artist: artist,
                 genre: item.primaryGenreName ?? "", artwork: item.artworkUrl100,
                 releaseDate: item.releaseDate, link: item.trackViewUrl, isAlbum: false,
                 sourcePosition: item.trackNumber)
        }.sorted { ($0.sourcePosition ?? 999) < ($1.sourcePosition ?? 999) }
    }
}


/// Ranking calculated from external metadata (NOT an official platform genre ranking).
/// Kept pure so the filtering, release window and duplicate handling can be tested offline.
enum GenreChartRanking {
    static func prepare(genre: DVSGenre, topSongs: [GenreChartSong], topAlbums: [GenreChartSong],
                        newAlbums: [GenreChartSong], searchResults: [GenreChartSong],
                        tagTracks: [GenreChartSong] = [], now: Date) -> GenreChartSnapshot {
        func unique(_ values: [GenreChartSong]) -> [GenreChartSong] {
            var seen = Set<String>()
            return values.filter { seen.insert($0.identity).inserted }
        }
        let matches: (GenreChartSong) -> Bool = {
            genre.matches(genre: $0.genre, artist: $0.artist, title: $0.title)
        }
        let releaseWindow = now.addingTimeInterval(-90 * 86400)
        let releases = unique((newAlbums + searchResults).filter(matches))
            .filter { item in
                guard let day = item.date else { return false }
                return day >= releaseWindow && day <= now.addingTimeInterval(86400)
            }.sorted { a, b in
                if a.date != b.date { return (a.date ?? .distantPast) > (b.date ?? .distantPast) }
                return a.identity < b.identity
            }
        let trending = Array(unique((tagTracks + topSongs + topAlbums + searchResults).filter(matches)).prefix(50))
        return GenreChartSnapshot(genreID: genre.id, refreshedAt: now,
            newReleases: Array(releases.prefix(45)), trending: trending,
            sourceDescription: tagTracks.isEmpty ? "Apple RSS · iTunes (classifica locale derivata)" : "Last.fm generi · Apple RSS · iTunes")
    }
}

enum ChartServiceError: Error { case unavailable }
