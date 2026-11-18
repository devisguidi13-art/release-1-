import Foundation

@main
struct Check {
    static func main() {
        let yt = MusicTrack(id: "abc12345678", title: "Future - Mask Off (Official Video)", artist: "FutureVEVO", duration: 204)
        let parsed = MusicMetadata.identity(for: yt)
        precondition(parsed.artist == "Future", "Artist normalization failed: \(parsed.artist)")
        precondition(parsed.title == "Mask Off", "Title cleanup failed: \(parsed.title)")
        precondition(!MusicMetadata.isMusic(MusicTrack(id: "reaction12A", title: "Mask Off reaction", artist: "Some channel", duration: 400)))
        let a = MusicTrack(id: "a1234567890", title: "Artist A - Song", artist: "Artist A", duration: 200)
        let b = MusicTrack(id: "b1234567890", title: "Artist B - Song", artist: "Artist B", duration: 200)
        let c = MusicTrack(id: "c1234567890", title: "Artist A - Another", artist: "Artist A", duration: 200)
        let ordered = RecommendationEngine().smartOrder([c,b], following: a, favorites: [], history: [:])
        precondition(ordered.first?.id == b.id, "Smart Shuffle should not repeat the artist immediately")
        var listening = ListeningStore()
        listening.began(a)
        listening.listened(a, seconds: 1)
        listening.skipped(a)
        precondition(listening.summary().tracksHeard >= 1)
        precondition(listening.records[a.id]?.skips ?? 0 >= 1)
        print("OK: normalization, filtering, Smart Shuffle and local listening stats")
    }
}
