import Foundation

enum MusicMetadata {
    static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Video titles and upload channels are not guaranteed to contain correct track metadata.
    /// Normalize conservatively: never claim that the catalog supplies an audio fingerprint.
    static func identity(for track: MusicTrack) -> (artist: String, title: String) {
        var title = track.title
            .replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
        let noise = ["official music video", "official video", "official audio", "official lyric video",
                     "lyrics video", "lyric video", "official visualizer", "visualizer",
                     "audio only", "official music", "official mv", "hd", "4k"]
        for phrase in noise {
            title = title.replacingOccurrences(
                of: "\\s*[\\(\\[]\\s*" + NSRegularExpression.escapedPattern(for: phrase) + "\\s*[\\)\\]]",
                with: "", options: [.regularExpression, .caseInsensitive])
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var artist = track.artist.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
        if let range = title.range(of: " - ") {
            let left = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let author = normalized(artist)
            let proposed = normalized(left)
            if !left.isEmpty && !right.isEmpty && left.count < 65 &&
               (author.contains(proposed) || author == "youtube" || author.contains("vevo") ||
                author.contains("records") || author.contains("music") ||
                // A user reupload often carries the actual artist in its title.
                // Preserve that identity for duplicate suppression and cover lookup.
                (left.split(separator: " ").count <= 5 && !["reaction", "review", "live", "cover"]
                    .contains(where: { proposed.contains($0) }))) {
                artist = left
                title = right
            }
        }
        return (artist.trimmingCharacters(in: .whitespacesAndNewlines),
                title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func words(_ input: String) -> Set<String> {
        let stop: Set<String> = ["official", "music", "video", "audio", "prod", "feat", "ft", "with",
                                  "lyrics", "lyric", "visualizer", "remastered", "version", "original", "topic"]
        return Set(normalized(input).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) })
    }

    static func canonicalKey(_ track: MusicTrack) -> String {
        let info = identity(for: track)
        return canonicalKey(artist: info.artist, title: info.title)
    }

    static func canonicalKey(artist: String, title: String) -> String {
        let cleanArtist = normalized(artist).replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        let cleanTitle = normalized(title)
            .replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*(official|lyric|audio|video|visualizer|remaster)[^\\)\\]]*[\\)\\]]", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        return "\(cleanArtist.trimmingCharacters(in: .whitespaces))|\(cleanTitle.trimmingCharacters(in: .whitespaces))"
    }

    static func titleMatch(_ requested: String, candidate: String) -> Double {
        let left = words(requested)
        let right = words(candidate)
        if left.isEmpty || right.isEmpty { return 0 }
        let overlap = Double(left.intersection(right).count)
        let precision = overlap / Double(right.count)
        let recall = overlap / Double(left.count)
        let f1 = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
        if normalized(requested) == normalized(candidate) { return 1 }
        return f1
    }

    static func artistMatch(_ requested: String, candidate: MusicTrack) -> Bool {
        let requested = normalized(requested)
        guard requested.count >= 2 else { return false }
        let info = identity(for: candidate)
        let artist = normalized(info.artist)
        let title = normalized(candidate.title)
        return artist == requested || artist.hasPrefix(requested + "vevo") ||
            artist.hasPrefix(requested + " - topic") || title.hasPrefix(requested + " - ") ||
            title.hasPrefix(requested + " – ")
    }

    static func isMusic(_ track: MusicTrack) -> Bool {
        let text = normalized(track.title)
        let bad = ["reaction", "interview", "podcast", "review", "tutorial", "behind the scenes",
                   "live stream", "1 hour", "10 hours", "full album", "compilation", "karaoke", "cover by",
                   "nightcore", "sped up", "slowed + reverb", "type beat", "instrumental remake",
                   "how to", "slowed reverb", "8d audio", "fan made"]
        return !bad.contains(where: { text.contains($0) }) &&
               (track.duration == 0 || (track.duration >= 65 && track.duration <= 660))
    }
}


/// Preferential source scoring; *not* a claim that YouTube verified a recording.
/// Public catalog search results do not expose a reliable Official Artist Channel flag.
enum OfficialCatalog {
    /// Higher = stronger evidence that the uploader is a music distribution channel.
    /// Official-looking words in a user-uploaded title are weak evidence on their own.
    static func sourceConfidence(_ track: MusicTrack) -> Int {
        let rawChannel = MusicMetadata.normalized(track.artist)
        let title = MusicMetadata.normalized(track.title)
        let info = MusicMetadata.identity(for: track)
        let parsedArtist = MusicMetadata.normalized(info.artist)
        let channelArtist = rawChannel
            .replacingOccurrences(of: " - topic", with: "")
            .replacingOccurrences(of: "vevo", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titleArtist = title.components(separatedBy: " - ").first ?? ""
        // Topic is an auto-generated music-distribution channel; VEVO is a strong hint.
        if rawChannel.hasSuffix(" - topic") { return 100 }
        if rawChannel.hasSuffix("vevo") && !channelArtist.isEmpty &&
            (titleArtist == channelArtist || parsedArtist == channelArtist) { return 90 }
        if rawChannel.hasSuffix("vevo") { return 65 }
        // A song row from YouTube Music has better structured metadata than
        // an arbitrary upload, but is NOT a verified official-artist badge.
        if track.isYouTubeMusic { return 75 }
        // Same-name uploader is useful for ordering but not verified as an OAC.
        if !channelArtist.isEmpty && channelArtist != "youtube" &&
            titleArtist == channelArtist { return 35 }
        if title.contains("official audio") || title.contains("official music video") { return 12 }
        return 0
    }

    /// Relevance is checked before source preference so an unrelated Topic video
    /// cannot defeat the correct song. Within the same recording prefer Topic/VEVO.
    static func queryRelevance(_ track: MusicTrack, query: String) -> Double {
        let requested = MusicMetadata.words(query)
        guard !requested.isEmpty else { return 0 }
        let info = MusicMetadata.identity(for: track)
        let searchable = MusicMetadata.words(info.title + " " + info.artist + " " + track.title)
        return Double(requested.intersection(searchable).count) / Double(requested.count)
    }

    static func order(_ tracks: [MusicTrack], query: String, preferOfficial: Bool = true) -> [MusicTrack] {
        guard preferOfficial else { return tracks }
        var selected: [String: (track: MusicTrack, relevance: Double, confidence: Int, index: Int)] = [:]
        for (index, track) in tracks.enumerated() where MusicMetadata.isMusic(track) {
            let key = MusicMetadata.canonicalKey(track)
            let stableKey = key == "|" ? "video:" + track.id : key
            let relevance = queryRelevance(track, query: query)
            let confidence = sourceConfidence(track)
            if let old = selected[stableKey] {
                // Small metadata relevance variations must not make an unofficial
                // duplicate win over an equally plausible official recording.
                if abs(relevance - old.relevance) <= 0.18 {
                    if confidence < old.confidence ||
                        (confidence == old.confidence && relevance <= old.relevance) { continue }
                } else if relevance <= old.relevance { continue }
            }
            selected[stableKey] = (track, relevance, confidence, index)
        }
        return selected.values.sorted { a, b in
            // Near-exact matches are music-equivalent; prefer their source first.
            let aExact = a.relevance >= 0.90
            let bExact = b.relevance >= 0.90
            if aExact != bExact { return aExact }
            if aExact && bExact && a.confidence != b.confidence {
                return a.confidence > b.confidence
            }
            if a.relevance != b.relevance { return a.relevance > b.relevance }
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.index < b.index
        }.map { $0.track }
    }
}
