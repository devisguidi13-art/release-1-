import Foundation

/// Mood = search intent, not an assertion about the song's real acoustic properties.
enum DVSMood: String, CaseIterable, Codable, Identifiable {
    case chill = "Chill"
    case sad = "Triste"
    case night = "Notturno"
    case energy = "Energia"
    case love = "Romantico"
    case focus = "Concentrazione"
    case trap = "Trap"
    case indie = "Indie"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .chill: return "cloud.fill"
        case .sad: return "cloud.rain.fill"
        case .night: return "moon.stars.fill"
        case .energy: return "bolt.fill"
        case .love: return "heart.fill"
        case .focus: return "brain.head.profile"
        case .trap: return "flame.fill"
        case .indie: return "guitars.fill"
        }
    }
    var searches: [String] {
        switch self {
        case .chill: return ["chill rnb songs", "chill indie music"]
        case .sad: return ["sad indie songs", "melancholic sad songs"]
        case .night: return ["night drive rnb music", "late night chill songs"]
        case .energy: return ["energetic workout rap songs", "upbeat dance songs"]
        case .love: return ["romantic rnb love songs", "love indie songs"]
        case .focus: return ["lofi instrumental study", "ambient focus music"]
        case .trap: return ["trap 2026 songs", "trap italiana music"]
        case .indie: return ["indie italian music", "indie alternative songs"]
        }
    }
    var description: String {
        switch self {
        case .chill: return "Suoni morbidi per rallentare"
        case .sad: return "Melodie malinconiche"
        case .night: return "Il sound della notte"
        case .energy: return "Alza il ritmo"
        case .love: return "Vibrazioni romantiche"
        case .focus: return "Meno distrazioni"
        case .trap: return "Beat e 808"
        case .indie: return "Nuove atmosfere alternative"
        }
    }
}

struct PlayedTrackEntry: Codable, Identifiable {
    let id: UUID
    let track: MusicTrack
    let date: Date
}

enum DVSAutoCollection: String, CaseIterable, Identifiable {
    case mostPlayed = "Più ascoltati"
    case lastMonth = "Ultimi 30 giorni"
    case favorites = "Preferiti del momento"
    case forgotten = "Da riscoprire"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .mostPlayed: return "chart.bar.fill"
        case .lastMonth: return "calendar"
        case .favorites: return "heart.fill"
        case .forgotten: return "arrow.counterclockwise"
        }
    }
}

/// User-defined local filtering; a smart playlist contains rules, not copied track IDs.
struct SmartPlaylistRule: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var textFilter: String = ""
    var favoritesOnly: Bool = false
    var minimumPlays: Int = 0
    var lastDays: Int = 0
}

struct SmartLibrary {
    static func automatic(_ category: DVSAutoCollection,
                          records: [String: ListeningRecord],
                          favorites: [MusicTrack],
                          blocked: Set<String>, now: Date = Date()) -> [MusicTrack] {
        let values = records.values.filter { $0.plays > 0 && !blocked.contains($0.track.id) }
        let sorted: [MusicTrack]
        switch category {
        case .mostPlayed:
            sorted = values.sorted { $0.plays == $1.plays ? $0.seconds > $1.seconds : $0.plays > $1.plays }
                .map(\.track)
        case .lastMonth:
            let threshold = now.addingTimeInterval(-30 * 86400)
            sorted = values.filter { $0.lastPlayed >= threshold }
                .sorted { $0.lastPlayed > $1.lastPlayed }.map(\.track)
        case .favorites:
            sorted = favorites.filter { !blocked.contains($0.id) }
        case .forgotten:
            let threshold = now.addingTimeInterval(-14 * 86400)
            sorted = values.filter { $0.plays > 0 && $0.lastPlayed < threshold }
                .sorted { $0.plays > $1.plays }.map(\.track)
        }
        return Array(sorted.prefix(100))
    }

    static func matching(_ rule: SmartPlaylistRule,
                         records: [String: ListeningRecord],
                         favorites: [MusicTrack], blocked: Set<String>, now: Date = Date()) -> [MusicTrack] {
        let favoriteIDs = Set(favorites.map(\.id))
        let search = MusicMetadata.normalized(rule.textFilter)
        return records.values.filter { entry in
            guard !blocked.contains(entry.track.id), entry.plays > 0, entry.plays >= rule.minimumPlays else { return false }
            if rule.favoritesOnly && !favoriteIDs.contains(entry.track.id) { return false }
            if rule.lastDays > 0 && entry.lastPlayed < now.addingTimeInterval(-Double(rule.lastDays) * 86400) { return false }
            if !search.isEmpty {
                let text = MusicMetadata.normalized(entry.track.artist + " " + entry.track.title)
                if !text.contains(search) { return false }
            }
            return true
        }.sorted { $0.lastPlayed > $1.lastPlayed }.prefix(150).map(\.track)
    }

    static func history(_ events: [PlayedTrackEntry], query: String) -> [PlayedTrackEntry] {
        let text = MusicMetadata.normalized(query)
        guard !text.isEmpty else { return events }
        return events.filter { MusicMetadata.normalized($0.track.artist + " " + $0.track.title).contains(text) }
    }
}
