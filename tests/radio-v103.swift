import Foundation

@main
struct Radio103Tests {
    static func main() {
        let old = MusicTrack(id: "old00000001", title: "Future - Mask Off", artist: "Future - Topic", duration: 204)
        let artistGroup = MusicDiscoveryService.style(for: "Future")
        precondition(artistGroup == "trap")
        precondition(MusicDiscoveryService.style(for: "Sfera Ebbasta") == "rap italiano")
        precondition(MusicDiscoveryService.style(for: "Artist unknown", genre: "R&B/Soul") == "rnb")
        let related = MusicDiscoveryService.relatedArtists(to: "Future", genre: "Hip-Hop/Rap", favorites: [], history: [:])
        precondition(related.count >= 4)
        precondition(related.contains("21 Savage"))
        precondition(!related.contains("Future"))
        precondition(!related.contains("Gazzelle"), "Do not switch genres in radio")
        let key = DiscoverySong(artist: "Future", title: "Mask Off", genre: "Hip-Hop/Rap", confidence: 70)
        precondition(key.canonical == MusicMetadata.canonicalKey(old))
        let candidate = MusicTrack(id: "candidate01", title: "21 Savage - Bank Account", artist: "21 Savage - Topic", duration: 210)
        let engine = RecommendationEngine()
        var blocked: Set<String> = []
        blocked.insert(MusicMetadata.canonicalKey(candidate))
        let ranked = engine.rank([.init(track: candidate, relevance: 140)], near: old,
                                 excluding: [], favorites: [], history: [:], exploration: 0.35,
                                 blockedCanonical: blocked)
        precondition(ranked.isEmpty)
        print("OK 1.0.3: independent style neighborhoods, genre checks, canonical blocking")
    }
}
