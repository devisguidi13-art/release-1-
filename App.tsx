import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator, Alert, Image, Keyboard, Platform, Pressable,
  SafeAreaView, ScrollView, StatusBar, StyleSheet, Switch, Text,
  TextInput, TouchableOpacity, View,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { WebView } from 'react-native-webview';
import { youtubeDestination } from './youtubeLinks';
import { requestNotificationPermissionsAsync, setAudioModeAsync, useAudioPlaylist, useAudioPlaylistStatus } from 'expo-audio';
import { distinctTracks, radioSuggestions, rotateFromSelection, shuffleUpcoming, Track, RepeatMode } from './queueLogic';

const GREEN = '#24E876';
const API = 'https://api.audius.co/v1';
const APP_NAME = 'DVS_Music_Personal';
const FAVORITES_KEY = '@dvs_music_favorites_v2';
const PLAYLIST_KEY = '@dvs_music_playlists_v3';
const SETTINGS_KEY = '@dvs_music_settings_v3';
type Tab = 'scopri' | 'cerca' | 'libreria' | 'coda' | 'youtube';
type UserPlaylist = { id: string; name: string; tracks: Track[] };

const artworkUrl = (t: any) => t?.artwork?.['480x480'] || t?.artwork?.['150x150'] || '';
function parseTrack(raw: any): Track {
  return {
    id: String(raw.id || ''),
    title: raw.title || 'Brano senza titolo',
    artist: raw.user?.name || raw.user?.handle || 'Artista',
    genre: raw.genre || '',
    artwork: artworkUrl(raw),
    duration: Number(raw.duration || 0),
    streamable: raw.is_streamable !== false,
  };
}
async function getTracks(route: string): Promise<Track[]> {
  const separator = route.includes('?') ? '&' : '?';
  const response = await fetch(`${API}${route}${separator}app_name=${APP_NAME}`,
    { headers: { Accept: 'application/json' } });
  if (!response.ok) throw new Error(`Catalogo Audius non disponibile (${response.status})`);
  const raw = await response.json();
  if (!Array.isArray(raw?.data)) throw new Error('Risposta non valida dal catalogo Audius');
  return distinctTracks(raw.data.map(parseTrack).filter((t: Track) => t.id && t.streamable));
}
const streamUrl = (id: string) => `${API}/tracks/${encodeURIComponent(id)}/stream?app_name=${APP_NAME}`;
const time = (value: number) => {
  const n = Math.max(0, Number.isFinite(value) ? Math.floor(value) : 0);
  return `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`;
};
const metadata = (t: Track) => ({
  title: t.title, artist: t.artist, albumTitle: 'DVS Music · Audius',
  ...(t.artwork ? { artworkUrl: t.artwork } : {}),
});
const MediaArt = ({ track, size = 52 }: { track?: Track | null; size?: number }) => track?.artwork
  ? <Image source={{ uri: track.artwork }} style={{ width: size, height: size, borderRadius: 12, backgroundColor: '#183422' }} />
  : <View style={{ width: size, height: size, borderRadius: 12, backgroundColor: '#14341F', justifyContent: 'center', alignItems: 'center' }}>
    <Text style={{ color: GREEN, fontSize: Math.max(19, size / 2.4) }}>♫</Text>
  </View>;

/**
 * Embedded YouTube browser, using the official mobile website directly.
 * It does not extract audio, block ads, manipulate the YouTube player,
 * or promise playback after iOS suspends the application.
 */
function YouTubeBrowser() {
  const webRef = useRef<any>(null);
  const [youtubeQuery, setYoutubeQuery] = useState('');
  const [url, setUrl] = useState('https://m.youtube.com/');
  const [canGoBack, setCanGoBack] = useState(false);
  const [canGoForward, setCanGoForward] = useState(false);
  const [browserError, setBrowserError] = useState('');

  const goToSearch = () => {
    Keyboard.dismiss();
    const destination = youtubeDestination(youtubeQuery);
    setBrowserError('');
    if (url === destination) webRef.current?.reload();
    else setUrl(destination);
  };

  return (
    <View style={styles.youtubeScreen}>
      <Text style={styles.youtubeHeading}>YouTube in DVS Music</Text>
      <Text style={styles.youtubeCaption}>Cerca e riproduci direttamente nella finestra YouTube integrata. Nessun server personale.</Text>
      <View style={styles.youtubeSearchRow}>
        <TextInput
          value={youtubeQuery}
          onChangeText={setYoutubeQuery}
          onSubmitEditing={goToSearch}
          returnKeyType="search"
          autoCapitalize="none"
          autoCorrect={false}
          placeholder="Artista, canzone o link YouTube"
          placeholderTextColor="#819387"
          style={styles.youtubeSearchInput}
        />
        <TouchableOpacity accessibilityLabel="Cerca su YouTube" onPress={goToSearch} style={styles.youtubeSearchButton}>
          <Text style={styles.searchGlyph}>⌕</Text>
        </TouchableOpacity>
      </View>
      <View style={styles.youtubeToolbar}>
        <TouchableOpacity disabled={!canGoBack} onPress={() => webRef.current?.goBack()} style={styles.youtubeTool}><Text style={[styles.youtubeToolText, !canGoBack && styles.youtubeToolDisabled]}>← Indietro</Text></TouchableOpacity>
        <TouchableOpacity disabled={!canGoForward} onPress={() => webRef.current?.goForward()} style={styles.youtubeTool}><Text style={[styles.youtubeToolText, !canGoForward && styles.youtubeToolDisabled]}>Avanti →</Text></TouchableOpacity>
        <TouchableOpacity onPress={() => webRef.current?.reload()} style={styles.youtubeTool}><Text style={styles.youtubeToolText}>↻</Text></TouchableOpacity>
        <TouchableOpacity onPress={() => setUrl('https://m.youtube.com/')} style={styles.youtubeTool}><Text style={styles.youtubeToolText}>⌂ Home</Text></TouchableOpacity>
      </View>
      {browserError ? <Text style={styles.youtubeError}>{browserError}</Text> : null}
      <View style={styles.youtubeWebContainer}>
        <WebView
          ref={webRef}
          source={{ uri: url }}
          originWhitelist={['https://*']}
          style={styles.youtubeWeb}
          javaScriptEnabled
          domStorageEnabled
          allowsInlineMediaPlayback
          allowsFullscreenVideo
          mediaPlaybackRequiresUserAction
          sharedCookiesEnabled
          thirdPartyCookiesEnabled
          allowsBackForwardNavigationGestures
          startInLoadingState
          renderLoading={() => <ActivityIndicator color={GREEN} size="large" style={styles.youtubeLoading} />}
          onNavigationStateChange={state => {
            setCanGoBack(state.canGoBack);
            setCanGoForward(state.canGoForward);
          }}
          onError={() => setBrowserError('YouTube non è stato caricato. Verifica la connessione e riprova con ↻.')}
        />
      </View>
      <Text style={styles.youtubeNotice}>YouTube resta un player video ufficiale: il blocco schermo potrebbe interrompere la riproduzione. La coda nativa e l’audio in background predisposto sono disponibili nella sezione Audius.</Text>
    </View>
  );
}

