/**
 * Fetches a stream on behalf of a screen that cannot fetch it itself.
 *
 * A receiver — the browser page, or a Chromecast — is the one that pulls the
 * video, and some of our sources only answer a request that carries a
 * particular Referer and User-Agent. A browser will not let a page forge
 * either of those, and Google's default receiver takes no custom headers at
 * all, so those streams are unreachable from any screen but the phone's own
 * player. This sits in between and sends the headers the source wants.
 *
 * An edge function rather than an ordinary one on purpose: this streams the
 * body straight through instead of buffering it, so a video segment is not
 * held in memory and none of the size or duration ceilings apply.
 *
 * HLS is a playlist of many small files, and every one of them has to come
 * back through here too — otherwise the player reads our rewritten playlist
 * and then goes straight to the origin for the segments, without the
 * headers, and gets nothing. So playlists are rewritten on the way out.
 *
 * The allow-list is the point of the whole file. Without it this is an open
 * proxy on our own domain: anyone could route any traffic through it, and
 * the bill and the blame would both be ours.
 */

const ALLOWED_HOSTS = [
  // the film and series catalogue
  'shabakaty.com',
  // the live sports servers, which are the reason this exists
  'boomstreaming.com',
  'korax90.co',
];

/** Headers a source expects before it will serve a stream. */
const SOURCE_HEADERS: Record<string, Record<string, string>> = {
  'boomstreaming.com': {
    'User-Agent':
      'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    Referer: 'https://9.boomstreaming.com/',
  },
  'korax90.co': {
    'User-Agent':
      'Mozilla/5.0 (Linux; Android 14; SmartTV; SM-A266B) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    Referer: 'https://korax90.co/',
  },
};

function allowedHost(host: string): string | null {
  const lower = host.toLowerCase();
  for (const allowed of ALLOWED_HOSTS) {
    if (lower === allowed || lower.endsWith('.' + allowed)) return allowed;
  }
  return null;
}

function headersFor(allowed: string): Record<string, string> {
  return SOURCE_HEADERS[allowed] ?? {};
}

/** The relay url for [target], as seen from the receiver. */
function relayed(target: string, origin: string): string {
  return origin + '/relay?u=' + encodeURIComponent(target);
}

const PLAYLIST_TYPES = [
  'application/vnd.apple.mpegurl',
  'application/x-mpegurl',
  'audio/mpegurl',
];

function looksLikePlaylist(url: URL, contentType: string): boolean {
  if (PLAYLIST_TYPES.some((t) => contentType.toLowerCase().includes(t))) return true;
  return url.pathname.toLowerCase().endsWith('.m3u8');
}

/**
 * Points every url inside an HLS playlist back at this relay.
 *
 * Three kinds appear: a bare line (a segment or a nested playlist), a URI
 * inside a tag such as #EXT-X-KEY or #EXT-X-MEDIA, and comments that are
 * neither. Relative paths are resolved against the playlist's own address
 * first, because once the player is reading from our domain it has lost the
 * origin it would otherwise resolve against.
 */
function rewritePlaylist(body: string, base: URL, origin: string): string {
  const absolute = (ref: string) => {
    try {
      return relayed(new URL(ref, base).toString(), origin);
    } catch {
      return ref;
    }
  };

  return body
    .split('\n')
    .map((line) => {
      const trimmed = line.trim();
      if (trimmed === '') return line;

      if (trimmed.startsWith('#')) {
        // URI="..." appears in #EXT-X-KEY, #EXT-X-MEDIA, #EXT-X-MAP and more.
        return line.replace(
          /URI="([^"]+)"/g,
          (_m, ref) => 'URI="' + absolute(ref) + '"',
        );
      }

      return absolute(trimmed);
    })
    .join('\n');
}

export default async function relay(request: Request): Promise<Response> {
  const here = new URL(request.url);
  const raw = here.searchParams.get('u');

  if (!raw) {
    return new Response('missing u', { status: 400 });
  }

  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    return new Response('bad url', { status: 400 });
  }

  if (target.protocol !== 'https:' && target.protocol !== 'http:') {
    return new Response('unsupported scheme', { status: 400 });
  }

  const allowed = allowedHost(target.hostname);
  if (!allowed) {
    // Not one of ours. Saying which host was refused makes a misconfigured
    // source obvious in the receiver's console instead of silent.
    return new Response('host not allowed: ' + target.hostname, { status: 403 });
  }

  const outbound = new Headers(headersFor(allowed));
  // Seeking and the player's own chunking both depend on ranges reaching
  // the origin untouched.
  const range = request.headers.get('range');
  if (range) outbound.set('Range', range);

  // Bounded on purpose: an origin that never answers would otherwise
  // hold the request until the platform kills it, and the caller would
  // be told only that something timed out, not what.
  const cutoff = AbortSignal.timeout(8000);
  let upstream: Response;
  try {
    upstream = await fetch(target.toString(), {
      headers: outbound,
      redirect: 'follow',
      signal: cutoff,
    });
  } catch (e) {
    return new Response('upstream unreachable: ' + e, { status: 502 });
  }

  const contentType = upstream.headers.get('content-type') ?? '';
  const out = new Headers();
  out.set('Access-Control-Allow-Origin', '*');
  out.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
  for (const name of ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
    const value = upstream.headers.get(name);
    if (value) out.set(name, value);
  }

  if (looksLikePlaylist(target, contentType)) {
    // Small enough to read whole, and it has to be read whole to rewrite it.
    const text = await upstream.text();
    const rewritten = rewritePlaylist(text, new URL(upstream.url || target.toString()), here.origin);
    out.set('content-type', 'application/vnd.apple.mpegurl');
    out.delete('content-length');
    // A live playlist is rewritten every few seconds and must never be held.
    out.set('Cache-Control', 'no-store');
    return new Response(rewritten, { status: upstream.status, headers: out });
  }

  // Everything else — the video itself — passes through without being held.
  return new Response(upstream.body, { status: upstream.status, headers: out });
}

export const config = { path: '/relay' };
