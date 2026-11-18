import SwiftUI

private let accent = Color(red: 0.08, green: 0.96, blue: 0.32)
private let base = Color(red: 0.035, green: 0.039, blue: 0.042)
private let panel = Color(red: 0.115, green: 0.12, blue: 0.13)
private let muted = Color.white.opacity(0.62)

private enum MusicTab: String, CaseIterable {
    case home = "Home"
    case search = "Cerca"
    case discover = "Scopri"
    case library = "Libreria"
    case profile = "Profilo"
    case wrapped = "Wrapped"

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .discover: return "sparkles"
        case .library: return "books.vertical.fill"
        case .profile: return "person.crop.circle"
        case .wrapped: return "chart.bar.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: MusicTab = .home
    @State private var query = ""
    @State private var results: [MusicTrack] = []
    @State private var searching = false
    @State private var searchRequestID = UUID()
    @State private var errorText: String?
    @State private var showPlayer = false
    @State private var showQueue = false
    @State private var openQueueAfterPlayerDismiss = false
    @State private var showCreatePlaylist = false
    @State private var playlistName = ""
    @State private var playlistTarget: MusicTrack?
    @State private var showPlaylistOptions = false
    @State private var openedPlaylist: MusicPlaylist?
    @State private var discoveryLabel = ""
    @StateObject private var lyrics = LyricsService()
    @State private var showSleepTimer = false
    @State private var showLyrics = false
    @State private var showWrapped = false
    @State private var customSleepMinutes = "45"
    @State private var lastFMKeyDraft = ""
    @StateObject private var voiceSearch = VoiceSearchService()
    @StateObject private var songIdentifier = SongIdentificationService()
    @StateObject private var artworkPalette = ArtworkPalette()
    @State private var showHistory = false
    @State private var historyQuery = ""
    @State private var showDiscoverySwipe = false
    @State private var swipeTracks: [MusicTrack] = []
    @State private var discoveryBusy = false
    @State private var swipeMessage = ""
    @State private var showSmartCreator = false
    @State private var openedRule: SmartPlaylistRule?
    @State private var openedAutoCollection: DVSAutoCollection?
    @State private var ruleName = ""
    @State private var ruleFilter = ""
    @State private var ruleFavorites = false
    @State private var ruleMinPlays = 0
    @State private var ruleDays = 0
    @State private var resumeAfterMicrophone = false
    @State private var selectedMood: DVSMood = .chill
    @StateObject private var charts = GenreChartsModel()
    @State private var selectedGenre: DVSGenre?
    @State private var selectedGenreSection = 0
    @State private var selectedChartAlbum: GenreChartSong?
    @State private var currentAlbumTracks: [GenreChartSong] = []
    @State private var loadingAlbum = false
    @State private var chartLookupID: String?
    @State private var chartPlaybackMessage: String?

    private let catalog = MultiSourceCatalog()
    private let genres = DVSGenre.all

    var body: some View {
        VStack(spacing: 0) {
            if player.nightMode {
                nightModePage
            } else {
                if tab == .home { header }
                else if tab == .profile || tab == .discover { subsectionNavigation }
                Group {
                    switch tab {
                    case .home: homePage
                    case .search: searchPage
                    case .discover: discoveryPage
                    case .library: libraryPage
                    case .profile: profilePage
                    case .wrapped: wrappedPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if player.current != nil { miniPlayer }
                tabBar
            }
        }
        .background(base.ignoresSafeArea())
        .foregroundStyle(.white)
        .fullScreenCover(isPresented: $showPlayer, onDismiss: {
            if openQueueAfterPlayerDismiss {
                openQueueAfterPlayerDismiss = false
                showQueue = true
            }
        }) { playerSheet }
        .sheet(isPresented: $showQueue) { queueSheet }
        .sheet(isPresented: $showSleepTimer) { sleepTimerSheet }
        .sheet(isPresented: $showLyrics) { lyricsSheet }
        .sheet(isPresented: $showWrapped) { wrappedSheet }
        .sheet(isPresented: $showHistory) { historySheet }
        .sheet(isPresented: $showDiscoverySwipe) { discoverySwipeSheet }
        .sheet(item: $selectedGenre) { genre in genreChartsSheet(genre) }
        .sheet(isPresented: $showSmartCreator) { smartPlaylistCreator }
        .sheet(item: $openedAutoCollection) { group in autoCollectionSheet(group) }
        .sheet(item: $openedRule) { rule in smartPlaylistSheet(rule) }
        .sheet(item: $openedPlaylist) { playlist in playlistDetail(playlist) }
        .onAppear { artworkPalette.load(player.current) }
        .task { await charts.refreshAllDue(lastFMKey: player.lastFMKey) }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                if let selectedGenre {
                    Task { await charts.refresh(selectedGenre, lastFMKey: player.lastFMKey) }
                }
                Task { await charts.refreshAllDue(lastFMKey: player.lastFMKey) }
            }
        }
        .onChange(of: player.current?.id) { _ in artworkPalette.load(player.current) }
        .onChange(of: voiceSearch.finishedText) { result in
            if let result, !result.isEmpty {
                query = result
                tab = .search
                Task { await search() }
            }
        }
        .onChange(of: songIdentifier.identifiedQuery) { result in
            if let result, !result.isEmpty {
                query = result
                tab = .search
                Task { await search() }
            }
        }
        .alert("Nuova playlist", isPresented: $showCreatePlaylist) {
            TextField("Nome della playlist", text: $playlistName)
            Button("Crea") {
                player.createPlaylist(named: playlistName)
                playlistName = ""
            }
            Button("Annulla", role: .cancel) { playlistName = "" }
        } message: { Text("Dai un nome alla tua raccolta") }
        .confirmationDialog("Aggiungi alla playlist", isPresented: $showPlaylistOptions) {
            ForEach(player.playlists) { playlist in
                Button(playlist.name) {
                    if let playlistTarget { player.addToPlaylist(playlistTarget, playlistID: playlist.id) }
                    playlistTarget = nil
                }
            }
            Button("Annulla", role: .cancel) { playlistTarget = nil }
        } message: { Text(player.playlists.isEmpty ? "Crea una playlist dalla Libreria" : "Scegli una playlist") }
    }

