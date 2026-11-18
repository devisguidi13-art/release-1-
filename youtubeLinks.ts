/** Resolve typed searches and common YouTube links. Never proxy or extract streams. */
export function youtubeDestination(raw: string): string {
  const input = raw.trim();
  if (!input) return 'https://m.youtube.com/';
  const maybeUrl = /^(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com|youtu\.be)\//i.test(input);
  if (!maybeUrl) return `https://m.youtube.com/results?search_query=${encodeURIComponent(input)}`;
  try {
    const parsed = new URL(/^https?:\/\//i.test(input) ? input : `https://${input}`);
    const host = parsed.hostname.toLowerCase();
    if (!['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be', 'www.youtu.be'].includes(host)) {
      return `https://m.youtube.com/results?search_query=${encodeURIComponent(input)}`;
    }
    if (host.endsWith('youtu.be')) {
      const id = parsed.pathname.split('/').filter(Boolean)[0] || '';
      if (/^[a-zA-Z0-9_-]{11}$/.test(id)) return `https://m.youtube.com/watch?v=${id}`;
    }
    return parsed.toString();
  } catch {
    return `https://m.youtube.com/results?search_query=${encodeURIComponent(input)}`;
  }
}
