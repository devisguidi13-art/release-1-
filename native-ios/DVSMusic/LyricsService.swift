import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Double
    let text: String
}

@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plain: String = ""
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    private var requestID = UUID()
    private var cache: [String: (lines: [LyricLine], plain: String)] = [:]

    private struct Result: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    func load(_ track: MusicTrack) async {
        requestID = UUID()
        let taskID = requestID
        if let cached = cache[track.id] {
            lines = cached.lines; plain = cached.plain; message = ""; busy = false
            return
        }
        busy = true
        lines = []
        plain = ""
        message = ""
        defer { if requestID == taskID { busy = false } }
        let info = MusicMetadata.identity(for: track)
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = [URLQueryItem(name: "track_name", value: info.title),
                          URLQueryItem(name: "artist_name", value: info.artist)]
        guard let address = url.url else { message = "Ricerca testo non disponibile"; return }
        var request = URLRequest(url: address)
        request.timeoutInterval = 10
        request.setValue("DVS-Music/0.7 (personal iOS lyrics client)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard requestID == taskID else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let matches = try JSONDecoder().decode([Result].self, from: data)
            let best = matches.filter { $0.instrumental != true }.sorted { lhs, rhs in
                func rank(_ entry: Result) -> Int {
                    var score = 0
                    if MusicMetadata.normalized(entry.trackName ?? "") == MusicMetadata.normalized(info.title) { score += 5 }
                    if MusicMetadata.normalized(entry.artistName ?? "") == MusicMetadata.normalized(info.artist) { score += 5 }
                    if let duration = entry.duration, track.duration > 0, abs(duration - Double(track.duration)) < 12 { score += 3 }
                    if entry.syncedLyrics != nil { score += 2 }
                    return score
                }
                return rank(lhs) > rank(rhs)
            }.first
            guard let best else { message = "Nessun testo disponibile per questo brano"; return }
            let synced = Self.parseLRC(best.syncedLyrics ?? "")
            let plainText = best.plainLyrics ?? synced.map(\.text).joined(separator: "\n")
            guard !synced.isEmpty || !plainText.isEmpty else { message = "Testo non disponibile"; return }
            lines = synced
            plain = plainText
            cache[track.id] = (lines: synced, plain: plainText)
        } catch {
            guard requestID == taskID else { return }
            message = "Testo momentaneamente non disponibile"
        }
    }

    static func parseLRC(_ content: String) -> [LyricLine] {
        let expression = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var output: [LyricLine] = []
        for line in content.components(separatedBy: .newlines) {
            let ns = line as NSString
            let matches = expression.matches(in: line, range: NSRange(location: 0, length: ns.length))
            let text = expression.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                let fraction: Double
                if match.range(at: 3).location != NSNotFound {
                    let raw = ns.substring(with: match.range(at: 3))
                    fraction = (Double(raw) ?? 0) / pow(10.0, Double(raw.count))
                } else { fraction = 0 }
                output.append(LyricLine(id: output.count, time: minutes * 60 + seconds + fraction, text: text))
            }
        }
        return output.sorted { $0.time < $1.time }
    }
}
