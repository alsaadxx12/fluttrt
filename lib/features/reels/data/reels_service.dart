import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';
import 'package:youtube_downloader/features/reels/data/reel_letterbox.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/trailers/data/movie_trailer.dart';
import 'package:youtube_downloader/features/trailers/data/tmdb_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The author line a reel carries when its channel is not known.
const String kReelTrailerAuthor = 'إعلان رسمي';

/// One vertical short — the official trailer — of a film or series of the
/// app's own catalogue, played from YouTube.
///
/// Every reel the feed hands out has been probed: upright (taller than
/// wide, so it fills the screen without cropping), at least 1080 pixels
/// across, and no longer than [kReelShortMaxDuration], so it plays whole at
/// that quality — and passed [reelIsOfficialShort]: the title's own
/// trailer, not a fan's clip.
class Reel {
  const Reel({
    required this.id,
    required this.title,
    required this.author,
    required this.channelId,
    required this.description,
    required this.duration,
    required this.viewCount,
    required this.likeCount,
    required this.uploadDate,
    this.kind = kindTrailer,
    this.thumbnail,
    this.catalogItem,
    ReelLane? lane,
  }) : _lane = lane;

  /// A film's short: every reel is one.
  static const String kindTrailer = 'trailer';

  /// The YouTube id.
  final String id;

  /// The film's title (with its year) for a reel found for a film; the
  /// short's own title for one found by a direct search.
  final String title;

  /// The short's channel, or [kReelTrailerAuthor] when it is not known.
  final String author;

  /// The short's channel; null when it is not known.
  final String? channelId;
  final String description;
  final Duration? duration;

  /// Null when the source did not carry it; the search cell then shows no
  /// count.
  final int? viewCount;

  /// Null when the source did not carry it (search results never do); the
  /// page can fill it in from the watch page later.
  final int? likeCount;
  final DateTime? uploadDate;

  /// [kindTrailer].
  final String kind;

  /// The film's own artwork (its catalogue poster, upright like the page)
  /// when the source had one; null means YouTube's frame is used.
  final String? thumbnail;

  /// The catalogue entry the short belongs to — the same film or series
  /// the app's cards show — so the page can open it; null for a reel that
  /// was not found for a catalogue title.
  final CinemanaItem? catalogItem;

  /// The lane the reel was drawn from, as it was written down; null for one
  /// kept on the device before the lanes were (see [lane]).
  final ReelLane? _lane;

  bool get isTrailer => kind == kindTrailer;

  /// True when the reel belongs to a series of the catalogue — an anime is
  /// one of those too, so the pill reads [lane] rather than this.
  bool get isSeries => catalogItem?.isSeries ?? false;

  /// Which of the feed's lanes the reel came from; for a reel kept before
  /// the lane was written down, what its catalogue entry says it is.
  ReelLane get lane => _lane ?? (isSeries ? ReelLane.series : ReelLane.film);

  /// True for a reel of the catalogue's anime lane.
  bool get isAnime => lane == ReelLane.anime;

  /// The picture under the player: the film's artwork when there is one,
  /// else the vertical (9:16) thumbnail YouTube renders for Shorts.
  String get thumbnailUrl => thumbnail ?? 'https://i.ytimg.com/vi/$id/oardefault.jpg';

  /// The 16:9 thumbnail every video has, for when the first one is missing.
  String get fallbackThumbnailUrl => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  /// The link handed to the share sheet.
  String get shareUrl => 'https://youtu.be/$id';

  /// A reel of one of the trailers the app's «مقاطع وإعلانات» row shows:
  /// the film's title and year, its TMDB artwork, and its own official
  /// trailer on YouTube.
  factory Reel.fromTrailer(MovieTrailer t) => Reel(
        id: t.youtubeId!,
        title: reelTitleWithYear(t.title, t.year),
        author: kReelTrailerAuthor,
        channelId: null,
        description: t.overview,
        duration: null,
        viewCount: null,
        likeCount: null,
        uploadDate: null,
        kind: kindTrailer,
        thumbnail: t.posterUrl ?? t.bestImage,
        lane: ReelLane.film,
      );

  /// A reel of a search hit as it is: the short's own title, its channel
  /// when YouTube named one, its view count.
  factory Reel.fromHit(ReelSearchHit h) => Reel(
        id: h.id,
        title: h.title,
        author: h.author.isNotEmpty ? h.author : kReelTrailerAuthor,
        channelId: null,
        description: '',
        duration: h.duration,
        viewCount: h.viewCount,
        likeCount: null,
        uploadDate: null,
        kind: kindTrailer,
      );

  @override
  bool operator ==(Object other) => other is Reel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// «Title (year)» when the year is known, else the title alone.
String reelTitleWithYear(String title, String? year) {
  final t = title.trim();
  final y = year?.trim() ?? '';
  return y.isEmpty ? t : '$t ($y)';
}

/// A film (or series) the feed looks for a vertical short of: its titles
/// (the English one for the search, the Arabic one for the page), its year
/// and artwork, and the catalogue entry it came from.
class ReelFilm {
  const ReelFilm({
    required this.titleEn,
    this.titleAr = '',
    this.original = '',
    this.year,
    this.poster,
    this.overview = '',
    this.isSeries = false,
    this.isAnime = false,
    this.item,
  });

  /// The English title; empty when the source has none.
  final String titleEn;

  /// The Arabic title; empty when the source has none.
  final String titleAr;

  /// The title in the film's own language when it is neither of the two;
  /// only for matching a short's title.
  final String original;
  final String? year;

  /// The upright poster, when the source has one.
  final String? poster;
  final String overview;

  /// True for a series of the catalogue.
  final bool isSeries;

  /// True for a title of the catalogue's anime section, which is a series
  /// too: its short is looked for with the anime queries (see
  /// [reelShortQueries]).
  final bool isAnime;

  /// The catalogue entry, handed on to the reel (see [Reel.catalogItem]).
  final CinemanaItem? item;

  /// The title the page shows: Arabic when there is one.
  String get title => titleAr.isNotEmpty ? titleAr : (titleEn.isNotEmpty ? titleEn : original);

  /// The title the YouTube queries are built on: English when there is one.
  String get searchTitle => titleEn.isNotEmpty ? titleEn : (titleAr.isNotEmpty ? titleAr : original);

  /// Every title a short's title may carry, without repeats or blanks.
  List<String> get names => {
        for (final n in [titleEn, titleAr, original])
          if (n.trim().isNotEmpty) n.trim(),
      }.toList();

  /// Identifies the film across the lanes and the catalogue's sources (the
  /// same title can come twice): its normalised search title and year.
  String get key => '${reelNormalizeTitle(searchTitle)}|${year ?? ''}';

