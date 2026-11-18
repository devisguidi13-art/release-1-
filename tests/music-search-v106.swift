import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL 1.0.6: \(message)\n", stderr); exit(1) }
}

@main struct MusicFirstSearchTests {
    static func main() throws {
        let configHTML = #"<script>ytcfg.set({"INNERTUBE_API_KEY":"public-web-key","INNERTUBE_CONTEXT_CLIENT_VERSION":"1.20261118.01.00"});</script>"#
        let config = YouTubeMusicCatalog.configurationFromHTML(configHTML)
        assertTrue(config?.key == "public-web-key" && config?.version == "1.20261118.01.00", "dynamic live client config")
        assertTrue(YouTubeMusicCatalog.configurationFromHTML("<html>no config</html>") == nil, "no invented API key")
        // A synthetic WEB_REMIX response: nested shelves, not fixed offsets.
        let sample = #"{"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[{"musicShelfRenderer":{"contents":[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"ABCDEF_1234"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Mask Off"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Future"},{"text":" • "},{"text":"FUTURE"},{"text":" • "},{"text":"3:25"}]}}}],"thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"https://example.net/cover_200.jpg"},{"url":"https://example.net/cover_500.jpg"}]}}}}},{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"ZYXWVU_9876"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Mask Off (Slowed)"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Future"},{"text":"3:45"}]}}}]}},{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"ABCDEF_1234"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Mask Off"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Future"},{"text":"3:25"}]}}}]}}]}}]}}}}]}}}"#
        let tracks = YouTubeMusicCatalog.parse(data: Data(sample.utf8))
        assertTrue(tracks.count == 2, "must parse and deduplicate songs")
        assertTrue(tracks[0].id == "ABCDEF_1234" && tracks[0].duration == 205, "song duration, ID")
        assertTrue(tracks[0].artist == "Future", "artist from structured metadata")
        assertTrue(tracks[0].artworkURL?.absoluteString == "https://example.net/cover_500.jpg", "album artwork")
        assertTrue(tracks[0].isYouTubeMusic && tracks[0].sourceLabel == "YouTube Music", "source hint")
        assertTrue(OfficialCatalog.sourceConfidence(tracks[0]) == 75, "song-row priority without false verification")

        let old = #"{"id":"dQw4w9WgXcQ","title":"Old","artist":"Artist","duration":210}"#
        let legacy = try JSONDecoder().decode(MusicTrack.self, from: Data(old.utf8))
        assertTrue(!legacy.isYouTubeMusic && legacy.sourceLabel == "YouTube", "old data decodes")
        let restored = try JSONDecoder().decode(MusicTrack.self, from: JSONEncoder().encode(tracks[0]))
        assertTrue(restored.isYouTubeMusic && restored.artworkLink == tracks[0].artworkLink, "new data roundtrip")

        let original = tracks[0]
        let duplicate = MusicTrack(id: "IJKLmn_1234", title: "Mask Off", artist: "Future - Topic", duration: 203)
        let remix = MusicTrack(id: "IJKLmn_9999", title: "Mask Off Remix", artist: "Future", duration: 204)
        let different = MusicTrack(id: "IJKLmn_9998", title: "Mask Off", artist: "Future", duration: 290)
        assertTrue(MultiSourceCatalog.sameRecording(original, duplicate), "true same-recording fallback")
        assertTrue(!MultiSourceCatalog.sameRecording(original, original), "no same ID fallback")
        assertTrue(!MultiSourceCatalog.sameRecording(original, remix), "no remix substitution")
        assertTrue(!MultiSourceCatalog.sameRecording(original, different), "no duration mismatch")

        let known = MusicTrack(id: "IJKLmn_1234", title: "Mask Off", artist: "Future", duration: 205)
        let ordered = OfficialCatalog.order([known, tracks[0]], query: "Future Mask Off")
        assertTrue(ordered.first?.isYouTubeMusic == true, "music-first if comparable uploads")
        assertTrue(YouTubeMusicCatalog.parse(data: Data("{}".utf8)).isEmpty, "empty response safe")
        print("OK v1.0.6: YouTube Music parser, artwork, official hints, fallback, legacy storage")
    }
}