    private var subsectionNavigation: some View {
        HStack {
            Button { tab = .home } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
            }.accessibilityLabel("Torna alla Home")
            Spacer()
            Text(tab == .discover ? "DVS Mood e Discovery" : "Il tuo profilo")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(muted)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }.padding(.horizontal, 12).padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image("BrandIcon").resizable().scaledToFit()
                .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7))
            Text("DVS Music").font(.system(size: 19, weight: .heavy, design: .rounded))
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 19))
                    .frame(width: 38, height: 38)
            }.accessibilityLabel("Coda di riproduzione")
            Button { tab = .profile } label: {
                Image(systemName: "gearshape").font(.system(size: 21))
                    .frame(width: 38, height: 38)
            }.accessibilityLabel("Impostazioni e profilo")
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Buongiorno" }
        if hour < 18 { return "Buon pomeriggio" }
        return "Buonasera"
    }

    private var homePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text(greeting).font(.system(size: 30, weight: .bold, design: .rounded))
                    .padding(.top, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        homeChip("Tutto", active: true) { }
                        homeChip("Mood") { tab = .discover }
                        homeChip("Mix") { player.startDailyMix(0) }
                        homeChip("Scopri") { showDiscoverySwipe = true }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    homeShortcut("Preferiti", icon: "heart.fill", tint: .purple) { tab = .library }
                    homeShortcut("Cronologia", icon: "clock.arrow.circlepath", tint: Color.gray) { showHistory = true }
                    homeShortcut("DVS Mix", icon: "waveform", tint: Color(red: 0.04, green: 0.55, blue: 0.32)) { player.startDailyMix(0) }
                    homeShortcut("Replay", icon: "arrow.clockwise", tint: Color(red: 0.34, green: 0.23, blue: 0.44)) { player.startDailyMix(2) }
                    homeShortcut("Scoperte", icon: "sparkles", tint: Color(red: 0.10, green: 0.35, blue: 0.56)) { showDiscoverySwipe = true }
                    homeShortcut("Playlist", icon: "music.note.list", tint: Color(red: 0.05, green: 0.39, blue: 0.24)) { tab = .library }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Nuove uscite e classifiche").font(.system(size: 22, weight: .bold))
                        Spacer()
                        Button { tab = .search } label: {
                            Text("Tutti i generi").font(.caption.weight(.bold)).foregroundStyle(accent)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(Array(genres.prefix(9))) { genre in
                                Button { openGenre(genre) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chart.bar.fill").foregroundStyle(accent)
                                        Text(genre.title).font(.system(size: 12, weight: .semibold))
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 11)
                                    .background(panel, in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Catalogo aggiornabile per ogni genere · ultime pubblicazioni in cima")
                        .font(.caption).foregroundStyle(muted)
                }.padding(.top, 5)
                Text("I tuoi mix di oggi")
                    .font(.system(size: 22, weight: .bold)).padding(.top, 5)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        editorialMixCard("DVS Mix", note: "Una selezione pensata per te", image: "MixDaily", kind: 0)
                        editorialMixCard("Discovery", note: "Nuove scoperte per i tuoi gusti", image: "MixDiscover", kind: 1)
                        editorialMixCard("Replay", note: "I brani che ami di più", image: "MixReplay", kind: 2)
                    }
                }
                HStack {
                    Text("Mood del momento").font(.system(size: 22, weight: .bold))
                    Spacer()
                    Button { tab = .discover } label: {
                        Image(systemName: "chevron.right").foregroundStyle(muted)
                    }.accessibilityLabel("Vedi tutti i mood")
                }.padding(.top, 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach([DVSMood.chill, .sad, .energy, .night, .love]) { mood in
                            moodCard(mood, width: 116, height: 110)
                        }
                    }
                }
                if !player.recentTracks.isEmpty {
                    Text("Ascoltati di recente").font(.system(size: 22, weight: .bold))
                    horizontalTracks(player.recentTracks)
                }
                if !player.favorites.isEmpty {
                    Text("Riascolta i tuoi preferiti").font(.system(size: 22, weight: .bold))
                    horizontalTracks(player.favorites)
                }
                Button { tab = .discover } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("La tua radio intelligente").font(.subheadline.weight(.bold))
                            Text("Esplora i brani simili e scopri nuove atmosfere")
                                .font(.caption).foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(muted)
                    }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.bottom, 25)
        }
    }

    private func homeChip(_ name: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Group {
            if active {
                Text(name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 17).padding(.vertical, 10)
                    .background(accent, in: Capsule())
            } else {
                Button(action: action) {
                    Text(name).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 17).padding(.vertical, 10)
                        .background(panel, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private func homeShortcut(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [tint.opacity(0.82), tint.opacity(0.38)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                }.frame(width: 53, height: 53)
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    .padding(.horizontal, 10)
                Spacer(minLength: 1)
            }.background(panel, in: RoundedRectangle(cornerRadius: 8))
             .clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private func editorialMixCard(_ title: String, note: String, image: String, kind: Int) -> some View {
        Button { player.startDailyMix(kind) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomLeading) {
                    Image(image).resizable().scaledToFill().frame(width: 174, height: 165).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill").font(.system(size: 12))
                                .foregroundStyle(.black).frame(width: 28, height: 28)
                                .background(accent, in: Circle())
                        }
                        Spacer()
                        Text(title).font(.system(size: 17, weight: .bold))
                    }.padding(11)
                }.frame(width: 174, height: 165).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(note).font(.system(size: 11)).foregroundStyle(muted)
                    .lineLimit(2).frame(width: 174, alignment: .leading)
            }.frame(width: 174, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private func moodArtworkName(_ mood: DVSMood) -> String {
        switch mood {
        case .chill: return "MoodChill"
        case .sad: return "MoodSad"
        case .night: return "MoodNight"
        case .energy: return "MoodEnergy"
        case .love: return "MoodLove"
        case .focus: return "MoodFocus"
        case .trap: return "MoodTrap"
        case .indie: return "MoodIndie"
        }
    }

    private func moodCard(_ mood: DVSMood, width: CGFloat, height: CGFloat) -> some View {
        Button { selectedMood = mood; player.startMood(mood) } label: {
            ZStack(alignment: .bottomLeading) {
                Image(moodArtworkName(mood)).resizable().scaledToFill()
                    .frame(width: width, height: height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.74)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: mood.symbol).font(.system(size: 18, weight: .semibold))
                    Text(mood.rawValue).font(.system(size: 13, weight: .bold)).lineLimit(1)
                }.padding(10)
            }.frame(width: width, height: height)
             .clipShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }

    private var searchPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Cerca").font(.system(size: 31, weight: .bold))
                .padding(.horizontal, 18).padding(.top, 12)
            searchBox
            if voiceSearch.isListening {
                Text(voiceSearch.transcript.isEmpty ? "Parla ora…" : voiceSearch.transcript)
                    .font(.caption).foregroundStyle(accent).padding(.horizontal, 18)
            }
            if let status = voiceSearch.errorText {
                Text(status).font(.caption).foregroundStyle(.orange).padding(.horizontal, 18)
            }
            if !songIdentifier.status.isEmpty {
                Text(songIdentifier.status).font(.caption).foregroundStyle(muted).padding(.horizontal, 18)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.orange).padding(.horizontal, 18)
            }
            if searching { ProgressView("Ricerca in corso…").tint(accent).frame(maxWidth: .infinity) }
            if !results.isEmpty {
                trackList(results)
            } else if !searching {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            searchAction("Cerca con la voce", symbol: "mic.fill") { startVoiceSearch() }
                            searchAction("Riconosci un brano", symbol: "waveform") { startSongIdentifier() }
                        }
                        Text("Esplora i generi").font(.system(size: 21, weight: .bold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(genres.indices, id: \.self) { index in
                                Button {
                                    openGenre(genres[index])
                                } label: {
                                    ZStack(alignment: .topLeading) {
                                        LinearGradient(colors: [genreColor(index), genreColor(index).opacity(0.54)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Image(systemName: genreSymbol(index))
                                            .font(.system(size: 72, weight: .black))
                                            .rotationEffect(.degrees(-22))
                                            .foregroundStyle(.white.opacity(0.23))
                                            .offset(x: 87, y: 33)
                                        Text(genres[index].title).font(.system(size: 17, weight: .bold))
                                            .padding(15)
                                    }
                                    .frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 13))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - DVS 1.0.4: dynamic charts for every category

    private func openGenre(_ genre: DVSGenre) {
        selectedGenreSection = 0
        chartPlaybackMessage = nil
        selectedGenre = genre
    }

    private func genreChartsSheet(_ genre: DVSGenre) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 13) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 30)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(genre.title).font(.system(size: 29, weight: .bold))
                            Text("Nuove uscite e classifiche sempre aggiornabili")
                                .font(.caption).foregroundStyle(muted)
                        }
                    }.padding(.top, 12)

                    Picker("Classifica", selection: $selectedGenreSection) {
                        Text("Novità").tag(0)
                        Text("Classifica DVS").tag(1)
                    }.pickerStyle(.segmented)

                    if let snapshot = charts.snapshots[genre.id] {
                        Text("Ultimo aggiornamento: " + snapshot.refreshedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(muted)
                        let items = selectedGenreSection == 0 ? snapshot.newReleases : snapshot.trending
                        if items.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(muted)
                                Text(selectedGenreSection == 0 ? "Nessuna nuova uscita verificata negli ultimi 90 giorni" : "Nessun brano disponibile per questo genere")
                                    .multilineTextAlignment(.center).foregroundStyle(muted)
                                Text("Prova ad aggiornare o cambia categoria.")
                                    .font(.caption).foregroundStyle(muted)
                            }.frame(maxWidth: .infinity).padding(.vertical, 32)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(items.indices, id: \.self) { index in
                                    chartSongRow(items[index], rank: selectedGenreSection == 1 ? index + 1 : nil)
                                }
                            }
                        }
                    } else if charts.loading.contains(genre.id) {
                        ProgressView("Caricamento delle uscite…").tint(accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 38)
                    }

                    if charts.loading.contains(genre.id), charts.snapshots[genre.id] != nil {
                        HStack { ProgressView().tint(accent); Text("Aggiornamento in corso…") }
                            .font(.caption).foregroundStyle(muted)
                    }
                    if let message = charts.errors[genre.id] {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                    if let chartPlaybackMessage {
                        Text(chartPlaybackMessage).font(.caption).foregroundStyle(.orange)
                    }
                    Text("Classifica DVS: " + (charts.snapshots[genre.id]?.sourceDescription ?? "Apple RSS / iTunes") + ". Se configuri una chiave Last.fm gratuita, vengono consultate anche le classifiche per tag. Non è una graduatoria ufficiale per genere di Apple o Spotify.")
                        .font(.caption2).foregroundStyle(muted)
                    Text("Motore multiplo DVS: YouTube + Audius. Ogni brano parte direttamente nel player interno; non tutti i titoli sono disponibili su entrambe le sorgenti.")
                        .font(.caption2).foregroundStyle(muted)
                }
                .padding(.horizontal, 18).padding(.bottom, 34)
            }
            .background(base.ignoresSafeArea())
            .navigationTitle("Scopri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { selectedGenre = nil }.foregroundStyle(accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await charts.refresh(genre, force: true, lastFMKey: player.lastFMKey) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.foregroundStyle(accent).disabled(charts.loading.contains(genre.id))
                        .accessibilityLabel("Aggiorna classifica")
                }
            }
            .refreshable { await charts.refresh(genre, force: true, lastFMKey: player.lastFMKey) }
            .task(id: genre.id) { await charts.refresh(genre, lastFMKey: player.lastFMKey) }
            .sheet(item: $selectedChartAlbum) { album in chartAlbumSheet(album) }
        }
    }

    private func chartSongRow(_ item: GenreChartSong, rank: Int?) -> some View {
        HStack(spacing: 10) {
            if let rank {
                Text("\(rank)").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(muted).frame(width: 24)
            }
            Button {
                if item.isAlbum {
                    currentAlbumTracks = []
                    loadingAlbum = true
                    selectedChartAlbum = item
                } else {
                    Task { await playChartSong(item) }
                }
            } label: {
                HStack(spacing: 11) {
                    AsyncImage(url: item.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 7).fill(panel)
                            .overlay(Image(systemName: "music.note").foregroundStyle(muted))
                    }
                    .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(item.artist).font(.caption).foregroundStyle(muted).lineLimit(1)
                        Text(item.isAlbum ? "Album · " + String((item.releaseDate ?? "").prefix(10)) : String((item.releaseDate ?? "").prefix(10)))
                            .font(.caption2).foregroundStyle(accent.opacity(0.88))
                    }
                    Spacer(minLength: 2)
                    if chartLookupID == item.id { ProgressView().tint(accent) }
                    else { Image(systemName: item.isAlbum ? "chevron.right" : "play.fill").foregroundStyle(accent) }
                }
            }.buttonStyle(.plain)

        }.padding(9).background(panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func chartAlbumSheet(_ album: GenreChartSong) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(album.title).font(.title2.weight(.bold))
                    Text(album.artist).foregroundStyle(muted)
                    if loadingAlbum {
                        ProgressView("Cerco i brani dell'album…").tint(accent).padding(.vertical, 20)
                    } else if currentAlbumTracks.isEmpty {
                        Text("Brani non disponibili. Apri Apple Music dall'elenco oppure riprova.")
                            .font(.caption).foregroundStyle(muted)
                    } else {
                        ForEach(currentAlbumTracks) { track in chartSongRow(track, rank: track.sourcePosition) }
                    }
                }.padding(18)
            }
            .background(base.ignoresSafeArea())
            .navigationTitle("Brani dell'album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { selectedChartAlbum = nil }.foregroundStyle(accent)
                }
            }
            .task(id: album.id) {
                currentAlbumTracks = await GenreChartsService.shared.albumTracks(albumID: album.id)
                loadingAlbum = false
            }
        }
    }

    private func playChartSong(_ item: GenreChartSong) async {
        guard chartLookupID == nil else { return }
        chartLookupID = item.id
        chartPlaybackMessage = nil
        defer { chartLookupID = nil }
        let result = try? await catalog.search(item.artist + " " + item.title)
        if let track = result?.first(where: {
            OfficialCatalog.queryRelevance($0, query: item.artist + " " + item.title) >= 0.80
        }) {
            player.startRadio(from: track)
            selectedChartAlbum = nil
            selectedGenre = nil
        } else {
            chartPlaybackMessage = "Non ho trovato questo brano nei due motori musicali disponibili."
        }
    }

    private func genreSymbol(_ index: Int) -> String {
        let symbols = ["flame.fill", "music.mic", "mic.fill", "music.note", "moon.fill", "guitars.fill", "waveform", "speaker.wave.3.fill", "leaf.fill", "cloud.fill"]
        return symbols[index % symbols.count]
    }

    private func searchAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol).font(.system(size: 27, weight: .semibold)).foregroundStyle(accent)
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 67, alignment: .leading)
             .padding(15)
             .background(LinearGradient(colors: [Color(red: 0.09, green: 0.27, blue: 0.18), panel],
                                        startPoint: .topLeading, endPoint: .bottomTrailing),
                         in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }

    private var searchBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(muted)
            TextField("Cerca brani, artisti, album o playlist", text: $query)
                .tint(accent).font(.system(size: 13))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).onSubmit { Task { await search() } }
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(muted)
                }.accessibilityLabel("Cancella ricerca")
            }
            Button { startVoiceSearch() } label: {
                Image(systemName: voiceSearch.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 17)).foregroundStyle(voiceSearch.isListening ? .orange : accent)
            }.accessibilityLabel("Ricerca vocale")
            Button { Task { await search() } } label: {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 18)).foregroundStyle(accent)
            }.accessibilityLabel("Avvia ricerca")
        }
        .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 18)
    }

    private var discoveryPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("DVS Mood").font(.system(size: 30, weight: .bold))
                Text("Scegli un'atmosfera e lascia che DVS crei la colonna sonora perfetta per te.")
                    .font(.system(size: 14)).foregroundStyle(muted)
                if player.moodLoading { ProgressView("Preparo il tuo mood…").tint(accent) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach([DVSMood.chill, .energy, .love, .sad, .trap, .night, .indie, .focus]) { mood in
                        moodCard(mood, width: 100, height: 121)
                    }
                }
                Button { player.startMood(selectedMood) } label: {
                    Label("Crea il mio Mood", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black).frame(maxWidth: .infinity)
                        .padding(.vertical, 17).background(accent, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Ascolta il mood selezionato")
                Button { showDiscoverySwipe = true } label: {
                    HStack {
                        Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Discovery Swipe").font(.headline)
                            Text("Scopri nuovi artisti scorrendo a destra o sinistra")
                                .font(.caption).foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(muted)
                    }.padding(17).background(panel, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                Text("La tua radio").font(.system(size: 20, weight: .bold)).padding(.top, 5)
                VStack(spacing: 14) {
                    Toggle("Radio infinita", isOn: Binding(get: { player.autoRadio }, set: { player.autoRadio = $0 }))
                    Toggle("Suggerimenti intelligenti", isOn: Binding(get: { player.smartRadio }, set: { player.setSmartRadio($0) }))
                    Toggle("Smart Shuffle", isOn: Binding(get: { player.shuffle }, set: { player.setSmartShuffle($0) }))
                }.tint(accent).padding(16).background(panel, in: RoundedRectangle(cornerRadius: 15))
                Text("Le atmosfere si basano sulla ricerca musicale e non su un'analisi diretta dei BPM.")
                    .font(.caption).foregroundStyle(muted)
            }.padding(.horizontal, 19).padding(.top, 7).padding(.bottom, 24)
        }
    }

    private func genreColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.40, green: 0.13, blue: 0.22), Color(red: 0.20, green: 0.31, blue: 0.40),
            Color(red: 0.28, green: 0.20, blue: 0.49), Color(red: 0.51, green: 0.21, blue: 0.25),
            Color(red: 0.23, green: 0.19, blue: 0.36), Color(red: 0.39, green: 0.27, blue: 0.17),
            Color(red: 0.10, green: 0.35, blue: 0.31), Color(red: 0.50, green: 0.21, blue: 0.13),
            Color(red: 0.16, green: 0.36, blue: 0.42), Color(red: 0.23, green: 0.38, blue: 0.25)
        ]
        return palette[index % palette.count]
    }

    private var libraryPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("La tua libreria").font(.system(size: 29, weight: .bold))
                    Spacer()
                    Button { showCreatePlaylist = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(accent)
                    }.accessibilityLabel("Crea playlist")
                }.padding(.top, 12).padding(.bottom, 2)
                libraryLink("Preferiti", note: "\(player.favorites.count) brani", symbol: "heart.fill", tint: accent) {
                    if let first = player.favorites.first { player.playSelection(player.favorites, selected: first) }
                }
                libraryLink("Playlist", note: "\(player.playlists.count) playlist", symbol: "music.note.list", tint: Color(red: 0.24, green: 0.63, blue: 0.48)) {
                    showCreatePlaylist = true
                }
                libraryLink("Cronologia", note: "Ascolti recenti e per data", symbol: "clock.arrow.circlepath", tint: .gray) {
                    showHistory = true
                }
                libraryLink("Playlist intelligenti", note: "Create con regole personalizzate", symbol: "slider.horizontal.3", tint: Color(red: 0.43, green: 0.43, blue: 0.53)) {
                    showSmartCreator = true
                }
                libraryLink("Playlist automatiche", note: "Aggiornate da DVS per te", symbol: "sparkles", tint: Color(red: 0.13, green: 0.52, blue: 0.32)) {
                    openedAutoCollection = .mostPlayed
                }
                HStack {
                    Text("Le tue playlist").font(.system(size: 21, weight: .bold))
                    Spacer()
                    Button { showCreatePlaylist = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(muted)
                    }
                }.padding(.top, 17)
                if player.playlists.isEmpty {
                    Text("Crea la tua prima playlist toccando +")
                        .font(.subheadline).foregroundStyle(muted)
                }
                ForEach(player.playlists) { list in
                    HStack(spacing: 12) {
                        Button { openedPlaylist = list } label: {
                            HStack(spacing: 12) {
                                libraryArtwork("music.note.list", tint: .purple)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text("\(list.tracks.count) brani").font(.caption).foregroundStyle(muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(muted)
                            }
                        }.buttonStyle(.plain)
                        Button { player.deletePlaylist(list.id) } label: {
                            Image(systemName: "trash").foregroundStyle(muted)
                        }.accessibilityLabel("Elimina playlist")
                    }.padding(.vertical, 4)
                }
                Text("Raccolte automatiche").font(.system(size: 20, weight: .bold)).padding(.top, 10)
                ForEach(DVSAutoCollection.allCases) { category in
                    Button { openedAutoCollection = category } label: {
                        HStack(spacing: 12) {
                            libraryArtwork(category.symbol, tint: Color(red: 0.12, green: 0.55, blue: 0.32))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.rawValue).font(.subheadline.weight(.semibold))
                                Text("\(player.autoTracks(for: category).count) brani")
                                    .font(.caption).foregroundStyle(muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(muted)
                        }.padding(.vertical, 3)
                    }.buttonStyle(.plain)
                }
                HStack {
                    Text("Playlist intelligenti").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button("Nuova +") { showSmartCreator = true }.font(.caption.weight(.semibold)).foregroundStyle(accent)
                }.padding(.top, 10)
                ForEach(player.smartRules) { rule in
                    HStack {
                        Button { openedRule = rule } label: {
                            HStack(spacing: 11) {
                                libraryArtwork("line.3.horizontal.decrease", tint: .indigo)
                                Text(rule.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(player.tracks(for: rule).count)").foregroundStyle(muted)
                            }
                        }.buttonStyle(.plain)
                        Button { player.removeSmartRule(rule.id) } label: {
                            Image(systemName: "trash").foregroundStyle(muted)
                        }
                    }.padding(.vertical, 3)
                }
            }.padding(.horizontal, 19).padding(.bottom, 26)
        }
    }

    private func libraryArtwork(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 22, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 50, height: 50)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
    }

    private func libraryLink(_ title: String, note: String, symbol: String, tint: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                libraryArtwork(symbol, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(note).font(.caption).foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted)
            }.frame(minHeight: 53, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private var profilePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [accent, .green, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text("DVS").font(.title2.weight(.black)).foregroundStyle(.black)
                    }.frame(width: 83, height: 83)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Il mio profilo").font(.system(size: 27, weight: .bold))
                        Text("DVS Music · Privato").font(.subheadline).foregroundStyle(muted)
                    }
                }
                HStack(spacing: 12) {
                    statCard("\(player.favorites.count)", "Preferiti")
                    statCard("\(player.playlists.count)", "Playlist")
                    statCard("\(player.recentTracks.count)", "Recenti")
                }
                sectionHeader("Impostazioni di ascolto", symbol: "slider.horizontal.3")
                VStack(spacing: 17) {
                    Toggle("Radio infinita", isOn: Binding(get: { player.autoRadio }, set: { player.autoRadio = $0 }))
                    Divider().overlay(Color.white.opacity(0.1))
                    Toggle("Coda intelligente", isOn: Binding(get: { player.smartRadio }, set: { player.setSmartRadio($0) }))
                    Divider().overlay(Color.white.opacity(0.1))
                    Toggle("Smart Shuffle", isOn: Binding(get: { player.shuffle }, set: { player.setSmartShuffle($0) }))
                }.tint(accent).padding(17).background(panel, in: RoundedRectangle(cornerRadius: 18))
                sectionHeader("Controllo dell'algoritmo", symbol: "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Brani familiari").font(.caption).foregroundStyle(muted)
                        Spacer()
                        Text("Nuove scoperte").font(.caption).foregroundStyle(muted)
                    }
                    Slider(value: Binding(get: { player.exploration }, set: { player.setExploration($0) }),
                           in: 0...1).tint(accent)
                    Text("Esplorazione: \(Int(player.exploration * 100))% · pesa i suggerimenti di DVS, non controlla YouTube o Last.fm.")
                        .font(.caption).foregroundStyle(muted)
                }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 17))
                sectionHeader("Interfaccia e cronologia", symbol: "moon.stars")
                VStack(spacing: 16) {
                    Toggle("Modalità notte", isOn: Binding(get: { player.nightMode }, set: { player.setNightMode($0) }))
                    Divider().overlay(Color.white.opacity(0.1))
                    Button { showHistory = true } label: {
                        HStack {
                            Label("Cronologia intelligente", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.foregroundStyle(.white)
                    }
                }.tint(accent).padding(16).background(panel, in: RoundedRectangle(cornerRadius: 17))
                sectionHeader("Raccomandazioni avanzate", symbol: "brain.head.profile")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last.fm migliora la somiglianza tra canzoni. Chiave API personale gratuita e facoltativa; senza chiave rimane attiva la radio base.")
                        .font(.footnote).foregroundStyle(muted)
                    SecureField("Chiave API Last.fm (facoltativa)", text: $lastFMKeyDraft)
                        .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(12).background(base, in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Button("Salva chiave Last.fm") { player.setLastFMKey(lastFMKeyDraft) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                        Spacer()
                        Link("Chiave gratuita", destination: URL(string: "https://www.last.fm/api/account/create")!)
                            .font(.caption).foregroundStyle(accent)
                    }
                    Text(player.lastFMKey.isEmpty ? "Modalità gratuita locale / catalogo" : "Last.fm configurato (chiave presente)")
                        .font(.caption).foregroundStyle(muted)
                }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 18))
                .onAppear { lastFMKeyDraft = player.lastFMKey }
                Button { showWrapped = true } label: {
                    HStack {
                        Image(systemName: "chart.bar.fill").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DVS Wrapped").font(.headline)
                            Text("Le tue statistiche musicali").font(.caption).foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(accent)
                    }.padding(17).background(panel, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
                sectionHeader("Audio avanzato", symbol: "slider.horizontal.3")
                Text("Crossfade reale, equalizzatore e normalizzazione LUFS richiedono una pipeline audio diversa dall'attuale AVQueuePlayer. Non sono abilitati nella 1.0 per evitare controlli fittizi o interruzioni degli stream.")
                    .font(.footnote).foregroundStyle(muted)
                sectionHeader("Informazioni", symbol: "info.circle")
                Text("DVS Music 1.0.3 · iPhone\nPlayer audio nativo e controlli dalla schermata di blocco. Catalogo sperimentale: risultati e flussi possono essere indisponibili a causa delle sorgenti esterne.")
                    .font(.footnote).foregroundStyle(muted).lineSpacing(5)
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }
    }

    private func statCard(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(accent)
            Text(caption).font(.caption2).foregroundStyle(muted)
        }.frame(maxWidth: .infinity).padding(14).background(panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline).foregroundStyle(.white)
    }

    private func horizontalTracks(_ tracks: [MusicTrack]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 13) {
                ForEach(Array(tracks.prefix(12))) { track in
                    Button { player.playSelection(tracks, selected: track) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Artwork(track: track, size: 128)
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(track.artist).font(.caption).foregroundStyle(muted).lineLimit(1)
                        }.frame(width: 128, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func trackList(_ tracks: [MusicTrack]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tracks) { track in
                    trackRow(track) { player.startRadio(from: track) }
                }
            }.padding(.horizontal, 18).padding(.bottom, 20)
        }
    }

    private func trackRow(_ track: MusicTrack, action: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            Button(action: action) {
                HStack(spacing: 11) {
                    Artwork(track: track, size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(player.current?.id == track.id ? accent : .white).lineLimit(1)
                        HStack(spacing: 5) {
                            Text(track.artist).font(.caption).foregroundStyle(muted).lineLimit(1)
                            Text("· " + track.sourceLabel).font(.caption2).foregroundStyle(accent.opacity(0.78)).fixedSize()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
            Button { player.toggleFavorite(track) } label: {
                Image(systemName: player.isFavorite(track) ? "heart.fill" : "heart")
                    .foregroundStyle(player.isFavorite(track) ? accent : muted)
            }.accessibilityLabel("Preferito")
            Menu {
                Button(action: action) { Label("Riproduci", systemImage: "play.fill") }
                Button { player.append(track) } label: { Label("Aggiungi alla coda", systemImage: "text.badge.plus") }
                Button { player.startRadio(from: track) } label: { Label("Avvia radio da questo brano", systemImage: "dot.radiowaves.left.and.right") }
                if player.isBlocked(track) {
                    Button { player.setBlocked(track, blocked: false) } label: { Label("Consiglia di nuovo", systemImage: "checkmark.circle") }
                } else {
                    Button { player.setBlocked(track) } label: { Label("Non consigliarmi questo brano", systemImage: "hand.thumbsdown") }
                }
                Button {
                    playlistTarget = track
                    showPlaylistOptions = true
                } label: { Label("Aggiungi a playlist", systemImage: "square.stack.badge.plus") }
            } label: {
                Image(systemName: "ellipsis").font(.title3).foregroundStyle(muted)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // Spotify-like horizontal movement: left = next, right = previous.
    // Vertical scroll on the full player still works normally.
    private var trackSwipe: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { gesture in
                let dx = gesture.translation.width
                let dy = gesture.translation.height
                guard abs(dx) > 65, abs(dx) > abs(dy) * 1.35 else { return }
                if dx < 0 { player.next() } else { player.previousFromSwipe() }
            }
    }

    private var miniPlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                if let track = player.current {
                    Button { showPlayer = true } label: {
                        HStack(spacing: 9) {
                            Artwork(track: track, size: 43)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(track.artist).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apri player di \(track.title)")
                }
                if player.preparing { ProgressView().tint(accent) }
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 19))
                        .foregroundStyle(muted).frame(width: 29, height: 42)
                }.accessibilityLabel("Apri coda")
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 20)).foregroundStyle(.white)
                        .frame(width: 33, height: 42)
                }.accessibilityLabel(player.playing ? "Pausa" : "Riproduci")
            }.padding(.horizontal, 9).padding(.vertical, 5)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.15)
                    accent.frame(width: geometry.size.width * (player.duration > 0 ?
                        min(1, max(0, player.elapsed / player.duration)) : 0))
                }
            }.frame(height: 2)
        }
        .background(Color(red: 0.15, green: 0.16, blue: 0.17), in: RoundedRectangle(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .padding(.horizontal, 9).padding(.bottom, 3)
        .simultaneousGesture(trackSwipe)
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            HStack(spacing: 0) {
                ForEach([MusicTab.home, .search, .library, .wrapped], id: \.self) { option in
                    Button { tab = option } label: {
                        VStack(spacing: 5) {
                            Image(systemName: option.symbol).font(.system(size: 21, weight: .medium))
                            Text(option == .library ? "La tua libreria" : option.rawValue)
                                .font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(tab == option ? accent : muted)
                        .frame(maxWidth: .infinity).frame(height: 57)
                    }.buttonStyle(.plain)
                }
            }
        }.background(.black.opacity(0.92))
    }

    private var playerSheet: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Button { showPlayer = false } label: {
                            Image(systemName: "chevron.down").font(.system(size: 21, weight: .semibold))
                                .frame(width: 36, height: 39)
                        }.accessibilityLabel("Chiudi player")
                        Spacer()
                        VStack(spacing: 3) {
                            Text("IN RIPRODUZIONE").font(.system(size: 10, weight: .bold))
                                .tracking(1.8).foregroundStyle(muted)
                            Text("DVS Music").font(.system(size: 13, weight: .semibold))
                        }
                        Spacer()
                        Menu {
                            if let current = player.current {
                                Button { player.startRadio(from: current) } label: {
                                    Label("Avvia radio da questo brano", systemImage: "dot.radiowaves.left.and.right")
                                }
                                Button { player.append(current) } label: {
                                    Label("Aggiungi alla coda", systemImage: "text.badge.plus")
                                }
                                Button { player.setBlocked(current) } label: {
                                    Label("Non consigliarmi il brano", systemImage: "hand.thumbsdown")
                                }
                            }
                            Button { openQueueAfterPlayerDismiss = true; showPlayer = false } label: {
                                Label("Mostra coda", systemImage: "list.bullet")
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 22))
                                .frame(width: 36, height: 39)
                        }.accessibilityLabel("Altre azioni sul brano")
                    }
                    if let track = player.current {
                        let coverSize = max(180, min(geo.size.width - 64, geo.size.height * 0.39, 365.0))
                        Artwork(track: track, size: coverSize)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .simultaneousGesture(trackSwipe)
                            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                            .padding(.top, 7)
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.system(size: 23, weight: .bold)).lineLimit(2)
                                Text(track.artist).font(.system(size: 16)).foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button { player.toggleFavorite(track) } label: {
                                Image(systemName: player.isFavorite(track) ? "heart.fill" : "heart")
                                    .font(.system(size: 27)).foregroundStyle(accent)
                                    .frame(width: 40, height: 40)
                            }.accessibilityLabel("Aggiungi o rimuovi dai preferiti")
                        }.padding(.top, 5)
                    }
                    if let error = player.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                    VStack(spacing: 2) {
                        if player.duration > 1 {
                            Slider(value: Binding(get: { min(player.elapsed, player.duration) },
                                                  set: { player.seek(to: $0) }),
                                   in: 0...max(player.duration, 1)).tint(accent)
                        } else {
                            Capsule().fill(.white.opacity(0.2)).frame(height: 4).padding(.vertical, 14)
                        }
                        HStack {
                            Text(timeLabel(player.elapsed))
                            Spacer()
                            Text("-" + timeLabel(max(0, player.duration - player.elapsed)))
                        }.font(.system(size: 12).monospacedDigit()).foregroundStyle(muted)
                    }
                    HStack(spacing: 0) {
                        Button { player.setSmartShuffle(!player.shuffle) } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(player.shuffle ? accent : muted)
                        }.frame(maxWidth: .infinity)
                        Button { player.previous() } label: {
                            Image(systemName: "backward.end.fill").foregroundStyle(.white)
                        }.frame(maxWidth: .infinity)
                        Button { player.togglePlayback() } label: {
                            Image(systemName: player.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.black).frame(width: 67, height: 67)
                                .background(.white, in: Circle())
                        }.frame(maxWidth: .infinity)
                        Button { player.next() } label: {
                            Image(systemName: "forward.end.fill").foregroundStyle(.white)
                        }.frame(maxWidth: .infinity)
                        Button { player.cycleRepeat() } label: {
                            Image(systemName: "repeat")
                                .foregroundStyle(player.repeatSetting == .all ? accent : muted)
                        }.frame(maxWidth: .infinity)
                    }.font(.system(size: 23)).padding(.vertical, 2)
                    HStack(spacing: 5) {
                        playerTool("Radio", icon: "dot.radiowaves.left.and.right") {
                            if let current = player.current { player.startRadio(from: current) }
                        }
                        playerTool("Testo", icon: "text.bubble") {
                            if let current = player.current { Task { await lyrics.load(current) } }
                            showLyrics = true
                        }
                        playerTool("Timer", icon: player.sleepDeadline != nil || player.sleepAtTrackEnd ? "moon.stars.fill" : "moon") {
                            showSleepTimer = true
                        }
                        playerTool("Notte", icon: "moon.zzz") {
                            player.setNightMode(true); showPlayer = false
                        }
                        playerTool("Coda", icon: "list.bullet") {
                            openQueueAfterPlayerDismiss = true; showPlayer = false
                        }
                    }.padding(.top, 13)
                    Button { openQueueAfterPlayerDismiss = true; showPlayer = false } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Prossimi brani").font(.system(size: 15, weight: .bold))
                                Text(player.preparedNextCount > 0
                                     ? "\(player.preparedNextCount) stream già preparati per il player"
                                     : player.findingNextTracks ? "Cerco musica simile in anticipo…" : "Apri la coda intelligente")
                                    .font(.caption).foregroundStyle(muted)
                            }
                            Spacer()
                            Image(systemName: "list.bullet").foregroundStyle(accent)
                        }.padding(17).background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).padding(.top, 7)
                }
                .padding(.horizontal, 24).padding(.top, 13).padding(.bottom, 32)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(LinearGradient(colors: [artworkPalette.color, base, .black],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func playerTool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }.foregroundStyle(.white.opacity(0.85))
             .frame(maxWidth: .infinity, minHeight: 49)
        }.buttonStyle(.plain)
    }

    private var queueSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(accent)
                    Text("Coda intelligente").font(.headline)
                    Spacer()
                    Toggle("Radio", isOn: Binding(get: { player.autoRadio }, set: { player.autoRadio = $0 }))
                        .labelsHidden().tint(accent)
                }.padding(.horizontal, 18)
                Text(player.preparedNextCount > 0
                     ? "\(player.preparedNextCount) stream preparati. La radio trova altri brani senza interrompere l'audio."
                     : "La radio prepara automaticamente i prossimi brani. Puoi cambiare l'ordine usando le frecce.")
                    .font(.caption).foregroundStyle(muted).padding(.horizontal, 18)
                if player.queue.isEmpty {
                    emptyState("music.note.list", title: "Coda vuota", subtitle: "Riproduci un brano per iniziare.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(player.queue.indices, id: \.self) { index in
                                let track = player.queue[index]
                                HStack(spacing: 10) {
                                    Artwork(track: track, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            .foregroundStyle(index == player.currentIndex ? accent : .white)
                                        Text(index == player.currentIndex ? "In riproduzione" : track.artist)
                                            .font(.caption).foregroundStyle(muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if index > player.currentIndex {
                                        Button { player.setBlocked(track) } label: {
                                            Image(systemName: "hand.thumbsdown").foregroundStyle(muted)
                                        }.accessibilityLabel("Non consigliarmi questo brano")
                                        Button { player.moveUpcoming(at: index, by: -1) } label: {
                                            Image(systemName: "chevron.up").foregroundStyle(accent)
                                        }.disabled(index == player.currentIndex + 1)
                                        Button { player.moveUpcoming(at: index, by: 1) } label: {
                                            Image(systemName: "chevron.down").foregroundStyle(accent)
                                        }.disabled(index == player.queue.count - 1)
                                        Button { player.removeUpcoming(at: index) } label: {
                                            Image(systemName: "trash").foregroundStyle(muted)
                                        }
                                    } else {
                                        Image(systemName: "waveform").foregroundStyle(accent)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }.padding(.horizontal, 18)
                    }
                }
            }
            .padding(.top, 15).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(base.ignoresSafeArea())
            .navigationTitle("Prossimi brani")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fine") { showQueue = false }.foregroundStyle(accent) }
            }
        }.preferredColorScheme(.dark)
    }

    private var sleepTimerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Scegli quando fermare la musica").font(.title3.weight(.bold))
                    if let remaining = player.sleepRemaining {
                        Label("Tempo rimanente: \(timeLabel(Double(remaining)))", systemImage: "moon.stars.fill")
                            .foregroundStyle(accent)
                    } else if player.sleepAtTrackEnd {
                        Label("Si fermerà alla fine del brano", systemImage: "moon.stars.fill").foregroundStyle(accent)
                    }
                    ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { minutes in
                        Button {
                            player.setSleepTimer(minutes: minutes)
                            showSleepTimer = false
                        } label: {
                            HStack {
                                Image(systemName: "timer").foregroundStyle(accent)
                                Text(minutes == 60 ? "1 ora" : minutes == 90 ? "1 ora e 30" : "\(minutes) minuti")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(muted)
                            }.padding(13).background(panel, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                    HStack {
                        TextField("Minuti", text: $customSleepMinutes)
                            .keyboardType(.numberPad).padding(12)
                            .background(panel, in: RoundedRectangle(cornerRadius: 12))
                        Button("Avvia") {
                            if let minutes = Int(customSleepMinutes), (1...1440).contains(minutes) {
                                player.setSleepTimer(minutes: minutes)
                                showSleepTimer = false
                            }
                        }.foregroundStyle(accent)
                    }
                    Button("Fine del brano") { player.setSleepAtTrackEnd(); showSleepTimer = false }
                        .foregroundStyle(accent)
                    Button("Disattiva timer", role: .destructive) { player.cancelSleepTimer(); showSleepTimer = false }
                }.padding(20)
            }
            .background(base.ignoresSafeArea())
            .navigationTitle("Timer musica")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { showSleepTimer = false } } }
        }.preferredColorScheme(.dark)
    }

    private var lyricsSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if lyrics.busy { ProgressView("Ricerca testo...").tint(accent) }
                        if !lyrics.message.isEmpty { Text(lyrics.message).foregroundStyle(muted) }
                        if !lyrics.lines.isEmpty {
                            let active = lyrics.lines.last(where: { $0.time <= player.elapsed })?.id ?? 0
                            ForEach(lyrics.lines) { line in
                                Text(line.text)
                                    .font(.system(size: 23, weight: active == line.id ? .bold : .medium))
                                    .foregroundStyle(active == line.id ? accent : muted)
                                    .id(line.id)
                                    .onTapGesture { player.seek(to: line.time) }
                            }
                        } else if !lyrics.plain.isEmpty {
                            Text(lyrics.plain).font(.title3).lineSpacing(8)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                }
                .onChange(of: player.current?.id) { _ in
                    if let current = player.current { Task { await lyrics.load(current) } }
                }
                .onChange(of: Int(player.elapsed)) { _ in
                    if let line = lyrics.lines.last(where: { $0.time <= player.elapsed }) {
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(line.id, anchor: .center) }
                    }
                }
            }
            .background(base.ignoresSafeArea())
            .navigationTitle("Testo del brano")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { showLyrics = false } } }
        }.preferredColorScheme(.dark)
    }

    private var wrappedPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                Text("DVS Wrapped").font(.system(size: 30, weight: .bold)).padding(.top, 12)
                Text("Il tuo anno in musica su DVS.")
                    .font(.system(size: 14)).foregroundStyle(muted)
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.85, blue: 0.31),
                                                      Color(red: 0.00, green: 0.31, blue: 0.16),
                                                      Color.black], startPoint: .topTrailing, endPoint: .bottomLeading))
                    Circle().fill(accent.opacity(0.55))
                        .frame(width: 270, height: 270).blur(radius: 28).offset(x: 160, y: -160)
                    Circle().stroke(.white.opacity(0.12), lineWidth: 28)
                        .frame(width: 270, height: 270).offset(x: 170, y: -85)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(player.listeningSummary.totalMinutes)")
                            .font(.system(size: 49, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.65).lineLimit(1)
                        Text("Minuti ascoltati").font(.system(size: 16))
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(player.listeningSummary.tracksHeard)")
                                    .font(.system(size: 26, weight: .bold))
                                Text("Brani riprodotti").font(.system(size: 12)).foregroundStyle(muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(player.listeningSummary.topArtists.count)")
                                    .font(.system(size: 26, weight: .bold))
                                Text("Artisti nei top").font(.system(size: 12)).foregroundStyle(muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.top, 24)
                    }.padding(23)
                }.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 20))
                Text("I tuoi artisti preferiti").font(.system(size: 21, weight: .bold)).padding(.top, 9)
                if player.listeningSummary.topArtists.isEmpty {
                    Text("Le statistiche appariranno dopo i primi ascolti.")
                        .font(.subheadline).foregroundStyle(muted)
                }
                ForEach(Array(player.listeningSummary.topArtists.enumerated()), id: \.offset) { item in
                    HStack(spacing: 12) {
                        Text("\(item.offset + 1)").font(.headline).foregroundStyle(accent)
                            .frame(width: 24)
                        Image(systemName: "person.fill").foregroundStyle(accent)
                            .frame(width: 45, height: 45)
                            .background(panel, in: RoundedRectangle(cornerRadius: 11))
                        Text(item.element.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(item.element.seconds / 60)) min")
                            .font(.caption).foregroundStyle(muted)
                    }.padding(.vertical, 6)
                }
                Text("I tuoi brani più ascoltati").font(.system(size: 21, weight: .bold))
                    .padding(.top, 13)
                ForEach(player.listeningSummary.topTracks, id: \.track.id) { item in
                    HStack(spacing: 11) {
                        Artwork(track: item.track, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(item.plays) ascolti · \(Int(item.seconds / 60)) min")
                                .font(.caption).foregroundStyle(muted)
                        }
                        Spacer()
                    }.padding(.vertical, 3)
                }
                Text("Statistiche calcolate dagli ascolti salvati su questo dispositivo.")
                    .font(.caption).foregroundStyle(muted).padding(.top, 9)
            }.padding(.horizontal, 19).padding(.bottom, 28)
        }
    }

    private var wrappedSheet: some View {
        NavigationStack {
            wrappedPage
                .background(base.ignoresSafeArea())
                .navigationTitle("DVS Wrapped")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fine") { showWrapped = false }.foregroundStyle(accent)
                    }
                }
        }.preferredColorScheme(.dark)
    }

    private var nightModePage: some View {
        VStack(spacing: 24) {
            HStack {
                Label("DVS Night", systemImage: "moon.stars.fill")
                    .font(.title3.weight(.bold)).foregroundStyle(accent)
                Spacer()
                Button { player.setNightMode(false) } label: {
                    Label("Esci", systemImage: "xmark.circle.fill").font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            if let track = player.current {
                Artwork(track: track, size: 228)
                    .shadow(color: artworkPalette.color.opacity(0.4), radius: 25)
                Text(track.title).font(.title2.weight(.bold)).lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(track.artist).foregroundStyle(muted).lineLimit(1)
            } else {
                Image(systemName: "moon.zzz").font(.system(size: 65)).foregroundStyle(accent)
                Text("La musica per la notte").font(.title3)
                Text("Riproduci una canzone dalla Home dopo essere uscito.")
                    .font(.footnote).foregroundStyle(muted).multilineTextAlignment(.center)
            }
            if player.duration > 1 {
                Slider(value: Binding(get: { min(player.elapsed, player.duration) }, set: { player.seek(to: $0) }),
                       in: 0...max(1, player.duration)).tint(accent)
            }
            HStack(spacing: 35) {
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 68)).foregroundStyle(accent)
                }
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
            }.font(.title2)
            Button { showSleepTimer = true } label: {
                Label(player.sleepDeadline == nil && !player.sleepAtTrackEnd ? "Imposta timer" : "Modifica timer",
                      systemImage: "moon.stars.fill")
                    .font(.subheadline.weight(.semibold)).padding(15)
                    .background(panel, in: Capsule())
            }.buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(LinearGradient(colors: [artworkPalette.color.opacity(0.75), base, .black],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var historySheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(accent)
                    TextField("Cerca nella cronologia", text: $historyQuery)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }.padding(13).background(panel, in: RoundedRectangle(cornerRadius: 14))
                 .padding(.horizontal, 16)
                let matches = SmartLibrary.history(player.playHistory, query: historyQuery)
                if matches.isEmpty {
                    emptyState("clock.arrow.circlepath", title: "Nessun ascolto da mostrare",
                               subtitle: "La cronologia dettagliata registra i nuovi ascolti dalla 0.8.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(matches) { event in
                                HStack(spacing: 11) {
                                    Artwork(track: event.track, size: 50)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(event.track.artist).font(.caption).foregroundStyle(muted).lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(event.date, style: .date)
                                        Text(event.date, style: .time)
                                    }.font(.caption2).foregroundStyle(muted)
                                    Button { player.playSelection([event.track], selected: event.track) } label: {
                                        Image(systemName: "play.circle.fill").foregroundStyle(accent)
                                    }
                                }.padding(10).background(panel, in: RoundedRectangle(cornerRadius: 13))
                            }
                        }.padding(.horizontal, 16)
                    }
                }
            }.padding(.top, 16).background(base.ignoresSafeArea())
             .navigationTitle("Cronologia")
             .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { showHistory = false }.foregroundStyle(accent) } }
        }.preferredColorScheme(.dark)
    }

    private var discoverySwipeSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Discovery Swipe")
                        .font(.system(size: 29, weight: .bold))
                    Text("Scopri nuova musica: scorri a destra per salvare, a sinistra per saltare.")
                        .font(.subheadline).foregroundStyle(muted)
                    if discoveryBusy {
                        ProgressView("Cerco musica nuova…").tint(accent)
                    }
                    if let track = swipeTracks.first {
                        VStack(spacing: 0) {
                            ZStack(alignment: .bottomLeading) {
                                Artwork(track: track, size: 285)
                                LinearGradient(colors: [.clear, .black.opacity(0.92)],
                                               startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(track.title).font(.system(size: 20, weight: .bold)).lineLimit(2)
                                    Text(track.artist).font(.subheadline).foregroundStyle(muted)
                                }.padding(18)
                            }.frame(width: 285, height: 285)
                             .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [Color(red: 0.07, green: 0.18, blue: 0.18), panel],
                                                   startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 24))
                        .gesture(DragGesture(minimumDistance: 50).onEnded { gesture in
                            if gesture.translation.width > 90 { decideSwipe(liked: true) }
                            if gesture.translation.width < -90 { decideSwipe(liked: false) }
                        })
                        HStack(spacing: 33) {
                            Button { decideSwipe(liked: false) } label: {
                                Image(systemName: "xmark").font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white).frame(width: 64, height: 64)
                                    .background(panel, in: Circle())
                            }.accessibilityLabel("Scarta suggerimento")
                            Button { player.playSelection([track], selected: track) } label: {
                                Image(systemName: "play.fill").font(.system(size: 19))
                                    .foregroundStyle(.white).frame(width: 49, height: 49)
                                    .background(panel, in: Circle())
                            }.accessibilityLabel("Ascolta suggerimento")
                            Button { decideSwipe(liked: true) } label: {
                                Image(systemName: "heart.fill").font(.system(size: 26))
                                    .foregroundStyle(.black).frame(width: 64, height: 64)
                                    .background(accent, in: Circle())
                            }.accessibilityLabel("Mi piace, aggiungi ai preferiti")
                        }.frame(maxWidth: .infinity).padding(.top, 12)
                        Text("\(max(0, swipeTracks.count - 1)) altre scoperte pronte")
                            .font(.caption).foregroundStyle(muted)
                            .frame(maxWidth: .infinity).padding(.top, 9)
                    } else if !discoveryBusy {
                        emptyState("sparkles", title: "Nuove scoperte",
                                   subtitle: swipeMessage.isEmpty ? "Avvia la ricerca per ricevere suggerimenti." : swipeMessage)
                        Button { Task { await loadSwipeTracks() } } label: {
                            Label("Cerca altri brani", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.bold)).foregroundStyle(.black)
                                .padding(14).background(accent, in: Capsule())
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 19).padding(.vertical, 14)
            }
            .background(base.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { showDiscoverySwipe = false }.foregroundStyle(accent)
                }
            }
            .task { if swipeTracks.isEmpty { await loadSwipeTracks() } }
        }.preferredColorScheme(.dark)
    }

    private func loadSwipeTracks() async {
        guard !discoveryBusy else { return }
        discoveryBusy = true
        swipeMessage = ""
        let found = await player.discoverTracks()
        let ids = Set(swipeTracks.map(\.id))
        swipeTracks.append(contentsOf: found.filter { !ids.contains($0.id) && !player.isBlocked($0) })
        if swipeTracks.isEmpty { swipeMessage = "Nessun suggerimento disponibile ora. Cerca un brano o configura Last.fm, poi riprova." }
        discoveryBusy = false
    }

    private func decideSwipe(liked: Bool) {
        guard !swipeTracks.isEmpty else { return }
        let track = swipeTracks.removeFirst()
        if liked {
            if !player.isFavorite(track) { player.toggleFavorite(track) }
        } else {
            player.rejectDiscovery(track)
        }
        if swipeTracks.isEmpty { Task { await loadSwipeTracks() } }
    }

    private var smartPlaylistCreator: some View {
        NavigationStack {
            Form {
                Section("Nome") { TextField("Es. Rap ascoltato spesso", text: $ruleName) }
                Section("Regole") {
                    TextField("Artista o parola chiave (facoltativo)", text: $ruleFilter)
                    Toggle("Solo preferiti", isOn: $ruleFavorites)
                    Stepper("Almeno \(ruleMinPlays) ascolti", value: $ruleMinPlays, in: 0...50)
                    Picker("Periodo", selection: $ruleDays) {
                        Text("Sempre").tag(0)
                        Text("7 giorni").tag(7)
                        Text("30 giorni").tag(30)
                        Text("90 giorni").tag(90)
                    }
                }
                Section {
                    Text("Le playlist intelligenti si aggiornano usando i dati salvati sul dispositivo. Non analizzano automaticamente audio o genere dei brani.")
                        .font(.footnote).foregroundStyle(muted)
                }
            }
            .navigationTitle("Playlist intelligente")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { showSmartCreator = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Crea") {
                        let trimmed = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        player.addSmartRule(SmartPlaylistRule(name: trimmed, textFilter: ruleFilter,
                            favoritesOnly: ruleFavorites, minimumPlays: ruleMinPlays, lastDays: ruleDays))
                        ruleName = ""; ruleFilter = ""; ruleFavorites = false; ruleMinPlays = 0; ruleDays = 0
                        showSmartCreator = false
                    }.disabled(ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func autoCollectionSheet(_ category: DVSAutoCollection) -> some View {
        NavigationStack {
            let tracks = player.autoTracks(for: category)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Raccolta aggiornata automaticamente dalla tua cronologia")
                        .font(.caption).foregroundStyle(muted)
                    if let first = tracks.first {
                        Button { player.playSelection(tracks, selected: first) } label: {
                            Label("Riproduci", systemImage: "play.fill").foregroundStyle(.black)
                                .padding(12).background(accent, in: Capsule())
                        }
                    }
                    ForEach(tracks) { track in trackRow(track) { player.playSelection(tracks, selected: track) } }
                    if tracks.isEmpty {
                        Text("Non ci sono ancora brani che rispettano questa raccolta.")
                            .foregroundStyle(muted).padding(.top, 24)
                    }
                }.padding(18)
            }.background(base.ignoresSafeArea())
            .navigationTitle(category.rawValue)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { openedAutoCollection = nil }.foregroundStyle(accent) } }
        }.preferredColorScheme(.dark)
    }

    private func smartPlaylistSheet(_ rule: SmartPlaylistRule) -> some View {
        NavigationStack {
            let tracks = player.tracks(for: rule)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(tracks.count) brani · Aggiornamento automatico")
                        .foregroundStyle(muted)
                    if let first = tracks.first {
                        Button { player.playSelection(tracks, selected: first) } label: {
                            Label("Riproduci", systemImage: "play.fill").foregroundStyle(.black)
                                .padding(12).background(accent, in: Capsule())
                        }
                    }
                    ForEach(tracks) { track in trackRow(track) { player.playSelection(tracks, selected: track) } }
                    if tracks.isEmpty {
                        Text("Nessun brano corrisponde alle regole. Prova ad ascoltare più musica.")
                            .font(.footnote).foregroundStyle(muted)
                    }
                }.padding(18)
            }.background(base.ignoresSafeArea())
             .navigationTitle(rule.name)
             .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { openedRule = nil }.foregroundStyle(accent) } }
        }.preferredColorScheme(.dark)
    }

    private func startVoiceSearch() {
        if voiceSearch.isListening { voiceSearch.stop(); return }
        if songIdentifier.listening { songIdentifier.stop() }
        resumeAfterMicrophone = player.playing
        if player.playing { player.pause() }
        voiceSearch.onStopped = { finishMicrophoneOperation() }
        voiceSearch.start()
    }

    private func startSongIdentifier() {
        if songIdentifier.listening { songIdentifier.stop(); return }
        if voiceSearch.isListening { voiceSearch.stop() }
        resumeAfterMicrophone = player.playing
        if player.playing { player.pause() }
        songIdentifier.onStopped = { finishMicrophoneOperation() }
        songIdentifier.start()
    }

    private func finishMicrophoneOperation() {
        if resumeAfterMicrophone {
            resumeAfterMicrophone = false
            player.resume()
        }
    }

    private func playlistDetail(_ playlist: MusicPlaylist) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(playlist.name).font(.largeTitle.weight(.bold))
                    Text("\(playlist.tracks.count) brani").foregroundStyle(muted)
                    if let first = playlist.tracks.first {
                        Button { player.playSelection(playlist.tracks, selected: first) } label: {
                            Label("Riproduci tutti", systemImage: "play.fill")
                                .font(.headline).foregroundStyle(.black).padding(12)
                                .frame(maxWidth: .infinity)
                                .background(accent, in: Capsule())
                        }
                    }
                    ForEach(playlist.tracks) { track in
                        HStack {
                            trackRow(track) { player.playSelection(playlist.tracks, selected: track) }
                            Button { player.removeFromPlaylist(track, playlistID: playlist.id) } label: {
                                Image(systemName: "minus.circle").foregroundStyle(muted)
                            }
                        }
                    }
                }.padding(18)
            }
            .background(base.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { openedPlaylist = nil }.foregroundStyle(accent) } }
        }.preferredColorScheme(.dark)
    }

    private func emptyState(_ symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 46)).foregroundStyle(accent)
            Text(title).font(.title3.weight(.bold))
            Text(subtitle).font(.footnote).foregroundStyle(muted).multilineTextAlignment(.center)
            Spacer()
        }.frame(maxWidth: .infinity).padding(28)
    }

    private func timeLabel(_ number: Double) -> String {
        let seconds = Int(number.isFinite ? max(number, 0) : 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func search() async {
        let requestID = UUID()
        searchRequestID = requestID
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            searching = false
            results = []
            errorText = nil
            return
        }
        searching = true
        errorText = nil
        do {
            let found = try await catalog.search(text)
            guard searchRequestID == requestID else { return }
            results = found
        } catch {
            guard searchRequestID == requestID else { return }
            errorText = "Ricerca non disponibile: \(error.localizedDescription)"
            results = []
        }
        searching = false
    }
}

/// Display the real release artwork when MusicBrainz/CAA has a confident match.
/// While metadata loads, or if the album has no artwork, show the existing
/// YouTube thumbnail without holding up search or playback.
private struct Artwork: View {
    let track: MusicTrack
    let size: CGFloat
    @State private var releaseCover: URL?

    var body: some View {
        Group {
            if let releaseCover {
                AsyncImage(url: releaseCover) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        youtubeThumbnail
                    default:
                        youtubeThumbnail
                    }
                }
            } else {
                youtubeThumbnail
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: track.id) {
            releaseCover = nil
            releaseCover = await CoverArtService.shared.artworkURL(for: track)
        }
    }

    private var youtubeThumbnail: some View {
        AsyncImage(url: track.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color(red: 0.10, green: 0.29, blue: 0.17)
                Image(systemName: "waveform").font(.title3).foregroundStyle(accent)
            }
        }
    }
}
