/** Pure queue helpers. No RN or network dependencies; tested with node. */
export type Track = {
  id: string;
  title: string;
  artist: string;
  artwork: string;
  duration: number;
  streamable: boolean;
  genre: string;
};
export type RepeatMode = 'none' | 'all' | 'single';

export function distinctTracks(tracks: Track[]): Track[] {
  const ids = new Set<string>();
  return tracks.filter(track => {
    if (!track?.id || ids.has(track.id)) return false;
    ids.add(track.id);
    return true;
  });
}

/** Start from the selected song, then play the rest of that list in order. */
export function rotateFromSelection(selected: Track, list: Track[]): Track[] {
  const all = distinctTracks([...(list.some(t => t.id === selected.id) ? list : [selected, ...list])]);
  const index = all.findIndex(t => t.id === selected.id);
  return [...all.slice(index), ...all.slice(0, index)];
}

export function shuffleTracks<T>(items: T[], random: () => number = Math.random): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.max(0, Math.min(0.9999999, random())) * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** Never shuffle the already-played section or the current song. */
export function shuffleUpcoming<T>(items: T[], currentIndex: number, random: () => number = Math.random): T[] {
  const start = Math.min(items.length, Math.max(0, currentIndex + 1));
  return [...items.slice(0, start), ...shuffleTracks(items.slice(start), random)];
}

/** Avoid repeats in autoplay radio; favor artist matches and, then, genre matches. */
export function radioSuggestions(seed: Track, heard: Track[], candidates: Track[], max = 15): Track[] {
  const seen = new Set(heard.map(t => t.id));
  const artist = seed.artist.trim().toLocaleLowerCase();
  const genre = seed.genre.trim().toLocaleLowerCase();
  return distinctTracks(candidates)
    .filter(t => t.streamable && !seen.has(t.id))
    .map((track, index) => ({
      track,
      index,
      score: (track.artist.toLocaleLowerCase() === artist ? 8 : 0) +
        (genre && track.genre.toLocaleLowerCase() === genre ? 3 : 0),
    }))
    .sort((a, b) => b.score - a.score || a.index - b.index)
    .slice(0, max)
    .map(entry => entry.track);
}