  @override
  String toString() => 'ReelFilm(${reelTitleWithYear(title, year)})';
}

/// One batch of reels plus what is needed to ask for the next one.
class ReelsPage {
  const ReelsPage({
    required this.items,
    required this.hasMore,
    this.cursor,
    this.failed = false,
  });

  final List<Reel> items;
  final bool hasMore;

  /// Opaque paging state; hand the page back as `after:` to continue.
  final ReelsCursor? cursor;

  /// True when the request itself failed (network, timeout) rather than
  /// simply returning nothing: the page may show a retry.
  final bool failed;

  static const ReelsPage empty = ReelsPage(items: [], hasMore: false);
}

/// Where paging stands for the three lanes of the feed (or for a search):
/// the titles each lane fetched but has not yet looked for a short of,
/// where its next fetch starts, how often it came back with nothing, every
/// id handed out so far (so the feed never repeats a short), and a tally of
/// the titles looked at and the ones that had a short.
class ReelsCursor {
  const ReelsCursor({
    this.seen = const {},
    this.films = const [],
    this.series = const [],
    this.anime = const [],
    this.filmPage = 0,
    this.seriesPage = 0,
    this.animePage = 0,
    this.filmMisses = 0,
    this.seriesMisses = 0,
    this.animeMisses = 0,
    this.filmsSearched = 0,
    this.filmsMatched = 0,
    this.query,
  });

  /// How many consecutive empty fetches dry a lane up.
  static const int laneMisses = 3;

  final Set<String> seen;

  /// Fetched, not yet searched: the catalogue's newest films, its newest
  /// series and its newest anime, each in the order the catalogue gave them
  /// — newest first. For a search, [films] holds the titles the catalogue
  /// found for the query that have not been looked at yet.
  final List<ReelFilm> films;
  final List<ReelFilm> series;
  final List<ReelFilm> anime;

  /// The next catalogue page of each lane (0-based).
  final int filmPage;
  final int seriesPage;
  final int animePage;

  /// Consecutive fetches that brought nothing new, per lane.
  final int filmMisses;
  final int seriesMisses;
  final int animeMisses;

  /// Running totals: titles a short was looked for, and titles that had one.
  final int filmsSearched;
  final int filmsMatched;

  /// For [ReelsService.search]: the query the cursor belongs to; null for
  /// the feed, and after a search whose catalogue lookup failed (so the
  /// next ask starts over).
  final String? query;

  bool get filmsDry => filmMisses >= laneMisses;
  bool get seriesDry => seriesMisses >= laneMisses;
  bool get animeDry => animeMisses >= laneMisses;

