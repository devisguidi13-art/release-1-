import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func check(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAILED: \(message)\n", stderr); exit(1) }
}

@main
struct MultiSourceTests {
    static func main() throws {
        // Old (0.5–1.0.4) favourites must still decode with no new field.
        let old = #"{"id":"dQw4w9WgXcQ","title":"Song","artist":"Artist - Topic","duration":213}"#.data(using: .utf8)!
        let track = try JSONDecoder().decode(MusicTrack.self, from: old)
        check(!track.isAudius && track.sourceLabel == "YouTube", "old history")
        check(track.artworkURL?.host == "i.ytimg.com", "old artwork")
        let json = #"{"data":[{"id":"aBcD2","title":"Song","duration":211,"user":{"name":"Artist"},"artwork":{"480x480":"https://example.com/cover.jpg"},"is_streamable":true},{"id":"x","title":"Bad","duration":200,"user":{"name":"Other"},"is_streamable":false}]}"#.data(using: .utf8)!
        let results = AudiusSource.parse(data: json)
        check(results.count == 1, "streamable only")
        check(results[0].id == "audius:aBcD2", "source namespace")
        check(results[0].artworkURL?.host == "example.com", "native covers")
        check(AudiusSource.streamURL(for: results[0])?.host == "api.audius.co", "internal stream")
        check(AudiusSource.exactMatch(to: track, among: results) != nil, "safe cross-source fallback")
        let wrong = MusicTrack(id: "audius:y", title: "Song (Slowed)", artist: "Artist", duration: 220)
        check(AudiusSource.exactMatch(to: track, among: [wrong]) == nil, "reject altered recording")
        let persisted = try JSONEncoder().encode(results)
        let decoded = try JSONDecoder().decode([MusicTrack].self, from: persisted)
        check(decoded.first?.isAudius == true, "new persistence")
        print("OK v1.0.5: 2 provider, stream endpoints, metadata, safe fallback, legacy storage")
    }
}
