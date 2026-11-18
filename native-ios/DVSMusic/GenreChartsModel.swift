import Foundation
import Combine

/// UI cache remains readable offline; refreshes on opening and after 12h,
/// never claims that iOS guarantees scheduled background execution.
@MainActor final class GenreChartsModel: ObservableObject {
    @Published private(set) var snapshots: [String: GenreChartSnapshot] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let ttl: TimeInterval = 12 * 3600
    private var refreshingAll = false
    private let keyPrefix = "dvs.genres.v104."

    init() {
        for genre in DVSGenre.all {
            if let data = UserDefaults.standard.data(forKey: keyPrefix + genre.id),
               let cached = try? JSONDecoder().decode(GenreChartSnapshot.self, from: data) {
                snapshots[genre.id] = cached
            }
        }
    }

    func refresh(_ genre: DVSGenre, force: Bool = false, lastFMKey: String = "") async {
        if loading.contains(genre.id) { return }
        if !force, let existing = snapshots[genre.id],
           Date().timeIntervalSince(existing.refreshedAt) < ttl { return }
        loading.insert(genre.id)
        errors[genre.id] = nil
        let fetched = await GenreChartsService.shared.load(genre, lastFMKey: lastFMKey)
        // Never overwrite a useful snapshot with an empty API response.
        // Empty results are not cached, so a later foreground visit can retry.
        if !fetched.isEmpty {
            snapshots[genre.id] = fetched
            if let data = try? JSONEncoder().encode(fetched) {
                UserDefaults.standard.set(data, forKey: keyPrefix + genre.id)
            }
        } else {
            errors[genre.id] = snapshots[genre.id] == nil
                ? "Catalogo temporaneamente indisponibile. Scorri per riprovare."
                : "Aggiornamento non riuscito. Mostro i dati salvati."
        }
        loading.remove(genre.id)
    }

    /// Opportunistically updates ALL genres while the app is open, respecting
    /// the public API with a pause between requests; iOS can suspend this task.
    func refreshAllDue(lastFMKey: String = "") async {
        guard !refreshingAll else { return }
        refreshingAll = true
        defer { refreshingAll = false }
        for genre in DVSGenre.all {
            if Task.isCancelled { return }
            if let existing = snapshots[genre.id], Date().timeIntervalSince(existing.refreshedAt) < ttl { continue }
            await refresh(genre, lastFMKey: lastFMKey)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }
}