  /// Nothing left anywhere: every lane is dry and nothing is waiting.
  bool get exhausted =>
      filmsDry && seriesDry && animeDry && films.isEmpty && series.isEmpty && anime.isEmpty;
}

/// How many reels make one page of the feed.
const int kReelsPageSize = 8;

/// The longest a short may run: YouTube's classic Short, and the longest
/// clip whose 1080p pair YouTube serves whole ([kReelAdaptiveMaxDuration]).
const Duration kReelShortMaxDuration = Duration(seconds: 60);

/// The lanes a page is drawn from: the catalogue's newest films, its newest
/// series and its newest anime.
enum ReelLane { film, series, anime }

/// The slot pattern of a page, repeated: one of the newest films, one of
/// the newest series, another film, one of the newest anime — the films
/// twice a cycle, since the catalogue brings more of them.
const List<ReelLane> kReelPagePattern = [
  ReelLane.film,
  ReelLane.series,
  ReelLane.film,
  ReelLane.anime,
];

/// The lane [name] stands for ('film', 'series', 'anime'); null for
/// anything else — a reel kept on the device before the lane was written
/// down carries no name at all.
ReelLane? reelLaneNamed(String? name) {
  for (final lane in ReelLane.values) {
    if (lane.name == name) return lane;
  }
  return null;
}

/// Words that mark a search result as something other than a clip of the
/// film itself.
const List<String> kReelNoiseWords = [
  'gameplay',
  'reaction',
  'react',
  'tutorial',
  'unboxing',
  'vlog',
  'podcast',
  'asmr',
  'lyrics',
  'music video',
  'review',
  'explained',
  'recap',
  'breakdown',
  'theory',
  'ردة فعل',
  'رد فعل',
];

/// Channels whose clips are never film clips, by a word in their name.
const List<String> kReelNoiseAuthors = ['news', 'أخبار', 'نيوز'];

/// True when [text] carries [word] as a word of its own (a plural «s»
/// allowed), case-insensitively: «review» is not found in «preview».
bool _hasWord(String text, String word) =>
    RegExp('(^|[^a-z])${RegExp.escape(word)}s?(\$|[^a-z])', caseSensitive: false).hasMatch(text);

/// True when [title] carries one of [kReelNoiseWords], or [author] one of
/// [kReelNoiseAuthors], as whole words (both case-insensitive).
bool isFilmNoise(String title, {String author = ''}) {
  if (kReelNoiseWords.any((w) => _hasWord(title, w))) return true;
  return kReelNoiseAuthors.any((w) => _hasWord(author, w));
}

/// Words in a short's title that say it is the title's own trailer. «pv»
/// («promotion video») is what an anime's own trailer is called.
const List<String> kReelOfficialWords = [
  'trailer',
  'teaser',
  'official',
  'pv',
  'promotion video',
  'إعلان',
  'تريلر',
  'اعلان',
  'رسمي',
];

/// Words in a channel's name that mark a studio, a network or a streaming
/// service — a channel whose shorts are the trailers themselves.
const List<String> kReelOfficialChannels = [
  'official',
  'pictures',
  'studios',
  'films',
  'entertainment',
  'netflix',
  'hbo',
  'max',
  'disney',
  'warner',
  'universal',
  'paramount',
  'sony',
  'lionsgate',
  'a24',
  'marvel',
  'dc',
  'shahid',
  'osn',
  'watch it',
  'mbc',
  'rotana',
  'prime video',
  'apple tv',
  'peacock',
  'hulu',
  'crunchyroll',
  'toho',
  'aniplex',
  'kadokawa',
  // The anime studios, labels and networks whose channels carry the PVs.
  // The ones already covered above are not repeated: «netflix anime» by
  // «netflix», «toho animation» by «toho», «avex pictures» and «a-1
  // pictures» by «pictures», «wit studio», «studio bones» and «studio
  // trigger» by «studios».
  'toei',
  'muse asia',
  'ani-one',
  'bandai',
  'pony canyon',
  'king records',
  'tv tokyo',
  'mappa',
  'ufotable',
  'madhouse',
  'kyoto animation',
  'cloverworks',
  'sunrise',
  'production i.g',
  'shueisha',
];

/// Words in a title or a channel's name that mark a fan's clip — an edit,
/// a reaction, a status clip, a compilation — rather than the trailer.
/// «part » stands for a clip cut into numbered parts («part 3»); «amv» is
/// the anime equivalent of a fan edit.
const List<String> kReelFanWords = [
  'edit',
  'edits',
  'amv',
  'fan',
  'reaction',
  'react',
  'tiktok',
  'funny',
  'meme',
  'explained',
  'recap',
  'review',
  'status',
  'whatsapp',
  'ringtone',
  'part ',
  'scene pack',
  'scenepack',
  'clip',
  'shorts channel',
  'compilation',
  'ترند',
  'ريأكشن',
  'مقطع مضحك',
  'حالات',
  'ستوري',
];

/// True when [text] carries [mark], case-insensitively: a Latin mark as a
/// word of its own, singular or plural either way («films» finds «Film»,
/// «edit» finds «edits»); an Arabic mark anywhere once both are normalised
/// (an Arabic word carries its prefixes: «الإعلان»); and a mark ending in
/// a space («part ») as the word with a number after it («part 3»), so
/// «Dune: Part Two» is not a numbered part.
bool reelHasMark(String text, String mark) {
  final m = mark.trim();
  if (m.isEmpty) return false;
  if (_hasArabic(m)) return reelNormalizeTitle(text).contains(reelNormalizeTitle(m));
  if (mark.endsWith(' ')) {
    return RegExp('(^|[^a-z])${RegExp.escape(m)}\\s*[0-9]', caseSensitive: false).hasMatch(text);
  }
  final stem = m.length > 3 && m.endsWith('s') ? m.substring(0, m.length - 1) : m;
  return _hasWord(text, stem);
}

/// True when [title] says the clip is the title's own trailer (one of
/// [kReelOfficialWords]).
bool reelHasOfficialMark(String title) => kReelOfficialWords.any((w) => reelHasMark(title, w));

/// True when [author] reads like a studio's, a network's or a streaming
/// service's channel (one of [kReelOfficialChannels]); never for an
/// unknown (empty) channel.
bool reelIsOfficialChannel(String author) =>
    author.trim().isNotEmpty && kReelOfficialChannels.any((w) => reelHasMark(author, w));

/// True when [title] or [author] carries one of [kReelFanWords].
bool reelIsFanClip(String title, {String author = ''}) =>
    kReelFanWords.any((w) => reelHasMark(title, w) || reelHasMark(author, w));

/// The rule every reel passes, over and above the picture's: the clip is
/// the title's own trailer — its title says so ([reelHasOfficialMark]) or
/// it comes from an official channel ([reelIsOfficialChannel]) — and
/// neither its title nor its channel marks it as a fan's clip
/// ([reelIsFanClip]) or as noise ([isFilmNoise]). A short whose channel
/// is not known passes on its title alone.
bool reelIsOfficialShort(String title, {String author = ''}) {
  if (reelIsFanClip(title, author: author)) return false;
  if (isFilmNoise(title, author: author)) return false;
  return reelHasOfficialMark(title) || reelIsOfficialChannel(author);
}

/// Accented Latin letters and their plain forms, for [reelNormalizeTitle].
const Map<String, String> _kLatinFolds = {
  'àáâãäåāăą': 'a',
  'çćč': 'c',
  'ďđ': 'd',
  'èéêëēėęě': 'e',
  'ğ': 'g',
  'ìíîïī': 'i',
  'ł': 'l',
  'ñńň': 'n',
  'òóôõöøō': 'o',
  'ř': 'r',
  'šśş': 's',
  'ťţ': 't',
  'ùúûüūů': 'u',
  'ýÿ': 'y',
  'žźż': 'z',
};

/// English words that a short's title drops or keeps at whim; taken out of
/// both sides when enough is left to tell the film by.
const Set<String> _kStopWords = {'the', 'a', 'an', 'of', 'and'};

/// Arabic diacritics, the tatweel and the Quranic marks: dropped.
final RegExp _kArabicMarks = RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]');

