import Foundation

/// DVS Intelligence 1.0.3: radio choices never use YouTube relatedVideos.
/// Real released song metadata (iTunes Search API), artist/style neighborhoods,
/// favorites, listening habits and optional Last.fm form the candidate pool.
/// YouTube is queried ONLY to resolve an already-selected song identity.
/// No invented BPM, audio fingerprints, or Spotify recommendation model.
struct RecommendationEngine {
    private let catalog = MultiSourceCatalog()
    private let lastFM = LastFMService()
    private let discovery = MusicDiscoveryService()

    private let genres: [String: [String]] = [
        "trap": ["trap", "drill", "rap", "hiphop", "hip hop", "migos", "future", "21 savage", "shiva", "sfera", "capo plaza", "metro boomin", "travis scott", "offset", "quavo", "lil baby", "gunna", "young thug"],
        "indie": ["indie", "alternative", "lofi", "bedroom", "bresh", "psicologi", "olly", "calcutta"],
        "pop": ["pop", "mainstream", "dua lipa", "taylor swift", "ariana grande"],
        "rock": ["rock", "punk", "metal", "grunge", "guitar", "nirvana"],
        "electronic": ["techno", "house", "edm", "electronic", "dance", "fred again"],
        "rnb": ["r&b", "rnb", "soul", "frank ocean", "the weeknd", "sza", "brent faiyaz"],
        "latin": ["reggaeton", "latin", "bachata", "salsa", "bad bunny", "urbano", "rauw alejandro"]
    ]

    struct Candidate {
        let track: MusicTrack
        let relevance: Double // higher means a better verified match to the source song
    }

