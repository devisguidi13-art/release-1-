import Foundation

@main
struct OfficialCoverTests {
    static func main() {
        let unofficial = MusicTrack(id: "unoff000001", title: "Future - Mask Off (Official Audio)", artist: "UserReuploads", duration: 205)
        let topic = MusicTrack(id: "topic000001", title: "Future - Mask Off", artist: "Future - Topic", duration: 204)
        let unrelatedTopic = MusicTrack(id: "topic000002", title: "Future - Another Song", artist: "Future - Topic", duration: 215)
        let vevo = MusicTrack(id: "vevo0000001", title: "Future - Mask Off (Official Video)", artist: "FutureVEVO", duration: 204)
        let query = "Future Mask Off"
        let ranked = OfficialCatalog.order([unofficial, unrelatedTopic, topic], query: query)
        precondition(ranked.first?.id == topic.id, "Prefer Topic for the matching song")
        precondition(!ranked.contains(unofficial), "Prefer official when both uploads share a recording key")
        precondition(ranked.contains(unrelatedTopic), "Other tracks can still appear below accurate matches")
        precondition(OfficialCatalog.sourceConfidence(unofficial) < 30, "User text 'official' is weak evidence")
        let fallback = OfficialCatalog.order([unofficial], query: query)
        precondition(fallback.first?.id == unofficial.id, "Keep reupload fallback when no distribution source is present")
        let vevoRank = OfficialCatalog.order([unofficial, vevo], query: query)
        precondition(vevoRank.first?.id == vevo.id, "Prefer a matched VEVO uploader")
        precondition(CoverArtMatching.identity(unofficial)?.artist == "Future", "Parse real artist from reupload title")
        precondition(CoverArtMatching.identity(unofficial)?.title == "Mask Off", "Strip video annotation from cover search")
        let fake = MusicTrack(id: "fake0000001", title: "Music Reaction", artist: "YouTube", duration: 180)
        precondition(CoverArtMatching.identity(fake) == nil, "Never match reaction video to artwork")
        let groupID = "123e4567-e89b-12d3-a456-426614174000"
        let wrongID = "123e4567-e89b-12d3-a456-426614174111"
        let releaseJSON = """
        {"recordings":[
            {"title":"Mask Off", "score":100,
             "artist-credit":[{"name":"Future","artist":{"name":"Future"}}],
             "releases":[{"status":"Official", "release-group":{"id":"\(groupID)","title":"Mask Off","primary-type":"Single"}}]},
            {"title":"Mask Off", "score":100,
             "artist-credit":[{"name":"Imposter"}],
             "releases":[{"status":"Official", "release-group":{"id":"\(wrongID)","title":"Mask Off","primary-type":"Single"}}]}
        ]}
        """
        let groups = CoverArtMatching.releaseGroupIDs(from: Data(releaseJSON.utf8), artist: "Future", title: "Mask Off")
        precondition(groups == [groupID], "Reject right-title/wrong-artist covers")
        let imageManifest = """
        {"images":[{"front":false,"thumbnails":{"500":"https://coverartarchive.org/bad.jpg"}},
                   {"front":true,"thumbnails":{"500":"http://coverartarchive.org/release/a/cover-500.jpg"}}]}
        """
        let url = CoverArtMatching.frontThumbnailURL(from: Data(imageManifest.utf8))
        precondition(url?.absoluteString == "https://coverartarchive.org/release/a/cover-500.jpg")
        print("OK 1.0.2: official-first ranking, user fallback, artist/title cover match, CAA front image")
    }
}