/// Anything that is not a letter or a digit: a break between words.
final RegExp _kNotWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// [title] as it is compared: lower-case, accents and Arabic diacritics
/// dropped, the alef, ta marbuta and alef maqsura forms unified, «&» read
/// as «and», punctuation turned into single spaces, and the English
/// articles («the», «a», «of», «and») left out when at least two words
/// remain without them. `«Dune: Part Two»` and `«dune part two #shorts»`
/// share `dune part two`.
String reelNormalizeTitle(String title) {
  var t = title.toLowerCase().replaceAll('&', ' and ');
  final buf = StringBuffer();
  for (final rune in t.runes) {
    final ch = String.fromCharCode(rune);
    var out = ch;
    for (final e in _kLatinFolds.entries) {
      if (e.key.contains(ch)) {
        out = e.value;
        break;
      }
    }
    buf.write(out);
  }
  t = buf
      .toString()
      .replaceAll(_kArabicMarks, '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(_kNotWord, ' ')
      .trim();
  final words = t.split(' ').where((w) => w.isNotEmpty).toList();
  final kept = words.where((w) => !_kStopWords.contains(w)).toList();
  return (kept.length >= 2 ? kept : words).join(' ');
}

/// The parts of a title with a subtitle — «Mission: Impossible – The Final
/// Reckoning» — that can stand for the film on their own: the subtitle
/// parts (never the first, the franchise's name, which «Turning Point: The
/// Vietnam War» shares with «Turning Point: Generation 9/11»), each of at
/// least two words and eight letters, normalised. Empty for a plain title.
List<String> reelTitleParts(String title) {
  final parts = title.split(RegExp(r'[:|]|\s[-–—]\s'));
  if (parts.length < 2) return const [];
  return [
    for (final p in parts.skip(1).map(reelNormalizeTitle))
      if (p.split(' ').length >= 2 && p.replaceAll(' ', '').length >= 8) p,
  ];
}

/// The longest of [names] (a film's titles) — or of the parts of a
/// subtitled name that can stand on their own ([reelTitleParts]) — that
/// [candidate] (a short's title) carries as whole words once both are
/// normalised; null when it carries none.
String? reelTitleMatch(String candidate, Iterable<String> names) {
  final c = ' ${reelNormalizeTitle(candidate)} ';
  if (c.trim().isEmpty) return null;
  String? best;
  void consider(String n) {
    if (n.isEmpty || !c.contains(' $n ')) return;
    if (best == null || n.length > best!.length) best = n;
  }

  for (final name in names) {
    consider(reelNormalizeTitle(name));
    reelTitleParts(name).forEach(consider);
  }
  return best;
}

/// True when [candidate] carries one of [names] (see [reelTitleMatch]).
bool reelTitleMatches(String candidate, Iterable<String> names) => reelTitleMatch(candidate, names) != null;

/// True when [title] pins a short to a film or series by more than a name:
/// «trailer» or «تريلر», or «إعلان» with «فيلم» or «مسلسل». Asked of a
/// short matched on a one-word name alone («Couture», «Saipan»), which a
/// fashion show or a battle may share: «official» or «teaser» is not
/// enough then.
bool reelPinsFilm(String title) =>
    reelHasMark(title, 'trailer') ||
    reelHasMark(title, 'تريلر') ||
    (reelHasMark(title, 'إعلان') && (reelHasMark(title, 'فيلم') || reelHasMark(title, 'مسلسل')));

/// The YouTube queries for [film]'s official vertical short, in the order
/// they are tried: the English title as an official trailer with «#shorts»,
/// with its year as a trailer, as a teaser; then — when the Arabic title
/// is its own, not the English one again — the Arabic title with «إعلان»
/// and with «تريلر».
///
/// An anime ([ReelFilm.isAnime]) is asked for differently: its own trailer
/// is a «PV», the year is rarely in the title, and «anime trailer» tells a
/// series' PV from a film of the same name.
List<String> reelShortQueries(ReelFilm film) {
  final en = film.searchTitle.trim();
  final ar = film.titleAr.trim();
  final year = film.year?.trim() ?? '';
  final out = <String>{};
  if (en.isNotEmpty) {
    out.add('$en official trailer #shorts');
    if (film.isAnime) {
      out.add('$en pv shorts');
      out.add('$en teaser shorts');
      out.add('$en anime trailer shorts');
    } else {
      if (year.isNotEmpty) out.add('$en $year trailer shorts');
      out.add('$en teaser shorts');
    }
  }
  if (ar.isNotEmpty && ar != film.titleEn.trim()) {
    out.add('$ar إعلان');
    out.add('$ar تريلر');
  }
  return out.toList();
}

/// True when [title] says the clip is a Short.
bool reelSaysShorts(String title) {
  final t = title.toLowerCase();
  return t.contains('#short') || t.contains('shorts');
}

/// One video in YouTube's search answer: a Short off the Shorts shelf
/// (YouTube prints neither its length nor its channel there) or a regular
/// video with both.
class ReelSearchHit {
  const ReelSearchHit({
    required this.id,
    required this.title,
    this.author = '',
    this.duration,
    this.viewCount,
    this.short = false,
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  final String id;
  final String title;

  /// The channel's name; empty when YouTube did not print it.
  final String author;

  /// The length YouTube printed; null for a Short off the shelf and for a
  /// live stream.
  final Duration? duration;
  final int? viewCount;

  /// True when YouTube listed it on its Shorts shelf: a Short, then, though
  /// its length is not printed there.
  final bool short;

  /// The size of the frame YouTube shows for a Short off the shelf, which
  /// it marks as the clip's own aspect (1080×1920 for an upright one); 0
  /// when not given. A hint for the order of probing, not a measurement:
  /// the manifest decides.
  final int frameWidth;
  final int frameHeight;

  /// True when the frame says the clip is upright.
  bool get portraitHint => frameWidth > 0 && frameHeight > frameWidth;

  /// True when the frame says the clip is wider than tall: no probe can
  /// make it upright.
  bool get landscapeHint => frameHeight > 0 && frameWidth > frameHeight;

  /// True when the clip may be a Short of [kReelShortMaxDuration] at most:
  /// listed as one, or printed with a length inside it. A regular video
  /// with no length is a live stream or an upcoming one.
  bool get mayBeShort {
    final d = duration;
    if (d != null) return d > Duration.zero && d <= kReelShortMaxDuration;
    return short;
  }

  /// The hit with [name] as its channel when the search printed none (a
  /// Short off the shelf); the hit itself when it already has one, or
  /// [name] is blank.
  ReelSearchHit withChannel(String name) {
    final n = name.trim();
    if (author.isNotEmpty || n.isEmpty) return this;
    return ReelSearchHit(
      id: id,
      title: title,
      author: n,
      duration: duration,
      viewCount: viewCount,
      short: short,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }

  @override
  String toString() => 'ReelSearchHit($id, ${short ? 'short' : '${duration?.inSeconds ?? '?'} s'}, $title)';
}

/// «3:24» or «1:02:03» as YouTube prints a length; null for anything else.
Duration? parseReelDuration(String text) {
  final parts = text.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  var total = 0;
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null || n < 0) return null;
    total = total * 60 + n;
  }
  return Duration(seconds: total);
}

/// A view count as YouTube prints it — «3,591,250 views», «2.7M views»,
/// «2.7 million views», «No views» — as a number; null when there is none
/// in [text].
int? parseReelViewCount(String text) {
  final t = text.trim().toLowerCase();
  if (t.startsWith('no views')) return 0;
  final m = RegExp(r'([\d][\d,\.]*)\s*(thousand|million|billion|k|m|b)?\b').firstMatch(t);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!.replaceAll(',', ''));
  if (n == null) return null;
  final scale = switch (m.group(2)) {
    'k' || 'thousand' => 1000,
    'm' || 'million' => 1000000,
    'b' || 'billion' => 1000000000,
    _ => 1,
  };
  return (n * scale).round();
}

/// What an innertube search answer (or a continuation of one) carries: the
/// videos in YouTube's order and the token for the next batch, if any.
typedef ReelSearchAnswer = ({List<ReelSearchHit> hits, String? continuation});

/// [json] (a decoded `/youtubei/v1/search` answer, first page or
/// continuation) read for its videos — the Shorts shelf's
/// `shortsLockupViewModel` and `reelItemRenderer` entries, and the regular
/// `videoRenderer` ones — in the order they appear, and for the first
/// continuation token. An entry with no id is dropped. Pure.
ReelSearchAnswer parseReelSearch(Map<String, dynamic> json) {
  final hits = <ReelSearchHit>[];
  String? continuation;

  void walk(Object? node) {
    if (node is List) {
      node.forEach(walk);
      return;
    }
    if (node is! Map) return;
    final map = Map<String, dynamic>.from(node);
    final video = _map(map['videoRenderer']);
    if (video.isNotEmpty) {
      final hit = _hitFromVideoRenderer(video);
      if (hit != null) hits.add(hit);
      return;
    }
    final lockup = _map(map['shortsLockupViewModel']);
    if (lockup.isNotEmpty) {
      final hit = _hitFromShortsLockup(lockup);
      if (hit != null) hits.add(hit);
      return;
    }
    final reel = _map(map['reelItemRenderer']);
    if (reel.isNotEmpty) {
      final hit = _hitFromReelItem(reel);
      if (hit != null) hits.add(hit);
      return;
    }
    final cont = _map(map['continuationItemRenderer']);
    if (cont.isNotEmpty) {
      final command = _map(_map(cont['continuationEndpoint'])['continuationCommand']);
      final token = '${command['token'] ?? ''}';
      if (token.isNotEmpty) continuation ??= token;
      return;
    }
    map.values.forEach(walk);
  }

  walk(json);
  return (hits: hits, continuation: continuation);
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// The text of a `{runs: [{text}]}` or `{simpleText}` node.
String _text(Object? node) {
  final m = _map(node);
  if (m.isEmpty) return '';
  final simple = m['simpleText'];
  if (simple is String) return simple.trim();
  final runs = m['runs'];
  if (runs is List) return runs.map((r) => '${_map(r)['text'] ?? ''}').join().trim();
  final content = m['content'];
  return content is String ? content.trim() : '';
}

/// A YouTube id is exactly eleven characters of its own alphabet.
bool _isVideoId(String id) => RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);

ReelSearchHit? _hitFromVideoRenderer(Map<String, dynamic> v) {
  final id = '${v['videoId'] ?? ''}';
  if (!_isVideoId(id)) return null;
  final title = _text(v['title']);
  if (title.isEmpty) return null;
  final author = _text(v['ownerText']).isNotEmpty ? _text(v['ownerText']) : _text(v['longBylineText']);
  final length = _text(v['lengthText']);
  return ReelSearchHit(
    id: id,
    title: title,
    author: author,
    duration: length.isEmpty ? null : parseReelDuration(length),
    viewCount: parseReelViewCount(_text(v['viewCountText'])),
  );
}

ReelSearchHit? _hitFromShortsLockup(Map<String, dynamic> l) {
  final command = _map(_map(l['onTap'])['innertubeCommand']);
  final endpoint = _map(command['reelWatchEndpoint']);
  var id = '${endpoint['videoId'] ?? ''}';
  if (!_isVideoId(id)) {
    final entity = '${l['entityId'] ?? ''}';
    final dash = entity.lastIndexOf('-');
    id = dash < 0 ? '' : entity.substring(dash + 1);
  }
  if (!_isVideoId(id)) return null;
  final overlay = _map(l['overlayMetadata']);
  var title = _text(overlay['primaryText']);
  final accessibility = '${l['accessibilityText'] ?? ''}'.trim();
  if (title.isEmpty) {
    // «<title>, 2.7 million views - play Short».
    title = accessibility.replaceFirst(RegExp(r',\s*[^,]*views\s*-\s*play Short\s*$', caseSensitive: false), '').trim();
  }
  if (title.isEmpty) return null;
  final views = _text(overlay['secondaryText']);
  // The frame, in the clip's own aspect when YouTube says so.
  final thumbnail = _map(endpoint['thumbnail']);
  final frames = thumbnail['thumbnails'];
  final frame = frames is List && frames.isNotEmpty ? _map(frames.first) : const <String, dynamic>{};
  final own = thumbnail['isOriginalAspectRatio'] == true;
  return ReelSearchHit(
    id: id,
    title: title,
    viewCount: parseReelViewCount(views.isNotEmpty ? views : accessibility.substring(math.min(title.length, accessibility.length))),
    short: true,
    frameWidth: own ? _int(frame['width']) : 0,
    frameHeight: own ? _int(frame['height']) : 0,
  );
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

ReelSearchHit? _hitFromReelItem(Map<String, dynamic> r) {
  final id = '${r['videoId'] ?? ''}';
  if (!_isVideoId(id)) return null;
  final title = _text(r['headline']);
  if (title.isEmpty) return null;
  return ReelSearchHit(id: id, title: title, viewCount: parseReelViewCount(_text(r['viewCountText'])), short: true);
}

/// YouTube's search, asked at the innertube endpoint as the website does,
/// since youtube_explode's search reads only the regular results and drops
/// the Shorts shelf — which is where the Shorts are. One plain [Dio]; a
/// failed request throws, so the caller decides what that means.
class ReelShortsSearch {
  ReelShortsSearch({Dio? dio}) : _dio = dio ?? _plainDio();

  static const Duration timeout = Duration(seconds: 12);
  static const String endpoint = 'https://www.youtube.com/youtubei/v1/search';
  static const String clientVersion = '2.20250312.04.00';
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  /// The «under 4 minutes» duration filter, as the website sends it.
  static const String shortParams = 'EgIYAQ==';

  final Dio _dio;

  static Dio _plainDio() => Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          responseType: ResponseType.plain,
        ),
      );

  /// The first batch for [query] (short videos only), or — with
  /// [continuation] — the next one.
  Future<ReelSearchAnswer> search(String query, {String? continuation}) async {
    final res = await _dio.post<String>(
      endpoint,
      queryParameters: {'prettyPrint': 'false'},
      data: jsonEncode({
        'context': {
          'client': {'clientName': 'WEB', 'clientVersion': clientVersion, 'hl': 'en', 'gl': 'US'},
        },
        if (continuation == null) 'query': query,
        if (continuation == null) 'params': shortParams,
        if (continuation != null) 'continuation': continuation,
      }),
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': userAgent,
          'X-YouTube-Client-Name': '1',
          'X-YouTube-Client-Version': clientVersion,
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
        },
      ),
    );
    final decoded = jsonDecode(res.data ?? '');
    if (decoded is! Map) throw const FormatException('search answer is not a JSON object');
    return parseReelSearch(Map<String, dynamic>.from(decoded));
  }

  void close() => _dio.close(force: true);
}

