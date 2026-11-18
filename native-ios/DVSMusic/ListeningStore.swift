import Foundation

struct ListeningRecord: Codable {
    var track: MusicTrack
    var seconds: Double = 0
    var plays: Int = 0
    var skips: Int = 0
    var lastPlayed: Date = .distantPast
}

struct PlaybackEvent: Codable {
    var id: String
    var date: Date
    var seconds: Double
}

struct ListeningSummary {
    let totalMinutes: Int
    let tracksHeard: Int
    let topTracks: [ListeningRecord]
    let topArtists: [(name: String, seconds: Double)]
}

/// Local-only history, saved in UserDefaults. No accounts, analytics server or telemetry.
struct ListeningStore {
    private(set) var records: [String: ListeningRecord] = [:]
    private(set) var daily: [PlaybackEvent] = []
    private(set) var playEvents: [PlayedTrackEntry] = []
    private(set) var blockedIDs: Set<String> = []
    private(set) var blockedCanonicalKeys: Set<String> = []
    private let key = "dvs-listening-v07"
    private let blockedKey = "dvs-blocked-v07"
    private let canonicalBlockedKey = "dvs-blocked-canonical-v10"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            records = saved.records
            daily = saved.daily
            playEvents = saved.playEvents ?? []
        }
        blockedIDs = Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
        blockedCanonicalKeys = Set(UserDefaults.standard.stringArray(forKey: canonicalBlockedKey) ?? [])
        // Backfill canonical exclusions for older blocked tracks whose metadata was saved.
        for id in blockedIDs {
            if let track = records[id]?.track { blockedCanonicalKeys.insert(MusicMetadata.canonicalKey(track)) }
        }
    }

    mutating func began(_ track: MusicTrack) {
        var record = records[track.id] ?? ListeningRecord(track: track)
        record.track = track
        record.plays += 1
        playEvents.insert(PlayedTrackEntry(id: UUID(), track: track, date: Date()), at: 0)
        playEvents = Array(playEvents.prefix(1000))
        record.lastPlayed = Date()
        records[track.id] = record
        save()
    }

    mutating func listened(_ track: MusicTrack, seconds: Double) {
        guard seconds > 0, seconds <= 3 else { return }
        var record = records[track.id] ?? ListeningRecord(track: track)
        record.seconds += seconds
        records[track.id] = record
        let day = Calendar.current.startOfDay(for: Date())
        if let index = daily.firstIndex(where: { $0.id == track.id && Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            daily[index].seconds += seconds
        } else {
            daily.append(PlaybackEvent(id: track.id, date: day, seconds: seconds))
        }
        if let oldest = Calendar.current.date(byAdding: .day, value: -370, to: day) {
            daily = daily.filter { $0.date > oldest }
        }
        // Save at 10-second intervals rather than every player callback.
        if Int(record.seconds) % 10 == 0 { save() }
    }

    mutating func skipped(_ track: MusicTrack) {
        var record = records[track.id] ?? ListeningRecord(track: track)
        record.skips += 1
        records[track.id] = record
        save()
    }

    func isBlocked(_ track: MusicTrack) -> Bool {
        blockedIDs.contains(track.id) || blockedCanonicalKeys.contains(MusicMetadata.canonicalKey(track))
    }

    mutating func setBlocked(_ track: MusicTrack, blocked: Bool) {
        let canonical = MusicMetadata.canonicalKey(track)
        if blocked {
            blockedIDs.insert(track.id)
            blockedCanonicalKeys.insert(canonical)
        } else {
            blockedIDs.remove(track.id)
            blockedCanonicalKeys.remove(canonical)
        }
        UserDefaults.standard.set(Array(blockedIDs), forKey: blockedKey)
        UserDefaults.standard.set(Array(blockedCanonicalKeys), forKey: canonicalBlockedKey)
    }

    func summary() -> ListeningSummary {
        let sorted = records.values.sorted { $0.seconds > $1.seconds }
        var artists: [String: Double] = [:]
        for record in records.values {
            let artist = MusicMetadata.identity(for: record.track).artist
            artists[artist, default: 0] += record.seconds
        }
        return ListeningSummary(totalMinutes: Int(records.values.reduce(0) { $0 + $1.seconds } / 60),
                                tracksHeard: records.values.filter { $0.plays > 0 }.count,
                                topTracks: Array(sorted.prefix(8)),
                                topArtists: artists.map { (name: $0.key, seconds: $0.value) }
                                    .sorted { $0.seconds > $1.seconds }.prefix(8).map { $0 })
    }

    func tracksForToday() -> [MusicTrack] {
        let today = Calendar.current.startOfDay(for: Date())
        return daily.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .sorted { $0.seconds > $1.seconds }.compactMap { records[$0.id]?.track }
    }

    mutating func flush() { save() }

    private struct Snapshot: Codable {
        let records: [String: ListeningRecord]
        let daily: [PlaybackEvent]
        // Optional preserves snapshots encoded by 0.7.
        let playEvents: [PlayedTrackEntry]?
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Snapshot(records: records, daily: daily, playEvents: playEvents)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
