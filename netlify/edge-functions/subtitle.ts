/**
 * Serves a catalogue subtitle as WebVTT.
 *
 * The catalogue stores SubRip. The browser receiver can fetch a .srt and
 * convert it itself, because it fetches the file as data — but a Chromecast
 * is handed a url and loads the track on its own, and Google's receiver
 * reads WebVTT and nothing else. A .srt sent to it is fetched, rejected and
 * dropped without a word, which from the sofa looks like a film with no
 * subtitles.
 *
 * So the phone sends the television this address instead, and the file is
 * rewritten in flight. Kilobytes, once per title.
 *
 * Same allow-list reasoning as the relay: an open converter is an open
 * proxy wearing a different hat.
 */

const ALLOWED_HOSTS = ['shabakaty.com'];

function allowed(host: string): boolean {
  const lower = host.toLowerCase();
  return ALLOWED_HOSTS.some((a) => lower === a || lower.endsWith('.' + a));
}

/**
 * SubRip to WebVTT.
 *
 * They differ in three details: the header line, a comma before the
 * milliseconds, and SubRip's habit of writing a single digit of hours where
 * WebVTT insists on two. SubStation override tags such as {\an8} ride along
 * in some files; WebVTT has no idea what they are and would print them in
 * the middle of the sentence, so they go.
 */
export function srtToVtt(text: string): string {
  const body = text
    .replace(/\r\n|\r/g, '\n')
    .replace(/^﻿/, '')
    .replace(/\{\\[^}]*\}/g, '')
    .replace(
      /(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})/g,
      (_m, h: string, m: string, s: string, ms: string) =>
        `${h.padStart(2, '0')}:${m}:${s}.${(ms + '00').slice(0, 3)}`,
    );
  return 'WEBVTT\n\n' + body;
}

export default async function subtitle(request: Request): Promise<Response> {
  const here = new URL(request.url);
  const raw = here.searchParams.get('u');
  if (!raw) return new Response('missing u', { status: 400 });

  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    return new Response('bad url', { status: 400 });
  }

  if (!allowed(target.hostname)) {
    return new Response('host not allowed: ' + target.hostname, { status: 403 });
  }

  // Bounded on purpose: an origin that never answers would otherwise
  // hold the request until the platform kills it, and the caller would
  // be told only that something timed out, not what.
  const cutoff = AbortSignal.timeout(8000);
  let upstream: Response;
  try {
    upstream = await fetch(target.toString(), { redirect: 'follow', signal: cutoff });
  } catch (e) {
    return new Response('upstream unreachable: ' + e, { status: 502 });
  }
  if (!upstream.ok) {
    return new Response('upstream said ' + upstream.status, { status: 502 });
  }

  const text = await upstream.text();
  const vtt = /^\s*WEBVTT/.test(text) ? text : srtToVtt(text);

  return new Response(vtt, {
    status: 200,
    headers: {
      'content-type': 'text/vtt; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      // The signed url it came from expires long before this would matter,
      // and a subtitle for a given title never changes.
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

export const config = { path: '/subtitle' };