/// The hits of one search worth probing for [film], in the order to probe
/// them: only ones that may be a Short (see [ReelSearchHit.mayBeShort]),
/// not shown wider than tall, whose title carries the film's title (see
/// [reelTitleMatch]; a one-word name must be pinned to a film by the
/// title, see [reelPinsFilm]), that are not a fan's clip or noise
/// ([reelIsFanClip], [isFilmNoise]), and that read as the trailer — the
/// title says so, the channel is official, or the channel is not printed
/// (a Short off the shelf), which the probe then tells. Official channels
/// first, then title-tagged hits, then the unknown channels; within each,
/// the ones YouTube shows upright, then the ones it lists as Shorts or
/// whose title says so, then the rest, in YouTube's order; at most
/// [limit]. Ids in [dead] — shorts the feed found unplayable (see
/// [ReelsService.markDead]) — are never offered again. Pure.
List<ReelSearchHit> reelShortCandidates(Iterable<ReelSearchHit> hits, ReelFilm film,
    {int limit = ReelsService.candidatesPerQuery, Set<String> dead = const {}}) {
  final names = film.names;
  final seen = <String>{};
  final fit = hits.where((h) {
    if (!h.mayBeShort || h.landscapeHint) return false;
    if (dead.contains(h.id)) return false;
    if (!seen.add(h.id)) return false;
    final matched = reelTitleMatch(h.title, names);
    if (matched == null) return false;
    if (!matched.contains(' ') && !reelPinsFilm(h.title)) return false;
    if (reelIsFanClip(h.title, author: h.author) || isFilmNoise(h.title, author: h.author)) return false;
    return reelHasOfficialMark(h.title) || reelIsOfficialChannel(h.author) || h.author.trim().isEmpty;
  }).toList();
  int rank(ReelSearchHit h) {
    final standing = reelIsOfficialChannel(h.author) ? 0 : (reelHasOfficialMark(h.title) ? 1 : 2);
    final shape = h.portraitHint ? 0 : (h.short || reelSaysShorts(h.title) ? 1 : 2);
    return standing * 3 + shape;
  }

  return [
    for (var r = 0; r < 9; r++) ...fit.where((h) => rank(h) == r),
  ].take(limit).toList();
}

