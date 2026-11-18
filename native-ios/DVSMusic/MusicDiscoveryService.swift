import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Metadata-only music discovery. YouTube's relatedVideos feed is NOT queried.
/// iTunes identifies real, released tracks and their genre; CatalogService is used
/// later only to find a matching playable source (official distributor preferred).
struct DiscoverySong: Hashable {
    let artist: String
    let title: String
    let genre: String
    let confidence: Double

    var canonical: String { MusicMetadata.canonicalKey(artist: artist, title: title) }
}

struct MusicDiscoveryService {
    private struct SearchResponse: Decodable {
        let results: [Item]
    }
    private struct Item: Decodable {
        let artistName: String?
        let trackName: String?
        let primaryGenreName: String?
        let trackTimeMillis: Int?
        let kind: String?
    }

    private actor SearchCache {
        static let shared = SearchCache()
        var stored: [String: (Date, [DiscoverySong])] = [:]
        func get(_ query: String) -> [DiscoverySong]? {
            guard let (stamp, result) = stored[query], Date().timeIntervalSince(stamp) < 60 * 60 else { return nil }
            return result
        }
        func put(_ query: String, result: [DiscoverySong]) {
            stored[query] = (Date(), result)
            if stored.count > 75 { stored.removeAll() }
        }
    }

    /// Explicit style clusters are only a cold-start prior, not a claim to have
    /// analyzed the audio. The real seed genre is read from music metadata.
    static let neighborhoods: [(name: String, terms: [String], artists: [String])] = [
        ("trap", ["future", "21 savage", "metro boomin", "travis scott", "gunna", "young thug", "lil baby", "don toliver", "quavo", "offset", "migos", "playboi carti", "drake", "lil uzi"],
         ["21 Savage", "Metro Boomin", "Travis Scott", "Gunna", "Young Thug", "Lil Baby", "Don Toliver", "Future", "Quavo", "Playboi Carti"]),
        ("rap italiano", ["sfera", "shiva", "capo plaza", "lazza", "paky", "geolier", "tedua", "tony effe", "rondo da sosa", "baby gang", "thasup", "gue"],
         ["Sfera Ebbasta", "Shiva", "Capo Plaza", "Lazza", "Geolier", "Tedua", "Paky", "Tony Effe", "thasup"]),
        ("indie italiano", ["bresh", "psicologi", "olly", "calcutta", "gazzelle", "pinguini tattici", "fulminacci", "fra h quintale", "coez"],
         ["Bresh", "Olly", "Gazzelle", "Calcutta", "Coez", "Fulminacci", "Pinguini Tattici Nucleari"]),
        ("rnb", ["frank ocean", "the weeknd", "sza", "brent faiyaz", "daniel caesar", "summer walker", "giveon"],
         ["Frank Ocean", "SZA", "Brent Faiyaz", "The Weeknd", "Daniel Caesar", "Giveon"]),
        ("rock", ["nirvana", "foo fighters", "muse", "arctic monkeys", "radiohead", "linkin park", "the strokes"],
         ["Nirvana", "Foo Fighters", "Muse", "Arctic Monkeys", "Radiohead", "The Strokes"]),
        ("electronic", ["fred again", "calvin harris", "martin garrix", "david guetta", "swedish house mafia", "disclosure", "skrillex"],
         ["Fred again..", "Disclosure", "Calvin Harris", "Skrillex", "Swedish House Mafia", "Martin Garrix"]),
        ("latin", ["bad bunny", "rauw alejandro", "feid", "karol g", "j balvin", "ozuna", "anuel aa"],
         ["Bad Bunny", "Rauw Alejandro", "Feid", "Karol G", "J Balvin", "Ozuna"]),
        ("pop", ["dua lipa", "taylor swift", "ariana grande", "billie eilish", "olivia rodrigo", "sabrina carpenter"],
         ["Dua Lipa", "Billie Eilish", "Olivia Rodrigo", "Sabrina Carpenter", "Ariana Grande"])
    ]

    static func style(for artist: String, genre: String = "") -> String {
        let name = MusicMetadata.normalized(artist)
        if let exact = neighborhoods.first(where: { group in
            group.terms.contains(where: { term in name == term || name.contains(term + " ") || name.hasPrefix(term + "-") })
        }) { return exact.name }
        let g = MusicMetadata.normalized(genre)
        if g.contains("hip-hop") || g.contains("hip hop") || g.contains("rap") { return "trap" }
        if g.contains("r&b") || g.contains("soul") { return "rnb" }
        if g.contains("latin") || g.contains("reggaeton") { return "latin" }
        if g.contains("rock") || g.contains("metal") || g.contains("punk") { return "rock" }
        if g.contains("electronic") || g.contains("dance") { return "electronic" }
        if g.contains("pop") { return "pop" }
        return ""
    }

