import Foundation

@main
struct CheckMusic08 {
    static func main() {
        let now = Date()
        let a = MusicTrack(id: "Aa123456789", title: "Notte Blu", artist: "DVS", duration: 181)
        let b = MusicTrack(id: "Bb123456789", title: "Trap Club", artist: "Artista", duration: 210)
        let c = MusicTrack(id: "Cc123456789", title: "Notte Rosa", artist: "DVS", duration: 200)
        let records = [
            a.id: ListeningRecord(track: a, seconds: 900, plays: 9, skips: 0, lastPlayed: now),
            b.id: ListeningRecord(track: b, seconds: 50, plays: 1, skips: 3, lastPlayed: now.addingTimeInterval(-50 * 86400)),
            c.id: ListeningRecord(track: c, seconds: 600, plays: 5, skips: 0, lastPlayed: now.addingTimeInterval(-20 * 86400))
        ]
        let most = SmartLibrary.automatic(.mostPlayed, records: records, favorites: [c], blocked: [], now: now)
        precondition(most.map(\.id) == [a.id, c.id, b.id])
        let recents = SmartLibrary.automatic(.lastMonth, records: records, favorites: [], blocked: [], now: now)
        precondition(recents.map(\.id) == [a.id, c.id])
        let rule = SmartPlaylistRule(name: "Notte recenti", textFilter: "notte", minimumPlays: 4, lastDays: 30)
        precondition(SmartLibrary.matching(rule, records: records, favorites: [], blocked: [], now: now).map(\.id) == [a.id, c.id])
        let withBlocked = SmartLibrary.matching(rule, records: records, favorites: [], blocked: [a.id], now: now)
        precondition(withBlocked.map(\.id) == [c.id])
        let favorites = SmartPlaylistRule(name: "Preferite", favoritesOnly: true)
        precondition(SmartLibrary.matching(favorites, records: records, favorites: [c], blocked: [], now: now).map(\.id) == [c.id])
        let events = [PlayedTrackEntry(id: UUID(), track: a, date: now), PlayedTrackEntry(id: UUID(), track: b, date: now)]
        precondition(SmartLibrary.history(events, query: "nOtte").count == 1)
        precondition(DVSMood.allCases.count >= 8)
        precondition(DVSMood.night.searches.count > 0)
        let reordered = RecommendationEngine().smartOrder([a,b,c], following: nil, favorites: [], history: records, exploration: 0.9)
        precondition(reordered.count == 3)
        print("OK 0.8: moods, smart playlists, automatic lists, history, exploration")
    }
}