/// [items] without any whose id is in [seen] or repeated earlier in the list.
/// Ids that pass are added to [seen].
List<Reel> dedupReels(Iterable<Reel> items, Set<String> seen) {
  final out = <Reel>[];
  for (final r in items) {
    if (r.id.isEmpty || seen.contains(r.id)) continue;
    seen.add(r.id);
    out.add(r);
  }
  return out;
}

/// The next title to look at and the lane it came from, following
/// [kReelPagePattern] from [slot] (which is advanced): a slot whose lane is
/// empty is skipped; null when every lane is empty. The lanes are consumed
/// in place, so what is left carries over to the next page in its source
/// order.
({ReelFilm film, ReelLane lane})? drawReelFilm({
  required List<ReelFilm> films,
  required List<ReelFilm> series,
  required List<ReelFilm> anime,
  required List<int> slot,
}) {
  final lanes = {ReelLane.film: films, ReelLane.series: series, ReelLane.anime: anime};
  for (var tries = 0; tries < kReelPagePattern.length; tries++) {
    final lane = kReelPagePattern[slot[0]++ % kReelPagePattern.length];
    final queue = lanes[lane]!;
    if (queue.isNotEmpty) return (film: queue.removeAt(0), lane: lane);
  }
  return null;
}

/// True when [s] carries an Arabic letter.
bool _hasArabic(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);

/// The titles among the catalogue's [items], in order, each keeping its
/// entry: both titles, the year, the poster (the full one first — it is
/// drawn over the whole page — then the card size, then the backdrop),
/// the synopsis (Arabic first) and whether it is a series. [anime] marks
/// the titles as the catalogue's anime, which are searched for their PVs.
/// An entry with no name at all is left out. Pure.
List<ReelFilm> reelFilmsFromCinemana(Iterable<CinemanaItem> items, {bool anime = false}) => [
      for (final i in items)
        if (i.enTitle.trim().isNotEmpty || i.arTitle.trim().isNotEmpty)
          ReelFilm(
            titleEn: i.enTitle.trim(),
            titleAr: i.arTitle.trim(),
            year: i.year.trim().isEmpty ? null : i.year.trim(),
            poster: _firstUrl([i.imgUrl, i.imgMediumUrl, i.backdropUrl]),
            overview: i.arContent.trim().isNotEmpty ? i.arContent.trim() : i.enContent.trim(),
            isSeries: i.isSeries,
            isAnime: anime,
            item: i,
          ),
    ];

String? _firstUrl(List<String?> urls) {
  for (final u in urls) {
    if (u != null && u.trim().isNotEmpty) return u.trim();
  }
  return null;
}

/// [f] over [items], at most [limit] at a time, the answers in [items]'s
/// order.
Future<List<T>> _mapLimited<S, T>(List<S> items, int limit, Future<T> Function(S) f) async {
  final out = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      out[i] = await f(items[i]);
    }
  }

  await Future.wait([for (var k = 0; k < math.min(limit, items.length); k++) worker()]);
  return [for (final v in out) v as T];
}

/// The film feed: for the app's own catalogue — its newest films and its
/// newest series, newest first, interleaved — the official vertical short
/// of each title, found on YouTube and probed, so every reel is upright,
/// 1080p, plays whole and is the title's own trailer (see
/// [reelIsOfficialShort]); a title with no such short is passed over. And
/// a search of the catalogue under the same rule.
///
/// One shared [YoutubeExplode]; every lane is bounded by [laneTimeout], a
/// page by [pageBudget], and a failure comes back as an empty (or `failed`)
/// page rather than an exception, so the pages never have to guard against
/// it. What was found (or not) for a title is remembered for the session,
/// so a page fetched again costs nothing.
class ReelsService {
  ReelsService({
    YoutubeExplode? yt,
    ReelShortsSearch? shorts,
    CinemanaService? cinemana,
    ReelStreamResolver? resolver,
    ReelLetterbox? letterbox,
    TmdbService? tmdb,
  })  : _tmdb = tmdb ?? TmdbService(),
        _yt = yt ?? YoutubeExplode(),
        _shorts = shorts ?? ReelShortsSearch(),
        _cinemanaGiven = cinemana,
        _resolverGiven = resolver,
        _letterbox = letterbox ?? ReelLetterbox();

  /// The trailers the feed is made of — the same source the home page's
  /// «مقاطع وإعلانات» row reads.
  final TmdbService _tmdb;

  /// For the watch page ([video]) only; the searches go through [_shorts].
  final YoutubeExplode _yt;
  final ReelShortsSearch _shorts;
  final CinemanaService? _cinemanaGiven;
  final ReelStreamResolver? _resolverGiven;

  /// The last gate a candidate passes: a 16:9 picture parked between black
  /// bands in the 9:16 canvas plays as a postage stamp on a phone, so it is
  /// not a vertical short whatever its pixel size says.
  final ReelLetterbox _letterbox;

  /// Built on first use, so a service that is never asked costs nothing.
  late final CinemanaService _cinemana = _cinemanaGiven ?? CinemanaService();
  late final ReelStreamResolver _resolver = _resolverGiven ?? ReelStreamResolver.instance;

  final Map<String, Video> _videos = {};