    /// Exposed for repeatable, network-free tests.
    func rank(_ candidates: [Candidate], near anchor: MusicTrack, excluding excluded: Set<String>,
              favorites: [MusicTrack], history: [String: ListeningRecord], exploration: Double,
              blockedCanonical: Set<String> = []) -> [MusicTrack] {
        let reference = MusicMetadata.identity(for: anchor)
        let referenceGenres = genreSet(anchor)
        let excludedCanonical = Set(history.values.filter { $0.skips >= 3 && $0.skips > $0.plays }
            .map { MusicMetadata.canonicalKey($0.track) })
        let favoriteKeys = Set(favorites.map { MusicMetadata.canonicalKey($0) })
        var candidateScores: [String: (MusicTrack, Double)] = [:]
        let novelty = min(1, max(0, exploration))
        let anchorArtist = MusicMetadata.normalized(reference.artist)
        let excludeKeys = Set(candidates.filter { excluded.contains($0.track.id) }.map { MusicMetadata.canonicalKey($0.track) })
        for item in candidates {
            let candidate = item.track
            guard candidate.id != anchor.id, !excluded.contains(candidate.id),
                  MusicMetadata.isMusic(candidate) else { continue }
            let key = MusicMetadata.canonicalKey(candidate)
            guard key != MusicMetadata.canonicalKey(anchor), !excludeKeys.contains(key),
                  !excludedCanonical.contains(key), !blockedCanonical.contains(key) else { continue }
            let candidateInfo = MusicMetadata.identity(for: candidate)
            let candidateArtist = MusicMetadata.normalized(candidateInfo.artist)
            var score = item.relevance
            let commonGenres = referenceGenres.intersection(genreSet(candidate)).count
            score += Double(commonGenres) * 12
            // Reduce monotony: user wants songs similar in style, not only the same artist.
            if !anchorArtist.isEmpty && candidateArtist == anchorArtist { score -= 16 }
            else { score += 4 }
            if candidate.duration >= 120 && candidate.duration <= 420 { score += 4 }
            if favoriteKeys.contains(key) { score += 12 * (1 - novelty) }
            if history[candidate.id] == nil { score += 12 * novelty }
            if let record = history[candidate.id] {
                score += min(12, Double(record.plays) * 2.5) * (1 - novelty / 2)
                score -= Double(record.skips) * 24
                if Date().timeIntervalSince(record.lastPlayed) < 12 * 3600 { score -= 28 }
            }
            // Prefer original recordings over upload duplicates, but do not fake audio features.
            let title = MusicMetadata.normalized(candidate.title)
            score += min(15, Double(OfficialCatalog.sourceConfidence(candidate)) * 0.15)
            if title.contains("live") || title.contains("remix") || title.contains("sped") { score -= 30 }
            if let previous = candidateScores[key] {
                let earlierSource = OfficialCatalog.sourceConfidence(previous.0)
                let newSource = OfficialCatalog.sourceConfidence(candidate)
                // Source preference is STRONG only when comparing two uploads
                // of the *same* recording, not unrelated recommended songs.
                if newSource > earlierSource && score >= previous.1 - 65 {
                    // Prefer the official-source hint.
                } else if score <= previous.1 || (newSource < earlierSource && score < previous.1 + 65) {
                    continue
                }
            }
            candidateScores[key] = (candidate, score)
        }
        return candidateScores.values.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }.prefix(32).map { $0.0 }
    }

    func recommendations(near track: MusicTrack, excluding excluded: Set<String>,
                         favorites: [MusicTrack] = [], history: [String: ListeningRecord] = [:],
                         apiKey: String = "", exploration: Double = 0.35,
                         blockedCanonical: Set<String> = []) async -> [MusicTrack] {
        // The radio is metadata-led, not video-led. Last.fm contributes optional
        // collaborative discovery; Apple public song metadata works without any key.
        async let metadataTask = discovery.suggestions(near: track, favorites: favorites, history: history)
        async let relatedTracksTask = lastFM.similar(to: track, apiKey: apiKey)
        let metadata = await metadataTask
        let collaborative = await relatedTracksTask
        var proposals: [DiscoverySong] = []
        for item in collaborative.prefix(8) {
            proposals.append(DiscoverySong(artist: item.artist, title: item.title,
                                           genre: "", confidence: 125 + item.match * 60))
        }
        proposals.append(contentsOf: metadata)
        // One song identity at most once, even if Apple and Last.fm agree.
        var seenIdentities: Set<String> = []
        proposals = proposals.filter { seenIdentities.insert($0.canonical).inserted }
        let avoid = Set(excluded).union(history.values.filter {
            $0.skips >= 3 && $0.skips > $0.plays
        }.map { $0.track.id })
        let excludedKeys = blockedCanonical.union(
            history.values.filter { avoid.contains($0.track.id) }
                .map { MusicMetadata.canonicalKey($0.track) }
        )
        let selected = proposals.filter { !excludedKeys.contains($0.canonical) }.prefix(16)
        var candidates: [Candidate] = []
        // Searches are concurrent, capped to avoid flooding catalog instances.
        await withTaskGroup(of: Candidate?.self) { group in
            for suggestion in selected {
                group.addTask {
                    guard !Task.isCancelled,
                          let results = try? await catalog.search("\(suggestion.artist) \(suggestion.title)") else { return nil }
                    let exact = results.compactMap { result -> (MusicTrack, Double)? in
                        guard MusicMetadata.isMusic(result), !avoid.contains(result.id) else { return nil }
                        let identity = MusicMetadata.identity(for: result)
                        let titleScore = MusicMetadata.titleMatch(suggestion.title, candidate: identity.title)
                        guard titleScore >= 0.78,
                              MusicMetadata.artistMatch(suggestion.artist, candidate: result) else { return nil }
                        let sourceBonus = Double(OfficialCatalog.sourceConfidence(result)) * 0.32
                        return (result, titleScore * 25 + sourceBonus)
                    }.max { $0.1 < $1.1 }
                    return exact.map { Candidate(track: $0.0, relevance: suggestion.confidence + $0.1) }
                }
            }
            for await candidate in group {
                if let candidate { candidates.append(candidate) }
            }
        }
        return rank(candidates, near: track, excluding: excluded,
                    favorites: favorites, history: history, exploration: exploration,
                    blockedCanonical: blockedCanonical)
    }

    func smartOrder(_ tracks: [MusicTrack], following anchor: MusicTrack?,
                    favorites: [MusicTrack], history: [String: ListeningRecord], exploration: Double = 0.35,
                    blockedCanonical: Set<String> = []) -> [MusicTrack] {
        let favoriteKeys = Set(favorites.map { MusicMetadata.canonicalKey($0) })
        var preferred: [String: MusicTrack] = [:]
        for track in tracks where MusicMetadata.isMusic(track) {
            let key = MusicMetadata.canonicalKey(track)
            guard !blockedCanonical.contains(key) else { continue }
            if let prior = preferred[key], OfficialCatalog.sourceConfidence(prior) >= OfficialCatalog.sourceConfidence(track) {
                continue
            }
            preferred[key] = track
        }
        var remaining = Array(preferred.values)
        var result: [MusicTrack] = []
        var previous = anchor
        let novelty = min(1, max(0, exploration))
        while !remaining.isEmpty {
            let referenceGenres = previous.map(genreSet) ?? []
            let previousArtist = previous.map { MusicMetadata.normalized(MusicMetadata.identity(for: $0).artist) } ?? ""
            let best = remaining.indices.max { left, right in
                func score(_ track: MusicTrack) -> Double {
                    let artist = MusicMetadata.normalized(MusicMetadata.identity(for: track).artist)
                    var value = Double(genreSet(track).intersection(referenceGenres).count) * 18
                    if !previousArtist.isEmpty && artist == previousArtist { value -= 35 }
                    if favoriteKeys.contains(MusicMetadata.canonicalKey(track)) { value += 9 * (1 - novelty) }
                    if history[track.id] == nil { value += 10 * novelty }
                    if let rec = history[track.id] { value += min(10, Double(rec.plays) * 2) - Double(rec.skips) * 18 }
                    return value
                }
                let lhs = score(remaining[left]), rhs = score(remaining[right])
                return lhs == rhs ? remaining[left].id > remaining[right].id : lhs < rhs
            }!
            let next = remaining.remove(at: best)
            result.append(next)
            previous = next
        }
        return result
    }

    private func genreSet(_ track: MusicTrack) -> Set<String> {
        let info = MusicMetadata.identity(for: track)
        let text = MusicMetadata.normalized(info.artist + " " + info.title)
        return Set(genres.compactMap { genre, terms in
            terms.contains(where: { text.contains($0) }) ? genre : nil
        })
    }
}
