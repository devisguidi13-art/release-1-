import Foundation

@main
struct IntelligenceTests {
    static func main() {
        let seed = MusicTrack(id: "seed0000001", title: "Future - Mask Off (Official Video)",
                              artist: "FutureVEVO", duration: 204)
        let exact = MusicTrack(id: "exact000001", title: "21 Savage - Bank Account (Official Audio)",
                               artist: "21 Savage", duration: 220)
        let duplicate = MusicTrack(id: "duplc000001", title: "21 Savage - Bank Account [Official Audio]",
                                   artist: "21 Savage - Topic", duration: 220)
        let unrelated = MusicTrack(id: "other000001", title: "A Completely Unrelated Song", artist: "Unknown", duration: 180)
        let bad = MusicTrack(id: "bad00000001", title: "Mask Off REACTION", artist: "Some Channel", duration: 190)
        let competitor = MusicTrack(id: "comp0000001", title: "Metro Boomin - Superhero", artist: "Metro Boomin", duration: 200)
        let wrongVersion = MusicTrack(id: "wrong000001", title: "21 Savage - Bank Account COVER BY fan", artist: "Fan", duration: 201)
        let engine = RecommendationEngine()
        precondition(MusicMetadata.identity(for: seed).title == "Mask Off")
        precondition(MusicMetadata.titleMatch("Bank Account", candidate: "Bank Account") >= 0.99)
        precondition(MusicMetadata.titleMatch("Bank Account", candidate: "Another Song") < 0.50)
        precondition(MusicMetadata.artistMatch("21 Savage", candidate: exact))
        precondition(!MusicMetadata.artistMatch("Drake", candidate: exact))
        precondition(!MusicMetadata.isMusic(bad))
        precondition(!MusicMetadata.isMusic(wrongVersion))
        precondition(MusicMetadata.canonicalKey(exact) == MusicMetadata.canonicalKey(duplicate))
        let candidates = [
            RecommendationEngine.Candidate(track: unrelated, relevance: 5),
            RecommendationEngine.Candidate(track: exact, relevance: 170),
            RecommendationEngine.Candidate(track: duplicate, relevance: 140),
            RecommendationEngine.Candidate(track: competitor, relevance: 90),
            RecommendationEngine.Candidate(track: bad, relevance: 200)
        ]
        let ranked = engine.rank(candidates, near: seed, excluding: [], favorites: [], history: [:], exploration: 0.25)
        precondition(ranked.first?.id == duplicate.id, "Same-song distribution uploads should outrank non-official duplicates")
        precondition(ranked.filter { MusicMetadata.canonicalKey($0) == MusicMetadata.canonicalKey(exact) }.count == 1,
                     "Duplicate recordings from different channels must be collapsed")
        precondition(!ranked.contains(bad), "Reaction videos must never enter the radio")
        let excluded = engine.rank(candidates, near: seed, excluding: [exact.id], favorites: [], history: [:], exploration: 0.25)
        precondition(!excluded.contains(exact) && !excluded.contains(duplicate), "Canonical exclusion prevents reuploads")
        var record = ListeningRecord(track: exact)
        record.plays = 1
        record.skips = 4
        let disliked = engine.rank(candidates, near: seed, excluding: [], favorites: [], history: [exact.id: record], exploration: 0.25)
        precondition(!disliked.contains(exact), "Repeated skips suppress a track")
        let order = engine.smartOrder([exact, duplicate, unrelated, competitor], following: seed,
                                      favorites: [], history: [:], exploration: 0.3)
        precondition(order.count == 3, "Smart Shuffle must remove exact recording duplicates")
        precondition(CatalogService.videoID(from: "https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        // Audit 1.0.1: video titles with en/em dashes must match the same song.
        let dash = MusicTrack(id: "dash0000001", title: "21 Savage – Bank Account [Official Audio]",
                              artist: "21 Savage - Topic", duration: 220)
        precondition(MusicMetadata.identity(for: dash).title == "Bank Account", "YouTube en-dash title parsing")
        precondition(MusicMetadata.canonicalKey(dash) == MusicMetadata.canonicalKey(exact), "Canonical en-dash match")
        let emDash = MusicTrack(id: "emda0000001", title: "21 Savage — Bank Account",
                                artist: "21 Savage - Topic", duration: 220)
        precondition(MusicMetadata.canonicalKey(emDash) == MusicMetadata.canonicalKey(exact))
        // Persistent negative preference covers uploads with different video IDs.
        let preference = MusicTrack(id: "block111111", title: "Test Artist - Unique Blocked Track",
                                    artist: "Test Artist", duration: 190)
        let mirror = MusicTrack(id: "block222222", title: "Test Artist - Unique Blocked Track (Official Audio)",
                                artist: "Test Artist - Topic", duration: 190)
        var store = ListeningStore()
        store.setBlocked(preference, blocked: true)
        precondition(store.isBlocked(mirror), "Blocking a recording must also block reuploads")
        let loadedStore = ListeningStore()
        precondition(loadedStore.isBlocked(mirror), "Canonical block must persist across launches")
        let rankedBlocked = engine.rank([.init(track: mirror, relevance: 250)], near: seed,
                                        excluding: [], favorites: [], history: [:], exploration: 0.25,
                                        blockedCanonical: store.blockedCanonicalKeys)
        precondition(rankedBlocked.isEmpty, "The recommender must respect canonical blocking")
        store.setBlocked(preference, blocked: false)
        precondition(!store.isBlocked(mirror), "Unblocking should undo the canonical exclusion")
        print("OK 1.0.1 audit: metadata separators, persistent block variants, Last.fm ranking, Smart Shuffle")
    }
}