  /// Watch-page fetches under way, so two asks for the same reel's record
  /// (say, two pages built at once) share one request.
  final Map<String, Future<Video?>> _videoInflight = {};

  /// Per film ([ReelFilm.key]): the id of its short, or null when none
  /// qualified; and the searches under way.
  final Map<String, String?> _shortOf = {};
  final Map<String, Future<String?>> _findInflight = {};

  /// The search hit of every short found, by id, for the reel's counts.
  final Map<String, ReelSearchHit> _found = {};

  /// The shorts the feed found unplayable (see [markDead]): never offered
  /// again, however often their title comes round.
  final Set<String> _dead = {};

  static const Duration timeout = Duration(seconds: 12);

  /// A lane's fetch gets this long.
  static const Duration laneTimeout = Duration(seconds: 20);

  /// How long one film's search may run before the page goes on without
  /// it (the search itself runs on and is remembered for the next page).
  static const Duration filmTimeout = Duration(seconds: 30);

  /// How long a page keeps looking before it goes out with what it has.
  static const Duration pageBudget = Duration(seconds: 30);

  /// How many films are searched at once, and how many candidates of one
  /// query are probed at once.
  static const int filmsAtOnce = 3;
  static const int probesAtOnce = 3;

  /// How many of one query's matches are probed, and how many probes one
  /// film may cost across its queries.
  static const int candidatesPerQuery = 5;
  static const int probesPerFilm = 8;

  /// A lane is topped up when fewer titles than this are waiting.
  static const int laneLowWater = 4;

  /// How many catalogue titles each lane asks for at a time.
  static const int filmsPerFetch = 24;
  static const int seriesPerFetch = 12;
  static const int animePerFetch = 12;

  /// How many of the titles the catalogue finds for a query a search looks
  /// for shorts of in one batch.
  static const int searchBatch = 6;

  /// How many of a page's reels are resolved ahead, once it is built.
  static const int prewarmCount = 3;

  void dispose() {
    _yt.close();
    _shorts.close();
    _letterbox.close();
  }

  /// Writes the short [id] off: it turned out not to play at all, so it is
  /// never handed out again, and the title it was found for is forgotten —
  /// the next page searches that title afresh, this time without the dead
  /// short among the candidates (see [reelShortCandidates]).
  void markDead(String id) {
    if (id.isEmpty || !_dead.add(id)) return;
    _found.remove(id);
    _shortOf.removeWhere((_, found) => found == id);
  }

  /// The shorts written off by [markDead]; the feed hands its own list back
  /// in on a new launch.
  @visibleForTesting
  Set<String> get deadShorts => _dead;

  /// What the service remembers per title ([ReelFilm.key]): the id of its
  /// short, null when it found none, absent when it has not looked.
  @visibleForTesting
  Map<String, String?> get shortsFound => _shortOf;

  /// The largest page TMDB will answer for a discover query.
  static const int lastTrailerPage = 500;

  /// One page of the feed: the very trailers the home page's
  /// «مقاطع وإعلانات» row shows, newest release first.
  ///
  /// It used to take a title from the catalogue and search YouTube for a
  /// vertical short of it, which is how clips turned up that had nothing to
  /// do with the film. It now reads TMDB's own list — sorted by release date,
  /// newest first — and each film's own official trailer, the same rows the
  /// trailers section is built from, so the two can never disagree. Nothing
  /// is searched for, so nothing arbitrary can be found.
  ///
  /// Endless: TMDB answers 500 pages of releases, and a page is only the
  /// next handful of them, so swiping never reaches the end.
  ///
  /// Quality is settled per trailer when it plays, not here. A clip of a
  /// minute or less plays from the 1080p pair; a longer one takes the muxed
  /// stream, because YouTube refuses adaptive bytes past about 60 s without a
  /// proof-of-origin token (measured; see [kReelAdaptiveMaxDuration]). Whole
  /// at the muxed picture beats 1080p that stops a minute in.
  Future<ReelsPage> fetchFeed({ReelsPage? after}) async {
    final prev = after?.cursor ?? const ReelsCursor();
    final seen = Set<String>.of(prev.seen);
    // TMDB pages count from 1; the cursor carries where we are.
    var page = prev.filmPage < 1 ? 1 : prev.filmPage;
    var misses = prev.filmMisses;
    final found = <Reel>[];
    var threw = false;

    while (found.length < kReelsPageSize &&
        page <= lastTrailerPage &&
        misses < ReelsCursor.laneMisses) {
      final List<MovieTrailer> batch;
      try {
        batch = await _tmdb.feedPage(page, want: kReelsPageSize * 2).timeout(laneTimeout);
      } catch (_) {
        threw = true;
        break;
      }
      page++;
      var added = 0;
      for (final t in batch) {
        final id = t.youtubeId;
        if (id == null || id.isEmpty || _dead.contains(id) || !seen.add(id)) continue;
        found.add(Reel.fromTrailer(t));
        added++;
        if (found.length >= kReelsPageSize) break;
      }
      // A page of releases with no trailer among them is not the end of the
      // feed; a run of them is.
      misses = added == 0 ? misses + 1 : 0;
    }

    return ReelsPage(
      items: found,
      hasMore: !threw && page <= lastTrailerPage && misses < ReelsCursor.laneMisses,
      failed: threw && found.isEmpty,
      cursor: ReelsCursor(seen: seen, filmPage: page, filmMisses: misses),
    );
  }

  /// [fetch] bounded by [laneTimeout]; null when it failed or timed out.
  Future<T?> _lane<T extends Object>(Future<T> Function() fetch) async {
    try {
      return await fetch().timeout(laneTimeout);
    } catch (_) {
      return null;
    }
  }

  /// The id of [film]'s vertical short, or null when none qualifies —
  /// remembered for the session either way, unless the search was cut
  /// short by YouTube refusing the probes (see
  /// [ReelStreamResolver.throttled]), in which case the film is asked
  /// about again next time. Concurrent asks share one search. Bounded by
  /// [filmTimeout]: past it the answer is null for now, while the search
  /// runs on and is remembered once done.
  Future<String?> _shortFor(ReelFilm film) async {
    final key = film.key;
    if (_shortOf.containsKey(key)) return _shortOf[key];
    final running = _findInflight.putIfAbsent(key, () {
      final f = _findShort(film).then((answer) {
        if (answer.settled) _shortOf[key] = answer.id;
        return answer.id;
      });
      f.whenComplete(() => _findInflight.remove(key)).ignore();
      return f;
    });
    try {
      return await running.timeout(filmTimeout);
    } catch (_) {
      return null;
    }
  }