export default function App() {
  // Native playlist rather than a one-track JS player: the OS can advance
  // to tracks that are already queued while the app is backgrounded.
  const player = useAudioPlaylist({ sources: [], loop: 'none', updateInterval: 500 });
  const status = useAudioPlaylistStatus(player);
  const [tab, setTab] = useState<Tab>('scopri');
  const [trending, setTrending] = useState<Track[]>([]);
  const [results, setResults] = useState<Track[]>([]);
  const [favorites, setFavorites] = useState<Track[]>([]);
  const [lists, setLists] = useState<UserPlaylist[]>([]);
  const [openedList, setOpenedList] = useState<string | null>(null);
  const [targetList, setTargetList] = useState<string | null>(null);
  const [newListName, setNewListName] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [query, setQuery] = useState('');
  const [current, setCurrent] = useState<Track | null>(null);
  const [queue, setQueue] = useState<Track[]>([]);
  const queueRef = useRef<Track[]>([]);
  const initialOrderRef = useRef<string[]>([]);
  const sessionRef = useRef(0);
  const radioBusyRef = useRef(false);
  const autoRadioRef = useRef(true);
  const lastMetadataIdRef = useRef('');
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState<RepeatMode>('none');
  const [autoRadio, setAutoRadio] = useState(true);
  const [radioBusy, setRadioBusy] = useState(false);
  const [settingsHydrated, setSettingsHydrated] = useState(false);
  const [radioInfo, setRadioInfo] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [expanded, setExpanded] = useState(false);
  const [progressWidth, setProgressWidth] = useState(1);

  const commitQueue = (updated: Track[]) => { queueRef.current = updated; setQueue(updated); };
  const selectedList = tab === 'scopri' ? trending : tab === 'cerca' ? results : openedList
    ? (lists.find(l => l.id === openedList)?.tracks || []) : favorites;
  const favoriteIds = useMemo(() => new Set(favorites.map(t => t.id)), [favorites]);
  const currentIndex = Math.max(0, status.currentIndex);

  useEffect(() => {
    setAudioModeAsync({ playsInSilentMode: true, shouldPlayInBackground: true, interruptionMode: 'doNotMix' })
      .catch(() => setError('Impossibile attivare la sessione audio'));
    if (Platform.OS === 'android') requestNotificationPermissionsAsync().catch(() => {});
    AsyncStorage.getItem(FAVORITES_KEY).then(v => v && setFavorites(JSON.parse(v))).catch(() => {});
    AsyncStorage.getItem(PLAYLIST_KEY).then(v => v && setLists(JSON.parse(v))).catch(() => {});
    AsyncStorage.getItem(SETTINGS_KEY).then(v => {
      if (!v) return;
      const saved = JSON.parse(v);
      if (typeof saved.shuffle === 'boolean') setShuffle(saved.shuffle);
      if (typeof saved.autoRadio === 'boolean') setAutoRadio(saved.autoRadio);
      if (['none', 'all', 'single'].includes(saved.repeat)) setRepeat(saved.repeat);
    }).catch(() => {}).finally(() => setSettingsHydrated(true));
  }, []);
  useEffect(() => { if (settingsHydrated) AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify({ shuffle, repeat, autoRadio })).catch(() => {}); }, [settingsHydrated, shuffle, repeat, autoRadio]);
  useEffect(() => { player.loop = repeat; }, [repeat, player]);
  useEffect(() => { autoRadioRef.current = autoRadio; }, [autoRadio]);

  useEffect(() => {
    if (tab !== 'scopri' || trending.length) return;
    let active = true;
    setLoading(true);
    getTracks('/tracks/trending?time=week&limit=35')
      .then(v => { if (active) setTrending(v); })
      .catch(e => { if (active) setError(e.message); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [tab, trending.length]);

  const search = async () => {
    const input = query.trim();
    if (!input) return;
    Keyboard.dismiss(); setError(''); setLoading(true); setTab('cerca');
    try { setResults(await getTracks(`/tracks/search?query=${encodeURIComponent(input)}&limit=40`)); }
    catch (e: any) { setError(e.message || 'Ricerca non riuscita'); }
    finally { setLoading(false); }
  };

  const playList = useCallback((tracks: Track[], startIndex: number = 0) => {
    const clean = distinctTracks(tracks);
    if (!clean.length) return;
    const selected = clean[Math.max(0, Math.min(startIndex, clean.length - 1))];
    const ordered = rotateFromSelection(selected, clean);
    const upcoming = shuffle ? shuffleUpcoming(ordered, 0) : ordered;
    try {
      ++sessionRef.current;
      setRadioInfo(''); setError('');
      player.pause(); player.clear();
      commitQueue(upcoming);
      initialOrderRef.current = ordered.map(t => t.id);
      upcoming.forEach(t => player.add({ uri: streamUrl(t.id), name: `${t.title} — ${t.artist}` }));
      player.loop = repeat;
      player.skipTo(0);
      setCurrent(selected);
      lastMetadataIdRef.current = selected.id;
      player.setActiveForLockScreen(true, metadata(selected), { showNextTrack: true, showPreviousTrack: true });
      player.play();
    } catch (e: any) { Alert.alert('Riproduzione non disponibile', e.message || String(e)); }
  }, [player, shuffle, repeat]);

  // Recommendations are queued *before* the current list ends, so native
  // playback can continue even if React Native is suspended on lock screen.
  const fillRadio = useCallback(async (force = false): Promise<boolean> => {
    const existing = queueRef.current;
    const position = Math.max(0, player.currentIndex);
    if (!autoRadio || !existing.length || radioBusyRef.current || (!force && existing.length - position > 4)) return false;
    const seed = existing[position] || existing[existing.length - 1];
    const generation = sessionRef.current;
    radioBusyRef.current = true; setRadioBusy(true);
    try {
      const queries = [
        getTracks(`/tracks/search?query=${encodeURIComponent(seed.artist)}&limit=35`),
        getTracks(`/tracks/trending?time=week&limit=45${seed.genre ? `&genre=${encodeURIComponent(seed.genre)}` : ''}`),
      ];
      const results = await Promise.allSettled(queries);
      if (generation !== sessionRef.current || !autoRadioRef.current) return false;
      let candidates = results.flatMap(r => r.status === 'fulfilled' ? r.value : []);
      let recommendations = radioSuggestions(seed, queueRef.current, candidates, 16);
      if (recommendations.length < 4) {
        const fallback = await getTracks('/tracks/trending?time=month&limit=80').catch(() => []);
        if (generation !== sessionRef.current || !autoRadioRef.current) return false;
        candidates = [...candidates, ...fallback];
        recommendations = radioSuggestions(seed, queueRef.current, candidates, 16);
      }
      if (!recommendations.length) {
        setRadioInfo('Nessun nuovo brano trovato. Prova un altro artista.');
        return false;
      }
      const oldLength = queueRef.current.length;
      const nextItems = [...queueRef.current, ...recommendations];
      recommendations.forEach(t => player.add({ uri: streamUrl(t.id), name: `${t.title} — ${t.artist}` }));
      commitQueue(nextItems);
      initialOrderRef.current = [...initialOrderRef.current, ...recommendations.map(t => t.id)];
      setRadioInfo(`Radio attiva: aggiunti ${recommendations.length} brani`);
      // If the current single track ended before the recommendation request
      // completed, recover playback when it ended naturally (not if paused).
      if (!player.playing && player.currentIndex >= oldLength - 1 && player.duration > 1
          && player.currentTime >= player.duration - 0.7) {
        player.next();
        player.play();
      }
      return true;
    } catch (e: any) {
      setRadioInfo(`Radio non disponibile: ${e.message || 'errore di rete'}`);
      return false;
    } finally {
      radioBusyRef.current = false; setRadioBusy(false);
    }
  }, [player, autoRadio]);

  useEffect(() => {
    if (autoRadio && queue.length && queue.length - currentIndex <= 4) void fillRadio();
  }, [autoRadio, queue.length, currentIndex, radioBusy, fillRadio]);

  useEffect(() => {
    const t = queueRef.current[status.currentIndex];
    if (!t || t.id === lastMetadataIdRef.current) return;
    lastMetadataIdRef.current = t.id;
    setCurrent(t);
    player.updateLockScreenMetadata(metadata(t));
  }, [status.currentIndex, queue, player]);

  const next = async () => {
    if (!queueRef.current.length) return;
    if (player.currentIndex >= queueRef.current.length - 1 && autoRadio) await fillRadio(true);
    player.next();
  };
  const previous = () => {
    if (status.currentTime > 3) { void player.seekTo(0); return; }
    player.previous();
  };
  const togglePlay = () => { if (status.playing) player.pause(); else player.play(); };
  const cycleRepeat = () => setRepeat(v => v === 'none' ? 'all' : v === 'all' ? 'single' : 'none');

  const changeShuffle = () => {
    const nextValue = !shuffle;
    setShuffle(nextValue);
    const items = queueRef.current;
    if (items.length < 3) return;
    const index = Math.max(0, player.currentIndex);
    const nextItems = nextValue
      ? shuffleUpcoming(items, index)
      : [...items.slice(0, index + 1), ...items.slice(index + 1).sort((a, b) =>
          initialOrderRef.current.indexOf(a.id) - initialOrderRef.current.indexOf(b.id))];
    const wasPlaying = player.playing;
    const playbackTime = player.currentTime;
    try {
      player.pause(); player.clear();
      commitQueue(nextItems);
      nextItems.forEach(t => player.add({ uri: streamUrl(t.id), name: `${t.title} — ${t.artist}` }));
      player.loop = repeat;
      player.skipTo(index);
      const t = nextItems[index];
      lastMetadataIdRef.current = t.id;
      setCurrent(t);
      player.setActiveForLockScreen(true, metadata(t), { showNextTrack: true, showPreviousTrack: true });
      void player.seekTo(playbackTime).then(() => { if (wasPlaying) player.play(); })
        .catch(() => { if (wasPlaying) player.play(); });
    } catch (e: any) { setError(`Impossibile modificare la riproduzione casuale: ${e.message}`); }
  };

  const queueTrack = (track: Track, playNext: boolean) => {
    if (!queueRef.current.length) { playList([track]); return; }
    const old = queueRef.current;
    const index = Math.max(0, player.currentIndex);
    const nextItems = [...old];
    const target = playNext ? index + 1 : nextItems.length;
    nextItems.splice(target, 0, track);
    try {
      if (playNext) player.insert({ uri: streamUrl(track.id), name: track.title }, target);
      else player.add({ uri: streamUrl(track.id), name: track.title });
      commitQueue(nextItems);
      if (playNext) initialOrderRef.current.splice(target, 0, track.id);
      else initialOrderRef.current.push(track.id);
      setRadioInfo(playNext ? 'Brano inserito subito dopo' : 'Brano aggiunto alla coda');
    } catch (e: any) { setError(`Impossibile aggiungere alla coda: ${e.message}`); }
  };
  const removeUpcoming = (index: number) => {
    if (index <= player.currentIndex) return;
    try {
      player.remove(index);
      commitQueue(queueRef.current.filter((_, i) => i !== index));
    } catch (e: any) { setError(e.message); }
  };

  const toggleFavorite = async (track: Track) => {
    const updated = favoriteIds.has(track.id)
      ? favorites.filter(t => t.id !== track.id) : [track, ...favorites];
    setFavorites(updated);
    await AsyncStorage.setItem(FAVORITES_KEY, JSON.stringify(updated)).catch(() => setError('Salvataggio preferiti non riuscito'));
  };
  const createList = async () => {
    const name = newListName.trim();
    if (!name) return;
    const newList = { id: `dvs-${Date.now()}`, name, tracks: [] as Track[] };
    const updated = [...lists, newList];
    setLists(updated); setOpenedList(newList.id); setTargetList(newList.id); setNewListName(''); setShowCreate(false);
    await AsyncStorage.setItem(PLAYLIST_KEY, JSON.stringify(updated)).catch(() => {});
  };
  const addToList = async (track: Track) => {
    if (!lists.length) {
      const newList = { id: `dvs-${Date.now()}`, name: 'La mia playlist', tracks: [track] };
      setLists([newList]); setTargetList(newList.id);
      await AsyncStorage.setItem(PLAYLIST_KEY, JSON.stringify([newList])).catch(() => {});
    } else {
      const id = targetList || lists[0].id;
      const updated = lists.map(l => l.id === id ? { ...l, tracks: distinctTracks([...l.tracks, track]) } : l);
      setLists(updated);
      await AsyncStorage.setItem(PLAYLIST_KEY, JSON.stringify(updated)).catch(() => {});
    }
    setRadioInfo('Brano salvato nella playlist');
  };
  const removeFromList = async (track: Track) => {
    if (!openedList) return;
    const updated = lists.map(l => l.id === openedList ? { ...l, tracks: l.tracks.filter(t => t.id !== track.id) } : l);
    setLists(updated);
    await AsyncStorage.setItem(PLAYLIST_KEY, JSON.stringify(updated)).catch(() => {});
  };
  const renderTrack = (track: Track, index: number, list: Track[], inPlaylist = false) => (
    <View key={`${track.id}-${index}`} style={styles.track}>
      <TouchableOpacity style={styles.trackMain} onLongPress={() => Alert.alert(track.title, track.artist, [
        { text: 'Riproduci dopo', onPress: () => queueTrack(track, true) },
        { text: 'Aggiungi in fondo alla coda', onPress: () => queueTrack(track, false) },
        { text: 'Annulla', style: 'cancel' },
      ])} onPress={() => {
        // Searching starts an automatic radio seeded by a *single* result.
        // Other sections respect the currently selected playlist/order.
        playList(tab === 'cerca' ? [track] : list, tab === 'cerca' ? 0 : index);
      }}>
        <MediaArt track={track} />
        <View style={styles.trackNames}>
          <Text numberOfLines={1} style={[styles.trackTitle, current?.id === track.id && { color: GREEN }]}>{track.title}</Text>
          <Text numberOfLines={1} style={styles.trackArtist}>{track.artist} · {time(track.duration)}</Text>
        </View>
      </TouchableOpacity>
      <TouchableOpacity accessibilityLabel="Riproduci dopo" style={styles.smallAction} onPress={() => queueTrack(track, true)}><Text style={styles.smallGlyph}>↳</Text></TouchableOpacity>
      <TouchableOpacity accessibilityLabel="Aggiungi a playlist" style={styles.smallAction} onPress={() => inPlaylist ? removeFromList(track) : addToList(track)}><Text style={styles.smallGlyph}>{inPlaylist ? '−' : '+'}</Text></TouchableOpacity>
      <TouchableOpacity accessibilityLabel="Preferiti" style={styles.smallAction} onPress={() => void toggleFavorite(track)}><Text style={[styles.smallGlyph, favoriteIds.has(track.id) && { color: GREEN }]}>{favoriteIds.has(track.id) ? '♥' : '♡'}</Text></TouchableOpacity>
    </View>
  );

  return (
    <SafeAreaView style={styles.safe}>
      <StatusBar barStyle="light-content" backgroundColor="#080B09" />
      <View style={styles.header}>
        <View style={styles.miniIcon}><Text style={styles.iconText}>▥</Text></View>
        <View><Text style={styles.logo}>DVS <Text style={{ color: GREEN }}>Music</Text></Text><Text style={styles.eyebrow}>IL TUO SOUND. SENZA PAUSE.</Text></View>
        <View style={styles.headerRight}><Text style={styles.headerRightText}>v0.4</Text></View>
      </View>
      {tab === 'youtube' ? <YouTubeBrowser /> : <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingHorizontal: 19, paddingBottom: current ? 180 : 110 }}>
        <Text style={styles.kicker}>DVS · MUSICA</Text>
        <Text style={styles.heading}>{tab === 'scopri' ? 'Scopri la musica' : tab === 'cerca' ? 'Cerca il tuo sound' : tab === 'libreria' ? 'La tua libreria' : tab === 'coda' ? 'Prossimi brani' : 'Video YouTube'}</Text>
        {tab === 'scopri' && <Text style={styles.subheading}>Riproduzione continua, playlist e Radio automatica. Catalogo audio Audius.</Text>}
        {tab === 'cerca' && <View style={styles.searchRow}>
          <TextInput style={styles.searchInput} placeholderTextColor="#819387" placeholder="Brano, artista o genere…" returnKeyType="search" value={query} onChangeText={setQuery} onSubmitEditing={search}/>
          <TouchableOpacity style={styles.searchButton} onPress={search}><Text style={styles.searchGlyph}>⌕</Text></TouchableOpacity>
        </View>}
        {tab === 'coda' && <>
          <View style={styles.infoCard}>
            <Text style={styles.cardTitle}>La tua riproduzione</Text>
            <View style={styles.setting}><Text style={styles.settingLabel}>Radio automatica · brani simili</Text><Switch value={autoRadio} onValueChange={setAutoRadio} thumbColor="#F5FFF9" trackColor={{ false: '#38513C', true: '#128D4A' }}/></View>
            <View style={styles.setting}><Text style={styles.settingLabel}>Casuale senza ripetizioni</Text><TouchableOpacity onPress={changeShuffle} style={[styles.chip, shuffle && styles.chipActive]}><Text style={[styles.chipLabel, shuffle && { color: '#07200F' }]}>{shuffle ? 'ON' : 'OFF'}</Text></TouchableOpacity></View>
            <View style={styles.setting}><Text style={styles.settingLabel}>Ripetizione</Text><TouchableOpacity onPress={cycleRepeat} style={styles.chip}><Text style={styles.chipLabel}>{repeat === 'none' ? 'Spenta' : repeat === 'all' ? 'Tutta la coda' : 'Un brano'}</Text></TouchableOpacity></View>
          </View>
          {queue.length ? <>
            <Text style={styles.sectionTitle}>In riproduzione · {queue.length} brani</Text>
            {queue.map((track, idx) => <View key={`${track.id}-${idx}`} style={[styles.track, idx === currentIndex && styles.activeRow]}>
              <TouchableOpacity style={styles.trackMain} onPress={() => { player.skipTo(idx); player.play(); }}>
                <MediaArt track={track} size={48} /><View style={styles.trackNames}><Text style={[styles.trackTitle, idx === currentIndex && { color: GREEN }]} numberOfLines={1}>{track.title}</Text><Text style={styles.trackArtist} numberOfLines={1}>{idx === currentIndex ? '♫ Ora' : idx < currentIndex ? 'Già ascoltato' : 'In coda'} · {track.artist}</Text></View>
              </TouchableOpacity>
              {idx > currentIndex && <TouchableOpacity onPress={() => removeUpcoming(idx)} style={styles.smallAction}><Text style={styles.smallGlyph}>×</Text></TouchableOpacity>}
            </View>)}
          </> : <Text style={styles.emptyTitle}>La coda è vuota. Seleziona un brano per iniziare.</Text>}
          {radioBusy && <Text style={styles.radioNote}>Sto preparando nuovi brani da ascoltare…</Text>}
        </>}
        {tab === 'libreria' && <>
          <View style={styles.libHeader}><Text style={styles.sectionTitle}>Le tue playlist</Text><TouchableOpacity onPress={() => setShowCreate(v => !v)} style={styles.chip}><Text style={styles.chipLabel}>+ Crea</Text></TouchableOpacity></View>
          {showCreate && <View style={styles.searchRow}>
            <TextInput value={newListName} onChangeText={setNewListName} placeholder="Nome della playlist" placeholderTextColor="#819387" style={styles.searchInput}/>
            <TouchableOpacity style={styles.searchButton} onPress={createList}><Text style={styles.searchGlyph}>✓</Text></TouchableOpacity>
          </View>}
          <ScrollView horizontal contentContainerStyle={{ gap: 10, paddingVertical: 9 }} showsHorizontalScrollIndicator={false}>
            <TouchableOpacity onPress={() => setOpenedList(null)} style={[styles.listChip, !openedList && styles.chipSelected]}><Text style={styles.listChipTitle}>♥ Preferiti</Text><Text style={styles.listChipCount}>{favorites.length} brani</Text></TouchableOpacity>
            {lists.map(l => <TouchableOpacity key={l.id} style={[styles.listChip, openedList === l.id && styles.chipSelected]} onPress={() => { setOpenedList(l.id); setTargetList(l.id); }}><Text numberOfLines={1} style={styles.listChipTitle}>{l.name}</Text><Text style={styles.listChipCount}>{l.tracks.length} brani</Text></TouchableOpacity>)}
          </ScrollView>
          {lists.length > 1 && <Text style={styles.subheading}>Playlist di destinazione per il tasto +: {lists.find(l => l.id === (targetList || lists[0].id))?.name}</Text>}
        </>}
        {error ? <Text style={styles.error}>{error}</Text> : null}
        {loading && <ActivityIndicator style={{ marginTop: 35 }} color={GREEN} />}
        {['scopri','cerca','libreria'].includes(tab) && !loading && <>
          <View style={styles.libHeader}><Text style={styles.sectionTitle}>{tab === 'scopri' ? 'In tendenza su Audius' : tab === 'cerca' ? `${results.length} risultati` : openedList ? lists.find(l => l.id === openedList)?.name : 'Brani preferiti'}</Text>
            {selectedList.length > 0 && <TouchableOpacity style={styles.chip} onPress={() => playList(selectedList)}><Text style={styles.chipLabel}>▶ Ascolta tutti</Text></TouchableOpacity>}
          </View>
          {!selectedList.length && <View style={styles.empty}><Text style={styles.emptySymbol}>♫</Text><Text style={styles.emptyTitle}>{tab === 'cerca' ? 'Cerca una canzone' : tab === 'libreria' ? 'Ancora nessun brano salvato' : 'Nessun risultato'}</Text></View>}
          {selectedList.map((t, i) => renderTrack(t, i, selectedList, tab === 'libreria' && !!openedList))}
        </>}
        {radioInfo && <Text style={styles.radioNote}>{radioInfo}</Text>}
      </ScrollView>}
      {current && tab !== 'youtube' && <View style={[styles.player, expanded && styles.playerExpanded]}>
        {expanded && <View style={styles.expandedContent}>
          <MediaArt track={current} size={200}/>
          <Text style={styles.expandedTitle} numberOfLines={2}>{current.title}</Text>
          <Text style={styles.expandedArtist}>{current.artist}</Text>
          <Pressable style={styles.progress} onLayout={e => setProgressWidth(e.nativeEvent.layout.width)} onPress={e => {
            const ratio = Math.max(0, Math.min(1, e.nativeEvent.locationX / progressWidth));
            void player.seekTo(ratio * status.duration);
          }}><View style={[styles.progressFill, { width: `${Math.max(0, Math.min(100, status.duration ? status.currentTime / status.duration * 100 : 0))}%` }]} /></Pressable>
          <View style={styles.times}><Text style={styles.time}>{time(status.currentTime)}</Text><Text style={styles.time}>{time(status.duration)}</Text></View>
          <View style={styles.bigControls}>
            <TouchableOpacity accessibilityLabel="Casuale" onPress={changeShuffle}><Text style={[styles.largeControl, shuffle && styles.controlActive]}>⤨</Text></TouchableOpacity>
            <TouchableOpacity accessibilityLabel="Precedente" onPress={previous}><Text style={styles.largeControl}>|◀</Text></TouchableOpacity>
            <TouchableOpacity accessibilityLabel="Play e pausa" onPress={togglePlay} style={styles.bigPlay}><Text style={styles.bigPlayText}>{status.playing ? 'Ⅱ' : '▶'}</Text></TouchableOpacity>
            <TouchableOpacity accessibilityLabel="Successivo" onPress={() => void next()}><Text style={styles.largeControl}>▶|</Text></TouchableOpacity>
            <TouchableOpacity accessibilityLabel="Ripeti" onPress={cycleRepeat}><Text style={[styles.largeControl, repeat !== 'none' && styles.controlActive]}>{repeat === 'single' ? '↺₁' : '↻'}</Text></TouchableOpacity>
          </View>
          <View style={styles.playerBottomControls}>
            <TouchableOpacity onPress={() => setAutoRadio(v => !v)} style={[styles.smallPill, autoRadio && styles.pillActive]}><Text style={styles.pillText}>♫ Radio {autoRadio ? 'ON' : 'OFF'}</Text></TouchableOpacity>
            <TouchableOpacity onPress={() => { setExpanded(false); setTab('coda'); }} style={styles.smallPill}><Text style={styles.pillText}>☷ Coda ({Math.max(0, queue.length - currentIndex - 1)})</Text></TouchableOpacity>
          </View>
          <Text style={styles.backgroundNote}>Audio nativo a schermo spento · sorgente Audius</Text>
        </View>}
        <View style={styles.playerLine}>
          <TouchableOpacity style={styles.trackMain} onPress={() => setExpanded(v => !v)}><MediaArt track={current} size={44}/><View style={styles.trackNames}><Text numberOfLines={1} style={styles.trackTitle}>{current.title}</Text><Text numberOfLines={1} style={styles.trackArtist}>{current.artist}</Text></View></TouchableOpacity>
          <TouchableOpacity onPress={togglePlay} style={styles.playBtn}><Text style={styles.playText}>{status.playing ? 'Ⅱ' : '▶'}</Text></TouchableOpacity>
          <TouchableOpacity onPress={() => setExpanded(v => !v)} style={styles.smallAction}><Text style={styles.collapseArrow}>{expanded ? '⌄' : '⌃'}</Text></TouchableOpacity>
        </View>
      </View>}
      <View style={styles.tabBar}>
        {([['scopri', '⌂', 'Scopri'], ['cerca', '⌕', 'Cerca'], ['libreria', '♡', 'Libreria'], ['coda', '☷', 'Coda'], ['youtube', '▷', 'YouTube']] as [Tab,string,string][]).map(([key, symbol, name]) =>
          <TouchableOpacity key={key} onPress={() => { if (key === 'youtube') player.pause(); setTab(key); setExpanded(false); }} style={styles.tab}><Text style={[styles.tabIcon, key === tab && { color: GREEN }]}>{symbol}</Text><Text style={[styles.tabLabel, key === tab && { color: GREEN }]}>{name}</Text></TouchableOpacity>)}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#080B09' },
  youtubeScreen: { flex: 1, paddingHorizontal: 15, paddingBottom: 76 },
  youtubeHeading: { color: '#F3FFF5', fontSize: 23, fontWeight: '900', marginTop: 9 },
  youtubeCaption: { color: '#98B49F', fontSize: 12, lineHeight: 18, marginTop: 4 },
  youtubeSearchRow: { flexDirection: 'row', gap: 7, marginTop: 13, marginBottom: 8 },
  youtubeSearchInput: { flex: 1, minWidth: 0, height: 45, borderColor: '#2A3A2E', borderWidth: 1, borderRadius: 11, backgroundColor: '#161E18', paddingHorizontal: 12, color: 'white' },
  youtubeSearchButton: { height: 45, width: 46, borderRadius: 11, alignItems: 'center', justifyContent: 'center', backgroundColor: GREEN },
  youtubeToolbar: { flexDirection: 'row', justifyContent: 'space-between', gap: 7, marginBottom: 9 },
  youtubeTool: { borderWidth: 1, borderColor: '#2E4A36', borderRadius: 9, paddingVertical: 7, paddingHorizontal: 10, alignItems: 'center' },
  youtubeToolText: { color: '#E2F4E6', fontWeight: '800', fontSize: 11 },
  youtubeToolDisabled: { color: '#627369' },
  youtubeWebContainer: { flex: 1, minHeight: 240, borderColor: '#285438', borderWidth: 1, borderRadius: 13, overflow: 'hidden', backgroundColor: '#101610' },
  youtubeWeb: { flex: 1, backgroundColor: '#101610' },
  youtubeLoading: { position: 'absolute', top: '45%', alignSelf: 'center' },
  youtubeError: { color: '#FFD1D1', fontSize: 12, marginBottom: 7 },
  youtubeNotice: { color: '#A1BCA9', fontSize: 10.5, lineHeight: 15, paddingTop: 7, paddingBottom: 4 },
  header: { height: 80, paddingHorizontal: 19, flexDirection: 'row', alignItems: 'center', gap: 11 },
  miniIcon: { width: 42, height: 42, borderRadius: 13, backgroundColor: '#123320', borderWidth: 1, borderColor: '#17643B', justifyContent: 'center', alignItems: 'center' },
  iconText: { fontSize: 24, color: GREEN, fontWeight: '900' },
  logo: { color: '#F0FFF3', fontSize: 23, fontWeight: '900', letterSpacing: -0.8 },
  eyebrow: { color: '#91A598', fontSize: 9, fontWeight: '700', letterSpacing: 1.7, marginTop: 3 },
  headerRight: { marginLeft: 'auto', borderWidth: 1, borderColor: '#24432D', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 30 },
  headerRightText: { color: '#82A18B', fontSize: 10, fontWeight: '800' },
  kicker: { color: GREEN, fontSize: 10, fontWeight: '900', letterSpacing: 2.5, marginTop: 24, marginBottom: 8 },
  heading: { fontSize: 29, fontWeight: '900', letterSpacing: -1, color: 'white', lineHeight: 36 },
  subheading: { fontSize: 13, color: '#8CA090', lineHeight: 21, marginTop: 8, marginBottom: 5 },
  searchRow: { flexDirection: 'row', marginTop: 22, gap: 8 },
  searchInput: { flex: 1, height: 53, backgroundColor: '#161E18', borderWidth: 1, borderColor: '#2A3A2E', borderRadius: 15, color: 'white', fontSize: 15, paddingHorizontal: 15 },
  searchButton: { width: 53, height: 53, backgroundColor: GREEN, borderRadius: 15, alignItems: 'center', justifyContent: 'center' },
  searchGlyph: { fontSize: 26, fontWeight: '700', color: '#0A2312' },
  libHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 9, marginTop: 24 },
  sectionTitle: { color: '#F6FFF8', fontSize: 17, fontWeight: '800', flexShrink: 1, marginBottom: 11, marginTop: 8 },
  track: { flexDirection: 'row', alignItems: 'center', paddingVertical: 9, borderBottomWidth: 1, borderBottomColor: '#18221B', gap: 4 },
  trackMain: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 11, minWidth: 0 },
  trackNames: { flex: 1, gap: 4, minWidth: 0 },
  trackTitle: { color: '#F3FFF5', fontWeight: '700', fontSize: 14 },
  trackArtist: { color: '#899D8E', fontSize: 11.5 },
  smallAction: { paddingHorizontal: 7, paddingVertical: 10, justifyContent: 'center', alignItems: 'center' },
  smallGlyph: { color: '#C4D7C9', fontSize: 21, fontWeight: '800' },
  activeRow: { backgroundColor: '#11281A', borderRadius: 12, paddingHorizontal: 5 },
  error: { color: '#FFD5D5', backgroundColor: '#442321', padding: 12, borderRadius: 9, marginTop: 15, fontSize: 12, lineHeight: 18 },
  radioNote: { color: '#9DE8B6', fontSize: 12, marginTop: 14, lineHeight: 19 },
  empty: { paddingVertical: 55, alignItems: 'center', gap: 8 },
  emptySymbol: { color: GREEN, fontSize: 43 },
  emptyTitle: { color: '#E7F5EB', marginTop: 10, fontSize: 14, fontWeight: '700' },
  infoCard: { marginTop: 20, backgroundColor: '#111C14', borderColor: '#2A4633', borderWidth: 1, borderRadius: 18, padding: 16 },
  cardTitle: { color: 'white', fontSize: 16, fontWeight: '800' },
  cardBody: { color: '#A2B5A7', lineHeight: 21, marginTop: 10, fontSize: 12 },
  primaryButton: { backgroundColor: GREEN, marginTop: 17, borderRadius: 12, alignItems: 'center', paddingVertical: 13 },
  primaryText: { color: '#05220E', fontWeight: '900', fontSize: 14 },
  setting: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 16, gap: 9 },
  settingLabel: { fontSize: 12, color: '#D4E8DA', flex: 1 },
  chip: { borderColor: '#3A5342', borderWidth: 1, paddingVertical: 9, paddingHorizontal: 11, borderRadius: 16 },
  chipActive: { backgroundColor: GREEN, borderColor: GREEN },
  chipLabel: { color: '#D8EFDD', fontSize: 11, fontWeight: '800' },
  listChip: { backgroundColor: '#19251D', borderRadius: 14, minWidth: 118, maxWidth: 160, padding: 14, borderWidth: 1, borderColor: '#21392B' },
  chipSelected: { borderColor: GREEN, backgroundColor: '#1A3925' },
  listChipTitle: { color: '#F0FFF1', fontWeight: '800', fontSize: 12 },
  listChipCount: { color: '#94B09B', fontSize: 11, marginTop: 7 },
  player: { position: 'absolute', left: 9, right: 9, bottom: 72, borderWidth: 1, borderColor: '#316847', backgroundColor: '#153521', borderRadius: 16, overflow: 'hidden', elevation: 12 },
  playerExpanded: { backgroundColor: '#101C14' },
  playerLine: { flexDirection: 'row', paddingHorizontal: 10, alignItems: 'center', height: 65, gap: 9 },
  playBtn: { backgroundColor: GREEN, width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  playText: { color: '#082714', fontWeight: '900', fontSize: 16 },
  collapseArrow: { color: '#B5D8C2', fontSize: 25 },
  expandedContent: { alignItems: 'center', paddingTop: 21, paddingHorizontal: 17, paddingBottom: 17 },
  expandedTitle: { color: 'white', fontSize: 21, fontWeight: '900', textAlign: 'center', marginTop: 15 },
  expandedArtist: { color: '#A9C3B0', fontSize: 13, marginTop: 6 },
  progress: { height: 9, width: '100%', backgroundColor: '#33523D', marginTop: 22, borderRadius: 8, overflow: 'hidden' },
  progressFill: { height: 9, backgroundColor: GREEN },
  times: { flexDirection: 'row', justifyContent: 'space-between', width: '100%', marginTop: 6 },
  time: { color: '#A3BFA9', fontSize: 11 },
  bigControls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', width: '100%', marginTop: 16 },
  largeControl: { color: '#D8EEDC', fontWeight: '800', fontSize: 23 },
  controlActive: { color: GREEN },
  bigPlay: { width: 60, height: 60, backgroundColor: GREEN, borderRadius: 30, justifyContent: 'center', alignItems: 'center' },
  bigPlayText: { fontWeight: '900', fontSize: 26, color: '#092813' },
  playerBottomControls: { flexDirection: 'row', gap: 10, marginTop: 19 },
  smallPill: { borderWidth: 1, borderColor: '#34543E', borderRadius: 18, paddingVertical: 10, paddingHorizontal: 14 },
  pillActive: { borderColor: GREEN },
  pillText: { color: '#D7F8DD', fontSize: 11, fontWeight: '800' },
  backgroundNote: { color: '#86A892', fontSize: 10, marginTop: 14 },
  tabBar: { position: 'absolute', bottom: 0, left: 0, right: 0, height: 72, flexDirection: 'row', backgroundColor: '#101813', borderTopWidth: 1, borderColor: '#1D3123', paddingBottom: 7 },
  tab: { flex: 1, justifyContent: 'center', alignItems: 'center', gap: 4 },
  tabIcon: { fontSize: 22, color: '#8A9F90' },
  tabLabel: { fontSize: 9, color: '#8A9F90', fontWeight: '700' },
});
