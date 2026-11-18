import Foundation

/// IDs without a prefix are the existing YouTube IDs. This preserves every saved
/// favourite, history entry and playlist from 0.5–1.0.4.
struct MusicTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let duration: Int
    let artworkLink: String?
    /// Search metadata origin. Audio still uses the existing YouTube player.
    let catalogOrigin: String?

    init(id: String, title: String, artist: String, duration: Int, artworkLink: String? = nil, catalogOrigin: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artworkLink = artworkLink
        self.catalogOrigin = catalogOrigin
    }

    var isAudius: Bool { id.hasPrefix("audius:") }
    var isYouTubeMusic: Bool { !isAudius && catalogOrigin == "youtube-music" }
    var sourceLabel: String { isAudius ? "Audius" : (isYouTubeMusic ? "YouTube Music" : "YouTube") }
    var providerID: String { isAudius ? String(id.dropFirst("audius:".count)) : id }

    var artworkURL: URL? {
        if let artworkLink, let url = URL(string: artworkLink), url.scheme == "https" { return url }
        guard !isAudius else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    enum CodingKeys: String, CodingKey { case id, title, artist, duration, artworkLink, catalogOrigin }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        duration = try container.decode(Int.self, forKey: .duration)
        artworkLink = try container.decodeIfPresent(String.self, forKey: .artworkLink)
        catalogOrigin = try container.decodeIfPresent(String.self, forKey: .catalogOrigin)
    }

    static func == (lhs: MusicTrack, rhs: MusicTrack) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct InvidiousVideo: Decodable {
    let type: String?
    let videoId: String?
    let title: String?
    let author: String?
    let lengthSeconds: Int?

    func asTrack() -> MusicTrack? {
        guard let videoId, videoId.count == 11, let title else { return nil }
        if let type, type != "video" { return nil }
        return MusicTrack(id: videoId, title: title, artist: author ?? "YouTube", duration: lengthSeconds ?? 0)
    }
}

struct InvidiousVideoDetail: Decodable {
    let recommendedVideos: [InvidiousVideo]?
}

enum RepeatSetting: String, CaseIterable {
    case off = "Nessuna"
    case all = "Tutte"
}
