import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var queue: [MusicTrack] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var playing: Bool = false
    @Published private(set) var preparing: Bool = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var errorMessage: String? = nil
    @Published var shuffle: Bool = false
    @Published var autoRadio: Bool = true
    @Published var repeatSetting: RepeatSetting = .off
    @Published private(set) var favorites: [MusicTrack] = []
    @Published private(set) var recentTracks: [MusicTrack] = []
    @Published private(set) var playlists: [MusicPlaylist] = []
    @Published var smartRadio: Bool = true
    @Published private(set) var sleepDeadline: Date? = nil
    @Published private(set) var sleepAtTrackEnd = false
    @Published private(set) var listeningVersion = 0
    @Published var lastFMKey: String = ""
    @Published private(set) var selectedMood: DVSMood? = nil
    @Published private(set) var moodLoading = false
    @Published private(set) var preparedNextCount = 0
    @Published private(set) var findingNextTracks = false
    @Published private(set) var exploration: Double = 0.35
    @Published private(set) var nightMode = false
    @Published private(set) var smartRules: [SmartPlaylistRule] = []
    private(set) var listeningStore = ListeningStore()
    private var lastTick = Date()
    private var radioAnchor: MusicTrack?

    var listeningSummary: ListeningSummary { listeningStore.summary() }
    var playHistory: [PlayedTrackEntry] { listeningStore.playEvents }

    func autoTracks(for group: DVSAutoCollection) -> [MusicTrack] {
        SmartLibrary.automatic(group, records: listeningStore.records, favorites: favorites, blocked: blockedIDs)
    }
    func tracks(for rule: SmartPlaylistRule) -> [MusicTrack] {
        SmartLibrary.matching(rule, records: listeningStore.records, favorites: favorites, blocked: blockedIDs)
    }
    func addSmartRule(_ rule: SmartPlaylistRule) {
        smartRules.append(rule)
        persist(smartRules, as: "dvs-smart-playlists-v08")
    }
    func removeSmartRule(_ id: UUID) {
        smartRules.removeAll { $0.id == id }
        persist(smartRules, as: "dvs-smart-playlists-v08")
    }
    func setExploration(_ value: Double) {
        exploration = min(1, max(0, value))
        UserDefaults.standard.set(exploration, forKey: "dvs-exploration-v08")
        if shuffle { setSmartShuffle(true) }
    }
    func setNightMode(_ enabled: Bool) {
        nightMode = enabled
        UserDefaults.standard.set(enabled, forKey: "dvs-night-mode-v08")
    }

    /// Mood selections are made from real catalog searches; no fabricated audio analysis.
    func startMood(_ mood: DVSMood) {
        selectedMood = mood
        UserDefaults.standard.set(mood.rawValue, forKey: "dvs-selected-mood-v08")
        moodLoading = true
        Task {
            let catalog = MultiSourceCatalog()
            var found: [MusicTrack] = []
            var known = blockedIDs
            for text in mood.searches {
                if let tracks = try? await catalog.search(text) {
                    for track in tracks where MusicMetadata.isMusic(track) && !isBlocked(track) && known.insert(track.id).inserted {
                        found.append(track)
                    }
                }
            }
            moodLoading = false
            guard !found.isEmpty else {
                errorMessage = "Non trovo brani per questo mood. Riprova più tardi."
                return
            }
            let ordered = recommendations.smartOrder(found, following: current,
                favorites: favorites, history: listeningStore.records, exploration: exploration,
                blockedCanonical: listeningStore.blockedCanonicalKeys)
            radioAnchor = ordered.first
            autoRadio = true
            smartRadio = true
            restart(with: Array(ordered.prefix(24)))
        }
    }

    func discoverTracks() async -> [MusicTrack] {
        let seen = blockedIDs.union(listeningStore.records.keys).union(queue.map(\.id))
        if let anchor = current ?? favorites.first ?? recentTracks.first {
            let candidates = await recommendations.recommendations(near: anchor, excluding: seen,
                favorites: favorites, history: listeningStore.records, apiKey: lastFMKey,
                exploration: max(0.8, exploration),
                blockedCanonical: listeningStore.blockedCanonicalKeys)
            if !candidates.isEmpty { return candidates }
        }
        let search = selectedMood?.searches.first ?? "new music official audio"
        let result = (try? await MultiSourceCatalog().search(search)) ?? []
        return Array(result.filter { MusicMetadata.isMusic($0) && !seen.contains($0.id) && !isBlocked($0) }.prefix(20))
    }
    var blockedIDs: Set<String> { listeningStore.blockedIDs }
    func isBlocked(_ track: MusicTrack) -> Bool { listeningStore.isBlocked(track) }
    var sleepRemaining: Int? { sleepDeadline.map { max(0, Int($0.timeIntervalSinceNow)) } }

    let player = AVQueuePlayer()
    private let resolver = AudioResolver()
    private let alternativeCatalog = MultiSourceCatalog()
    private var failedOriginIDs = Set<String>()
    private var recoveringOriginIDs = Set<String>()
    private var statusObserver: NSKeyValueObservation?
    private let recommendations = RecommendationEngine()
    private var itemIndexByID: [ObjectIdentifier: Int] = [:]
    private var queuedIndices = Set<Int>()
    private var failedIndices = Set<Int>()
    private var session = UUID()
    private var filling = false
    private var fillingOwner = UUID()
    private var radioLoading = false
    private var radioTask: Task<Void, Never>?
    private var radioGeneration = 0
    private var refillRequested = false
    private var prefetchGeneration = 0
    private var radioRetryAt: Date = .distantPast
    private var waitingForAutoplay = false
    private var observedItem: NSKeyValueObservation?
    private var timeObserver: Any?
    private var sleepCheckTimer: Timer?
    private var finishObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var currentLockScreenArtwork: MPMediaItemArtwork?
    private var currentArtworkTrackID: String?
    private var lockScreenArtworkTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var audioInterrupted = false
    private var resumeWhenInterruptionEnds = false

    var current: MusicTrack? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }
    var duration: Double {
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            return duration
        }
        return Double(current?.duration ?? 0)
    }

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { errorMessage = "Sessione audio: \(error.localizedDescription)" }
        player.automaticallyWaitsToMinimizeStalling = true
        if let saved = UserDefaults.standard.data(forKey: "dvs-native-favorites"),
           let value = try? JSONDecoder().decode([MusicTrack].self, from: saved) {
            favorites = value
        }
        if let saved = UserDefaults.standard.data(forKey: "dvs-recent-v06"),
           let value = try? JSONDecoder().decode([MusicTrack].self, from: saved) { recentTracks = value }
        if let saved = UserDefaults.standard.data(forKey: "dvs-playlists-v06"),
           let value = try? JSONDecoder().decode([MusicPlaylist].self, from: saved) { playlists = value }
        smartRadio = UserDefaults.standard.object(forKey: "dvs-smart-v06") as? Bool ?? true
        lastFMKey = UserDefaults.standard.string(forKey: "dvs-lastfm-api-v07") ?? ""
        exploration = UserDefaults.standard.object(forKey: "dvs-exploration-v08") as? Double ?? 0.35
        nightMode = UserDefaults.standard.bool(forKey: "dvs-night-mode-v08")
        selectedMood = UserDefaults.standard.string(forKey: "dvs-selected-mood-v08").flatMap(DVSMood.init(rawValue:))
        if let data = UserDefaults.standard.data(forKey: "dvs-smart-playlists-v08"),
           let rules = try? JSONDecoder().decode([SmartPlaylistRule].self, from: data) { smartRules = rules }
        observedItem = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.itemChanged() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed = max(0, time.seconds.isFinite ? time.seconds : 0)
                self.tickListeningAndTimer()
                self.updateNowPlaying()
            }
        }
        finishObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.sleepAtTrackEnd { self.cancelSleepTimer(); self.pause() }
                self.itemChanged()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let failed = note.object as? AVPlayerItem,
                      failed === self.player.currentItem else { return }
                await self.handleActiveStreamFailure(failed)
            }
        }
        sleepCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkSleepDeadline() }
        }
        observeAudioInterruptions()
        setupRemoteCommands()
    }

    deinit {
        lockScreenArtworkTask?.cancel()
        sleepCheckTimer?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    func toggleFavorite(_ track: MusicTrack) {
        if favorites.contains(track) { favorites.removeAll { $0.id == track.id } }
        else { favorites.insert(track, at: 0) }
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: "dvs-native-favorites")
        }
    }

    func isFavorite(_ track: MusicTrack) -> Bool { favorites.contains(track) }

    func remember(_ track: MusicTrack) {
        listeningStore.began(track)
        refreshLockScreenArtwork(for: track)
        listeningVersion += 1
        recentTracks.removeAll { $0.id == track.id }
        recentTracks.insert(track, at: 0)
        recentTracks = Array(recentTracks.prefix(30))
        persist(recentTracks, as: "dvs-recent-v06")
    }

    func createPlaylist(named name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        playlists.append(MusicPlaylist(id: UUID(), name: title, tracks: []))
        persist(playlists, as: "dvs-playlists-v06")
    }

    func addToPlaylist(_ track: MusicTrack, playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[i].tracks.contains(track) else { return }
        playlists[i].tracks.append(track)
        persist(playlists, as: "dvs-playlists-v06")
    }

    func removeFromPlaylist(_ track: MusicTrack, playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].tracks.removeAll { $0.id == track.id }
        persist(playlists, as: "dvs-playlists-v06")
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        persist(playlists, as: "dvs-playlists-v06")
    }

    func setSmartRadio(_ enabled: Bool) {
        smartRadio = enabled
        UserDefaults.standard.set(enabled, forKey: "dvs-smart-v06")
        if enabled { scheduleRadioIfNeeded() }
        else {
            radioGeneration += 1
            radioTask?.cancel()
            radioTask = nil
            radioLoading = false
            findingNextTracks = false
            waitingForAutoplay = false
        }
    }

    func setLastFMKey(_ key: String) {
        lastFMKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(lastFMKey, forKey: "dvs-lastfm-api-v07")
        radioRetryAt = .distantPast
        scheduleRadioIfNeeded()
    }

    func setSmartShuffle(_ enabled: Bool) {
        shuffle = enabled
        guard enabled, queue.indices.contains(currentIndex + 1) else { return }
        let future = Array(queue[(currentIndex + 1)...])
        let sorted = recommendations.smartOrder(future, following: current, favorites: favorites,
                                                history: listeningStore.records, exploration: exploration,
                                                blockedCanonical: listeningStore.blockedCanonicalKeys)
        queue.replaceSubrange((currentIndex + 1)..<queue.count, with: sorted)
        rebuildUpcoming()
    }

    func startRadio(from track: MusicTrack) {
        autoRadio = true
        smartRadio = true
        radioAnchor = track
        restart(with: [track])
    }

    func startDailyMix(_ type: Int) {
        var seeds = favorites + recentTracks.filter { !favorites.contains($0) }
        seeds = seeds.filter { !isBlocked($0) }
        guard !seeds.isEmpty else { return }
        // Consistent day-specific order: mixes naturally change each morning.
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        seeds.sort { lhs, rhs in
            let l = (lhs.id.unicodeScalars.reduce(day + type * 41) { $0 &+ Int($1.value) * 13 }) % 1009
            let r = (rhs.id.unicodeScalars.reduce(day + type * 41) { $0 &+ Int($1.value) * 13 }) % 1009
            return l < r
        }
        switch type {
        case 1:
            // Discovery starts with a listening-history seed but prioritizes new recommendations.
            seeds = Array(seeds.prefix(2))
        case 2:
            seeds = Array(seeds.reversed().prefix(10))
        default:
            seeds = Array(seeds.prefix(12))
        }
        radioAnchor = seeds.first
        autoRadio = true
        smartRadio = true
        restart(with: seeds)
    }

    func rejectDiscovery(_ track: MusicTrack) {
        listeningStore.skipped(track)
        listeningVersion += 1
    }

    func setBlocked(_ track: MusicTrack, blocked: Bool = true) {
        listeningStore.setBlocked(track, blocked: blocked)
        listeningVersion += 1
        if blocked {
            for index in queue.indices.reversed() where index > currentIndex && isBlocked(queue[index]) {
                queue.remove(at: index)
            }
            rebuildUpcoming()
        }
    }

    func setSleepTimer(minutes: Int) {
        guard minutes > 0 else { cancelSleepTimer(); return }
        let wasTrackEnd = sleepAtTrackEnd
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepAtTrackEnd = false
        if wasTrackEnd { resumePrefetchAfterTimer() }
    }

    func setSleepAtTrackEnd() {
        sleepDeadline = nil
        sleepAtTrackEnd = true
        // Prevent AVQueuePlayer automatically entering the next prefetched song.
        prefetchGeneration += 1
        if let now = player.currentItem {
            for item in player.items() where item !== now { player.remove(item) }
            itemIndexByID = [ObjectIdentifier(now): currentIndex]
            queuedIndices = [currentIndex]
            preparedNextCount = 0
        }
    }

    func cancelSleepTimer() {
        let wasTrackEnd = sleepAtTrackEnd
        sleepDeadline = nil
        sleepAtTrackEnd = false
        if wasTrackEnd { resumePrefetchAfterTimer() }
    }

    private func resumePrefetchAfterTimer() {
        guard player.currentItem != nil else { return }
        if filling { refillRequested = true }
        else { Task { await fillAhead() } }
    }

    private func checkSleepDeadline() {
        guard let deadline = sleepDeadline, Date() >= deadline else { return }
        cancelSleepTimer()
        pause()
        listeningStore.flush()
    }

    private func tickListeningAndTimer() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        if playing, player.timeControlStatus == .playing, let current, delta > 0, delta < 3 {
            listeningStore.listened(current, seconds: delta)
            if Int(listeningStore.records[current.id]?.seconds ?? 0) % 10 == 0 { listeningVersion += 1 }
        }
        if autoRadio && smartRadio && playing && queue.count - currentIndex < 7 && !radioLoading {
            scheduleRadioIfNeeded()
        }
        checkSleepDeadline()
    }

    private func persist<T: Encodable>(_ value: T, as key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Rebuild only the prefetched future items, without stopping the playing song.
    private func rebuildUpcoming() {
        guard let now = player.currentItem else { return }
        prefetchGeneration += 1
        for item in player.items() where item !== now { player.remove(item) }
        itemIndexByID = [ObjectIdentifier(now): currentIndex]
        queuedIndices = [currentIndex]
        failedIndices.removeAll()
        preparedNextCount = 0
        if filling { refillRequested = true } else { Task { await fillAhead() } }
        scheduleRadioIfNeeded()
    }

    func moveUpcoming(at index: Int, by delta: Int) {
        let destination = index + delta
        guard index > currentIndex, queue.indices.contains(index),
              destination > currentIndex, queue.indices.contains(destination) else { return }
        let track = queue.remove(at: index)
        queue.insert(track, at: destination)
        rebuildUpcoming()
    }

    func removeUpcoming(at index: Int) {
        guard index > currentIndex, queue.indices.contains(index) else { return }
        queue.remove(at: index)
        rebuildUpcoming()
    }

    func playSelection(_ source: [MusicTrack], selected: MusicTrack) {
        guard let start = source.firstIndex(of: selected) else { return }
        let selectedFirst = Array(source[start...]) + Array(source[..<start])
        let rest = Array(selectedFirst.dropFirst())
        let ordered = [selectedFirst[0]] + (shuffle ? recommendations.smartOrder(rest,
            following: selectedFirst[0], favorites: favorites, history: listeningStore.records, exploration: exploration) : rest)
        restart(with: ordered)
    }

    func append(_ track: MusicTrack) {
        if queue.isEmpty { restart(with: [track]); return }
        if !queue.contains(track) {
            queue.append(track)
            Task { await fillAhead() }
        }
    }

    private func restart(with tracks: [MusicTrack], preservingFailures: Bool = false) {
        if !preservingFailures {
            failedOriginIDs.removeAll()
            recoveringOriginIDs.removeAll()
        }
        // A deliberate selection overrides any pending automatic interruption resume.
        resumeWhenInterruptionEnds = false
        session = UUID()
        radioGeneration += 1
        radioTask?.cancel()
        radioTask = nil
        player.pause()
        player.removeAllItems()
        radioLoading = false
        findingNextTracks = false
        radioRetryAt = .distantPast
        waitingForAutoplay = false
        preparedNextCount = 0
        refillRequested = false
        prefetchGeneration += 1
        lastTick = Date()
        itemIndexByID.removeAll()
        queuedIndices.removeAll()
        failedIndices.removeAll()
        queue = tracks
        currentIndex = 0
        elapsed = 0
        playing = false
        preparing = true
        errorMessage = nil
        fillingOwner = UUID()  // old async tasks must not reset the new prefetch state
        filling = false
        let request = session
        Task { await prepareFirst(sessionID: request) }
        // Start music discovery immediately. It NEVER blocks initial playback.
        scheduleRadioIfNeeded()
    }

    private func prepareFirst(sessionID request: UUID) async {
        guard let first = queue.first else { preparing = false; return }
        do {
            let item = try await resolver.playerItem(for: first)
            guard session == request else { return }
            itemIndexByID[ObjectIdentifier(item)] = 0
            queuedIndices.insert(0)
            player.insert(item, after: nil)
            preparing = false
            itemChanged()  // Install status observation even if the first KVO event ran early.
            if audioInterrupted {
                // iOS owns the session (e.g. WhatsApp). Start when it releases it.
                resumeWhenInterruptionEnds = true
                playing = false
            } else {
                player.play()
                playing = true
            }
            updateNowPlaying()
            remember(first)
            Task { await fillAhead() }
        } catch {
            guard session == request else { return }
            if await recoverAlternative(for: first, expectedSession: request) { return }
            guard session == request else { return }
            preparing = false
            playing = false
            errorMessage = "Audio non disponibile: \(error.localizedDescription)"
            // One unavailable recording must not end an existing playlist.
            if queue.count > 1 { restart(with: Array(queue.dropFirst())) }
            else {
                waitingForAutoplay = autoRadio && smartRadio
                scheduleRadioIfNeeded()
            }
        }
    }

    /// If the current recording fails, find only the same recording from
    /// another search result or origin. Never substitute a random remix or open an external app.
    private func recoverAlternative(for track: MusicTrack, expectedSession request: UUID) async -> Bool {
        guard session == request else { return false }
        // A second AVPlayer notification during lookup must not skip the song.
        if recoveringOriginIDs.contains(track.id) { return true }
        guard !failedOriginIDs.contains(track.id) else { return false }
        recoveringOriginIDs.insert(track.id)
        failedOriginIDs.insert(track.id)
        defer { recoveringOriginIDs.remove(track.id) }
        guard let alternate = await alternativeCatalog.alternative(to: track),
              session == request, !failedOriginIDs.contains(alternate.id) else { return false }
        errorMessage = "Provo la stessa registrazione da \(alternate.sourceLabel)."
        let remaining = queue.indices.contains(currentIndex) ? Array(queue.dropFirst(currentIndex + 1)) : []
        restart(with: [alternate] + remaining, preservingFailures: true)
        return true
    }

    private func handleActiveStreamFailure(_ item: AVPlayerItem) async {
        guard item === player.currentItem, let track = current else { return }
        let request = session
        if await recoverAlternative(for: track, expectedSession: request) { return }
        guard request == session else { return }
        errorMessage = "Stream non disponibile sulle sorgenti accessibili: passo al prossimo brano."
        next()
    }

    private func itemChanged() {
        guard !preparing else { return }
        guard let item = player.currentItem else {
            statusObserver?.invalidate()
            statusObserver = nil
            preparedNextCount = 0
            playing = false
            updateNowPlaying()
            // Honor sleep-at-end before starting another track.
            if sleepAtTrackEnd { cancelSleepTimer(); return }
            if (autoRadio && smartRadio) || repeatSetting == .all {
                let nextIndex = currentIndex + 1 < queue.count
                    ? (currentIndex + 1..<queue.count).first { !failedIndices.contains($0) }
                    : nil
                if let nextIndex {
                    restart(with: Array(queue[nextIndex...]))
                    return
                }
                waitingForAutoplay = true
                if !radioLoading { scheduleRadioIfNeeded() }
            }
            return
        }
        guard let index = itemIndexByID[ObjectIdentifier(item)], queue.indices.contains(index) else { return }
        // Observe actual AVPlayerItem failures (HTTP errors can occur after resolve).
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === self.player.currentItem else { return }
                await self.handleActiveStreamFailure(item)
            }
        }
        if index != currentIndex {
            currentIndex = index
            elapsed = 0
            remember(queue[index])
        }
        waitingForAutoplay = false
        preparedNextCount = max(0, player.items().count - 1)
        playing = player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
        scheduleRadioIfNeeded()
        Task { await fillAhead() }
    }

    /// New radio candidates load in a *separate task* and never block AVQueuePlayer's
    /// already-known next item. This is the key gap/freeze fix compared with 0.8.
    private func scheduleRadioIfNeeded() {
        guard autoRadio && smartRadio && repeatSetting != .all && !radioLoading,
              Date() >= radioRetryAt,
              queue.count - currentIndex < 7,
              let anchor = queue.last ?? current ?? radioAnchor else { return }
        radioLoading = true
        findingNextTracks = true
        radioGeneration += 1
        let generation = radioGeneration
        let request = session
        let known = Set(queue.map(\.id))
            .union(recentTracks.prefix(20).map(\.id))
            .union(blockedIDs)
        let favoritesSnapshot = favorites
        let historySnapshot = listeningStore.records
        let apiKey = lastFMKey
        let degree = exploration
        let blockedKeys = listeningStore.blockedCanonicalKeys
        radioTask = Task { [weak self] in
            guard let self else { return }
            let found = await recommendations.recommendations(near: anchor, excluding: known,
                favorites: favoritesSnapshot, history: historySnapshot,
                apiKey: apiKey, exploration: degree,
                blockedCanonical: blockedKeys)
            guard session == request, radioGeneration == generation else { return }
            radioLoading = false
            findingNextTracks = false
            guard autoRadio && smartRadio else { return }
            // Canonical matching also filters a song uploaded by two video channels.
            var canonical = Set(queue.map { MusicMetadata.canonicalKey($0) })
                .union(recentTracks.prefix(15).map { MusicMetadata.canonicalKey($0) })
            var additions = found.filter { candidate in
                MusicMetadata.isMusic(candidate) && !isBlocked(candidate) &&
                canonical.insert(MusicMetadata.canonicalKey(candidate)).inserted
            }
            if additions.isEmpty {
                // Offline fallback: *known playable* library content, without repeats.
                let offline = favoritesSnapshot + recentTracks
                additions = recommendations.smartOrder(offline.filter { candidate in
                    !isBlocked(candidate) &&
                    canonical.insert(MusicMetadata.canonicalKey(candidate)).inserted
                }, following: anchor, favorites: favoritesSnapshot,
                history: historySnapshot, exploration: degree, blockedCanonical: blockedKeys)
            }
            if !additions.isEmpty {
                radioRetryAt = .distantPast
                // Style-led playback: avoid same-artist streaks between picks.
                additions = recommendations.smartOrder(additions, following: queue.last,
                    favorites: favoritesSnapshot, history: historySnapshot,
                    exploration: degree, blockedCanonical: blockedKeys)
                queue.append(contentsOf: additions.prefix(18))
                if waitingForAutoplay && player.currentItem == nil {
                    waitingForAutoplay = false
                    // Start the next song rather than leaving the user with a silent queue.
                    restart(with: additions)
                } else if filling { refillRequested = true }
                else { Task { await fillAhead() } }
            } else {
                radioRetryAt = Date().addingTimeInterval(30)
                if waitingForAutoplay {
                    errorMessage = "Non trovo altri brani disponibili. Prova un altro brano o la chiave Last.fm gratuita."
                }
            }
        }
    }

    /// Resolve video stream URLs in advance. The active track is never interrupted.
    /// Recommendation requests run independently; only existing items are prepared here.
    private func fillAhead() async {
        guard !filling, !sleepAtTrackEnd, player.currentItem != nil else { return }
        filling = true
        let owner = UUID()
        fillingOwner = owner
        defer {
            if fillingOwner == owner {
                filling = false
                if refillRequested {
                    refillRequested = false
                    Task { await fillAhead() }
                }
            }
        }
        let request = session
        let generation = prefetchGeneration
        scheduleRadioIfNeeded()
        if repeatSetting == .all && queue.count - currentIndex < 5 && !queue.isEmpty {
            queue.append(contentsOf: Array(queue.prefix(min(18, queue.count))))
        }
        let upper = min(queue.count, currentIndex + 5)
        guard currentIndex + 1 < upper else { return }
        for idx in (currentIndex + 1)..<upper {
            guard session == request, !sleepAtTrackEnd else { return }
            if generation != prefetchGeneration { refillRequested = true; return }
            if queuedIndices.contains(idx) || failedIndices.contains(idx) { continue }
            do {
                let item = try await resolver.playerItem(for: queue[idx])
                guard session == request, !sleepAtTrackEnd else { return }
                if generation != prefetchGeneration { refillRequested = true; return }
                // Playback may have advanced while the stream was being resolved.
                guard idx > currentIndex, player.currentItem != nil else { continue }
                itemIndexByID[ObjectIdentifier(item)] = idx
                queuedIndices.insert(idx)
                player.insert(item, after: nil)
                preparedNextCount = max(0, player.items().count - 1)
            } catch {
                guard session == request, generation == prefetchGeneration,
                      queue.indices.contains(idx) else { return }
                // Prefetch needs the same cross-origin fallback as the active item.
                let original = queue[idx]
                failedOriginIDs.insert(original.id)
                if let alternate = await alternativeCatalog.alternative(to: original),
                   session == request, generation == prefetchGeneration,
                   queue.indices.contains(idx), queue[idx].id == original.id,
                   !failedOriginIDs.contains(alternate.id) {
                    queue[idx] = alternate
                    do {
                        let item = try await resolver.playerItem(for: alternate)
                        guard session == request, generation == prefetchGeneration,
                              queue.indices.contains(idx), queue[idx].id == alternate.id else { return }
                        if idx > currentIndex, player.currentItem != nil {
                            itemIndexByID[ObjectIdentifier(item)] = idx
                            queuedIndices.insert(idx)
                            player.insert(item, after: nil)
                            preparedNextCount = max(0, player.items().count - 1)
                            continue
                        }
                    } catch { failedOriginIDs.insert(alternate.id) }
                }
                guard session == request else { return }
                failedIndices.insert(idx)
            }
        }
    }

    func togglePlayback() {
        if playing { pause() } else { resume() }
    }

    func pause() {
        // A manual pause must never be reversed by a delayed WhatsApp interruption end.
        resumeWhenInterruptionEnds = false
        player.pause()
        playing = false
        waitingForAutoplay = false
        listeningStore.flush()
        updateNowPlaying()
    }

    func resume() {
        if audioInterrupted {
            resumeWhenInterruptionEnds = true
            return
        }
        resumeWhenInterruptionEnds = false
        lastTick = Date()
        player.play()
        playing = true
        updateNowPlaying()
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleAudioInterruption(notification) }
        }
        // Some audio apps return control via app focus rather than an interruption-end
        // notification. Only resume if we had actually been interrupted while playing.
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.resumeWhenInterruptionEnds, !self.audioInterrupted else { return }
                self.reactivateAudioAndResume()
            }
        }
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            resumeWhenInterruptionEnds = playing || preparing || resumeWhenInterruptionEnds
            audioInterrupted = true
            player.pause()
            playing = false
            listeningStore.flush()
            updateNowPlaying()
        case .ended:
            audioInterrupted = false
            let flags = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            // iOS explicitly authorizes resuming, or another app has already
            // released audio focus. Never seize the session during a phone call.
            guard resumeWhenInterruptionEnds else { return }
            if flags.contains(.shouldResume) || !AVAudioSession.sharedInstance().isOtherAudioPlaying {
                reactivateAudioAndResume()
            }
            // The other app may still hold audio focus briefly after .ended.
            // Retry only while the same interrupted playback is still pending.
            if resumeWhenInterruptionEnds {
                updateNowPlaying()
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 950_000_000)
                    self?.reactivateAudioAndResume()
                }
            }
        @unknown default: break
        }
    }

    private func reactivateAudioAndResume() {
        guard resumeWhenInterruptionEnds && !audioInterrupted,
              !AVAudioSession.sharedInstance().isOtherAudioPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            resumeWhenInterruptionEnds = false
            if player.currentItem != nil { resume() }
            // If the item is still resolving, prepareFirst starts it on completion.
        } catch {
            errorMessage = "Ripresa audio non riuscita: \(error.localizedDescription)"
        }
    }

    func next() {
        if let current, elapsed >= 5 && duration >= 25 && elapsed / duration < 0.45 {
            listeningStore.skipped(current)
            listeningVersion += 1
        }
        if player.items().count > 1 {
            player.advanceToNextItem()
            if !audioInterrupted { player.play(); playing = true }
            itemChanged()
        } else if queue.indices.contains(currentIndex + 1) {
            let remaining = Array(queue[(currentIndex + 1)...])
            restart(with: remaining)
        } else {
            // If the radio is still searching, remain ready to start on arrival.
            scheduleRadioIfNeeded()
            waitingForAutoplay = autoRadio && smartRadio
            if !waitingForAutoplay {
                player.pause()
                playing = false
                updateNowPlaying()
            }
        }
    }

    func previous() {
        if elapsed > 4 { seek(to: 0); return }
        guard !queue.isEmpty else { return }
        let from = max(0, currentIndex - 1)
        restart(with: Array(queue[from...]))
    }

    /// Swiping right is always an attempt to change to the PREVIOUS song,
    /// not the standard remote-button behavior of restarting the current song.
    func previousFromSwipe() {
        guard let current else { return }
        if currentIndex > 0 {
            restart(with: Array(queue[(currentIndex - 1)...]))
        } else if let previousSong = recentTracks.first(where: {
            MusicMetadata.canonicalKey($0) != MusicMetadata.canonicalKey(current)
        }) {
            let otherTracks = queue.filter {
                MusicMetadata.canonicalKey($0) != MusicMetadata.canonicalKey(previousSong)
            }
            restart(with: [previousSong] + otherTracks)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsed = seconds
        updateNowPlaying()
    }

    func cycleRepeat() {
        repeatSetting = repeatSetting == .off ? .all : .off
        if repeatSetting == .all { Task { await fillAhead() } }
        else { scheduleRadioIfNeeded() }
    }

    private func refreshLockScreenArtwork(for track: MusicTrack) {
        guard currentArtworkTrackID != track.id else { return }
        currentArtworkTrackID = track.id
        currentLockScreenArtwork = nil
        lockScreenArtworkTask?.cancel()
        lockScreenArtworkTask = Task { [weak self] in
            let resolved = await CoverArtService.shared.artworkURL(for: track)
            guard !Task.isCancelled else { return }
            let preferred = resolved ?? track.artworkURL
            guard let preferred else { return }
            // A missing album image falls back to the YouTube thumbnail.
            var data = try? await URLSession.shared.data(from: preferred).0
            if UIImage(data: data ?? Data()) == nil,
               let fallback = track.artworkURL, fallback != preferred {
                data = try? await URLSession.shared.data(from: fallback).0
            }
            guard !Task.isCancelled, let data, let image = UIImage(data: data),
                  let self, self.currentArtworkTrackID == track.id else { return }
            self.currentLockScreenArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork = currentLockScreenArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
    }
}
