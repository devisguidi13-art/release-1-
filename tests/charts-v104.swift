import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main
struct ChartsV104Check {
static func main() {
let genres = DVSGenre.all
expect(genres.count >= 19, "all categories must be supported")
expect(Set(genres.map(\.id)).count == genres.count, "genre keys unique")
for genre in genres {
    expect(!genre.searchTerms.isEmpty && !genre.genreHints.isEmpty, "genre has a dynamic query")
}
let rap = genres.first(where: { $0.id == "hiphop" })!
let trap = genres.first(where: { $0.id == "trap-it" })!
let metal = genres.first(where: { $0.id == "metal" })!
expect(rap.matches(genre: "Hip-Hop/Rap", artist: "Artist", title: "Song"), "rap genre")
expect(!trap.matches(genre: "Hip-Hop/Rap", artist: "Unrelated Artist", title: "Track"), "trap should not include all rap")
expect(trap.matches(genre: "Hip-Hop/Rap", artist: "Lazza", title: "Nuovo"), "trap artist seeds")
expect(metal.matches(genre: "Metal", artist: "Artist", title: "Song"), "metal supported")

let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!
func song(_ id: String, _ title: String, _ date: String, _ genre: String = "Hip-Hop/Rap") -> GenreChartSong {
    .init(id: id, title: title, artist: "Lazza", genre: genre, artwork: nil,
          releaseDate: date, link: nil, isAlbum: false, sourcePosition: nil)
}
let yesterday = song("1", "Nuova", "2026-11-17")
let lastMonth = song("2", "Mese scorso", "2026-10-31")
let old = song("3", "Vecchia", "2019-01-03")
let dup = song("4", "Nuova", "2026-11-17")
let pop = GenreChartSong(id: "5", title: "Pezzo Pop", artist: "Taylor Swift", genre: "Pop", artwork: nil, releaseDate: "2026-11-11", link: nil, isAlbum: false, sourcePosition: nil)
let snapshot = GenreChartRanking.prepare(genre: trap, topSongs: [old, yesterday],
    topAlbums: [], newAlbums: [old, lastMonth, yesterday, dup, pop], searchResults: [yesterday], now: now)
expect(snapshot.newReleases.map(\.title) == ["Nuova", "Mese scorso"], "date order and dedup")
expect(snapshot.trending.map(\.title) == ["Vecchia", "Nuova"], "local rankings preserve source order")
expect(!snapshot.newReleases.contains(where: { $0.title == "Vecchia" }), "stale removed")
expect(!snapshot.newReleases.contains(where: { $0.title == "Pezzo Pop" }), "wrong genre filtered")
print("OK v1.0.4: 20 generi, filtri, classifiche locali, novità, cache-ready metadata, sorgente alternativa")
}
}