    static func relatedArtists(to artist: String, genre: String, favorites: [MusicTrack], history: [String: ListeningRecord]) -> [String] {
        let cluster = style(for: artist, genre: genre)
        let current = MusicMetadata.normalized(artist)
        let neighborhood = neighborhoods.first { $0.name == cluster }
        var result: [String] = []
        var seen: Set<String> = [current]
        let listened = history.values.sorted { $0.seconds > $1.seconds }
            .map { MusicMetadata.identity(for: $0.track).artist }
        for candidate in favorites.map({ MusicMetadata.identity(for: $0).artist }) + listened {
            let name = MusicMetadata.normalized(candidate)
            if !name.isEmpty && style(for: candidate, genre: genre) == cluster && seen.insert(name).inserted {
                result.append(candidate)
            }
        }
        if let neighborhood {
            // Rotate across days so there is no permanent 5-artist loop.
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            let artists = neighborhood.artists
            for offset in artists.indices {
                let name = artists[(day + offset) % artists.count]
                if seen.insert(MusicMetadata.normalized(name)).inserted { result.append(name) }
            }
        }
        return result
    }

    private func searchSongs(for artist: String, exactSong: String? = nil) async -> [DiscoverySong] {
        let term = exactSong.map { artist + " " + $0 } ?? artist
        let key = (exactSong == nil ? "artist:" : "song:") + MusicMetadata.normalized(term)
        if let cached = await SearchCache.shared.get(key) { return cached }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: "IT"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: exactSong == nil ? "55" : "12")
        ]
        if exactSong == nil { components.queryItems?.append(URLQueryItem(name: "attribute", value: "artistTerm")) }
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("DVS Music/1.0.3", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [] }
        let cleaned = payload.results.compactMap { item -> DiscoverySong? in
            guard let name = item.artistName, let song = item.trackName,
                  !name.isEmpty, !song.isEmpty,
                  item.kind == nil || item.kind == "song",
                  (item.trackTimeMillis ?? 180_000) >= 70_000 else { return nil }
            let normalizedName = MusicMetadata.normalized(name)
            let sought = MusicMetadata.normalized(artist)
            // A search response may contain artist name as part of the *title*.
            guard exactSong != nil || normalizedName == sought || normalizedName.hasPrefix(sought + " &") ||
                normalizedName.hasPrefix(sought + ",") else { return nil }
            if let exactSong, MusicMetadata.titleMatch(exactSong, candidate: song) < 0.7 { return nil }
            let title = MusicMetadata.normalized(song)
            guard !["karaoke", "tribute", "remix", "sped up", "slowed", "live at", "instrumental"].contains(where: { title.contains($0) }) else { return nil }
            return DiscoverySong(artist: name, title: song, genre: item.primaryGenreName ?? "",
                                 confidence: exactSong == nil ? 64 : 110)
        }
        var seen: Set<String> = []
        let unique = cleaned.filter { seen.insert($0.canonical).inserted }
        await SearchCache.shared.put(key, result: unique)
        return unique
    }

    /// Build an independent, genre-led playlist of *song identities*, not videos.
    /// Falls back to the seed artist if iTunes metadata is unavailable.
    func suggestions(near anchor: MusicTrack, favorites: [MusicTrack], history: [String: ListeningRecord]) async -> [DiscoverySong] {
        let seed = MusicMetadata.identity(for: anchor)
        guard !seed.artist.isEmpty, MusicMetadata.normalized(seed.artist) != "youtube" else { return [] }
        async let seedLookup = searchSongs(for: seed.artist, exactSong: seed.title)
        let seedResults = await seedLookup
        let genre = seedResults.first?.genre ?? ""
        let neighbors = Self.relatedArtists(to: seed.artist, genre: genre, favorites: favorites, history: history)
        let selectedArtists = [seed.artist] + Array(neighbors.prefix(5))
        var byArtist: [[DiscoverySong]] = Array(repeating: [], count: selectedArtists.count)
        await withTaskGroup(of: (Int, [DiscoverySong]).self) { group in
            for (index, name) in selectedArtists.enumerated() {
                group.addTask { (index, await searchSongs(for: name)) }
            }
            for await (index, songs) in group { byArtist[index] = songs }
        }
        let anchorStyle = Self.style(for: seed.artist, genre: genre)
        // The returned Apple genre narrows the pool even if the seed artist
        // isn't in one of our cold-start clusters.
        let normalizedGenre = MusicMetadata.normalized(genre)
        var pool: [[DiscoverySong]] = []
        for (idx, songs) in byArtist.enumerated() {
            var selected = songs.filter { item in
                let sameStyle = Self.style(for: item.artist, genre: item.genre) == anchorStyle
                let sameGenre = !normalizedGenre.isEmpty && MusicMetadata.normalized(item.genre) == normalizedGenre
                return anchorStyle.isEmpty || sameStyle || sameGenre
            }
            // Start at different offsets: prevent playing the same hits every time.
            let offset = (Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0) + idx * 3
            if selected.count > 5 { selected = Array(selected[(offset % selected.count)...]) + Array(selected[..<(offset % selected.count)]) }
            pool.append(selected)
        }
        var discovered: [DiscoverySong] = []
        var used: Set<String> = [MusicMetadata.canonicalKey(anchor)]
        // Round-robin across artists, rather than YouTube's next-video order.
        for round in 0..<4 {
            for artistIndex in pool.indices {
                guard pool[artistIndex].indices.contains(round) else { continue }
                let candidate = pool[artistIndex][round]
                if used.insert(candidate.canonical).inserted { discovered.append(candidate) }
            }
        }
        return Array(discovered.prefix(20))
    }
}