  /// Runs [reelShortQueries] for [film] in order, probing each query's
  /// candidates ([reelShortCandidates]) [probesAtOnce] at a time, and
  /// answers the first candidate — in the candidates' order — whose probe
  /// qualifies ([ReelProbe.qualifies]: upright, 1080p, whole) and that is
  /// the title's own trailer ([reelIsOfficialShort]) once its channel is
  /// known — off the search, else off the probe, for a Short whose channel
  /// the search did not print; null when none did within [probesPerFilm]
  /// probes. A candidate that clears both is still dropped when its
  /// portrait thumbnail turns out to be letterboxed ([ReelLetterbox]) — it
  /// counts against the film's probe budget like any other tried hit. A
  /// short written off by [markDead] is never a candidate. Not `settled` when the probes were refused (the resolver
  /// throttled) before a short was found: nothing was learnt about the
  /// film then.
  Future<({String? id, bool settled})> _findShort(ReelFilm film) async {
    final tried = <String>{};
    var probes = 0;
    for (final q in reelShortQueries(film)) {
      if (probes >= probesPerFilm || _resolver.throttled) break;
      final hits = await _searchShorts(q);
      final candidates = reelShortCandidates(hits, film, limit: candidatesPerQuery, dead: _dead)
          .where((h) => tried.add(h.id))
          .take(probesPerFilm - probes)
          .toList();
      if (candidates.isEmpty) continue;
      probes += candidates.length;
      final probed = await _mapLimited(candidates, probesAtOnce, (h) => _resolver.probe(h.id));
      for (var i = 0; i < candidates.length; i++) {
        final p = probed[i];
        if (p == null || !p.qualifies) continue;
        final h = candidates[i].withChannel(p.author);
        if (!reelIsOfficialShort(h.title, author: h.author)) continue;
        // Last, because it costs a thumbnail fetch: a hit that was never
        // going to be accepted must not pay for one. A null answer — the
        // thumbnail did not arrive or would not decode — accepts: the
        // detector not knowing is no evidence against the short, and
        // rejecting on it would empty the feed whenever i.ytimg.com hiccups.
        if (await _letterbox.isLetterboxed(h.id) ?? false) continue;
        _found[h.id] = h;
        return (id: h.id, settled: true);
      }
    }
    return (id: null, settled: !_resolver.throttled);
  }

  /// YouTube's short videos for [q]; empty when the search failed.
  Future<List<ReelSearchHit>> _searchShorts(String q) async {
    try {
      return (await _shorts.search(q).timeout(timeout)).hits;
    } catch (_) {
      return const [];
    }
  }

  /// [film]'s reel for its short [id]: the film's title and year, its
  /// poster and catalogue entry, the lane it was drawn from, the short's
  /// length as probed (else as printed), and its channel and view count
  /// when the search — or the probe — carried them.
  Reel _reelOf(ReelFilm film, String id, ReelLane lane) {
    final h = _found[id];
    final author = h?.author ?? '';
    return Reel(
      lane: lane,
      id: id,
      title: reelTitleWithYear(film.title, film.year),
      author: author.isNotEmpty ? author : kReelTrailerAuthor,
      channelId: null,
      description: film.overview,
      duration: _resolver.cachedProbe(id)?.duration ?? h?.duration,
      viewCount: h?.viewCount,
      likeCount: null,
      uploadDate: null,
      kind: Reel.kindTrailer,
      thumbnail: film.poster,
      catalogItem: film.item,
    );
  }

  /// The search, under the feed's rule: the titles the app's own catalogue
  /// finds for [query] (films and series, by relevance), looked up
  /// [searchBatch] at a time — [filmsAtOnce] together — for their official
  /// vertical shorts until a batch yields one or the titles run out; hand
  /// the returned page back as [after] for the next batch of the same
  /// query. A new query starts over. A title without a qualifying official
  /// short is left out; never a clip that is not upright, 1080p and whole,
  /// and never one that is not the catalogue's own film or series.
  Future<ReelsPage> search(String query, {ReelsPage? after}) async {
    final q = query.trim();
    if (q.isEmpty) return ReelsPage.empty;
    final prev = after?.cursor;
    final continuing = prev != null && prev.query == q;
    final seen = continuing ? Set<String>.of(prev.seen) : <String>{};
    var searched = continuing ? prev.filmsSearched : 0;
    var matched = continuing ? prev.filmsMatched : 0;

    List<ReelFilm> pending;
    var threw = false;
    if (continuing) {
      pending = List<ReelFilm>.of(prev.films);
    } else {
      final found = await _lane(() => _cinemana.search(q));
      threw = found == null;
      pending = reelFilmsFromCinemana(found ?? const []);
    }

    final items = <Reel>[];
    final clock = Stopwatch()..start();
    while (items.isEmpty && pending.isNotEmpty && clock.elapsed < pageBudget && !_resolver.throttled) {
      final batch = pending.take(searchBatch).toList();
      pending = pending.skip(searchBatch).toList();
      final ids = await _mapLimited(batch, filmsAtOnce, _shortFor);
      for (var i = 0; i < batch.length; i++) {
        searched++;
        final id = ids[i];
        if (id == null) continue;
        matched++;
        // A search hit's lane is what the catalogue entry says it is; the
        // search does not draw from the feed's lanes.
        if (seen.add(id)) {
          items.add(_reelOf(batch[i], id, batch[i].isSeries ? ReelLane.series : ReelLane.film));
        }
      }
    }

    // Nothing to show because the catalogue could not be reached, or
    // because YouTube is refusing the probes for now: a failure, so the
    // page offers a retry — and the cursor forgets the query, so the retry
    // asks the catalogue again.
    final failed = items.isEmpty && (threw || _resolver.throttled);
    if (items.isNotEmpty) unawaited(_resolver.prewarm(items.take(prewarmCount).map((r) => r.id)));
    return ReelsPage(
      items: items,
      hasMore: failed || pending.isNotEmpty,
      failed: failed,
      cursor: ReelsCursor(
        seen: seen,
        films: pending,
        filmsSearched: searched,
        filmsMatched: matched,
        query: threw ? null : q,
      ),
    );
  }

  /// The full video record (with like count) for [id]; null when it could
  /// not be fetched. Cached for the session.
  Future<Video?> video(String id) {
    final hit = _videos[id];
    if (hit != null) return Future.value(hit);
    return _videoInflight.putIfAbsent(id, () => _fetchVideo(id))
      ..whenComplete(() => _videoInflight.remove(id));
  }

  Future<Video?> _fetchVideo(String id) async {
    try {
      final v = await _yt.videos.get(id).timeout(timeout);
      _videos[id] = v;
      return v;
    } catch (_) {
      return null;
    }
  }
}
