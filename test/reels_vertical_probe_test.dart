import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';

/// Live probe (network): the film feed must come back from the app's own
/// catalogue — its newest films, series and anime, the ones its cards show
/// — as official vertical shorts only. Every reel of the first two pages is
/// probed off its YouTube manifest and must be upright (taller than wide),
/// at least 1080 pixels across and no longer than a minute — the rule «لا
/// تجلب أي فيديو إن لم تكن دقته 1080 ويدعم العرض العمودي ويظهر كاملاً» —
/// must carry its catalogue entry (the rule «المحتوى يجب أن يخص الأفلام
/// الموجودة في بطاقات الأفلام والمسلسلات»), and the next page with
/// anything on it must not repeat the first. Under that rule a page can
/// come back empty (the catalogue's newest titles are not all big
/// releases with a vertical trailer), so — as the feed provider does — up
/// to [kHops] further pages are fetched for the second page with reels.
/// Prints every reel with its lane, its channel, its entry and its
/// measurements, each page's count per lane (films, series, anime), how
/// many catalogue titles it looked at and how many of them had an official
/// short, and how long it took.
///
/// No TestWidgetsFlutterBinding here: it installs a mock HttpClient that
/// fails every real request.
void main() {
  test('feed: every reel upright, 1080p, whole and of the catalogue; pages differ', () async {
    final service = ReelsService();
    final resolver = ReelStreamResolver.instance;

    final sw = Stopwatch()..start();
    final first = await service.fetchFeed();
    final firstMs = sw.elapsedMilliseconds;
    final c1 = first.cursor!;
    _dump('page 1', first, ms: firstMs, searched: c1.filmsSearched, matched: c1.filmsMatched);
    await _check(first, resolver);

    var before = first;
    ReelsPage? second;
    for (var hop = 1; hop <= kHops && second == null; hop++) {
      sw.reset();
      final page = await service.fetchFeed(after: before);
      final ms = sw.elapsedMilliseconds;
      final c = page.cursor!;
      final cb = before.cursor!;
      _dump('page ${hop + 1}', page,
          ms: ms, searched: c.filmsSearched - cb.filmsSearched, matched: c.filmsMatched - cb.filmsMatched);
      await _check(page, resolver);
      expect(page.failed, isFalse, reason: 'page ${hop + 1} failed outright');
      if (page.items.isNotEmpty) {
        second = page;
      } else {
        expect(page.hasMore, isTrue, reason: 'the feed ended after page 1');
      }
      before = page;
    }
    service.dispose();

    final c2 = before.cursor!;
    // ignore: avoid_print
    print('cursor at the end: filmPage=${c2.filmPage} seriesPage=${c2.seriesPage} animePage=${c2.animePage} '
        'waiting: films=${c2.films.length} series=${c2.series.length} anime=${c2.anime.length} '
        'misses f/s/a=${c2.filmMisses}/${c2.seriesMisses}/${c2.animeMisses} '
        'catalogue titles searched in all=${c2.filmsSearched} with an official short=${c2.filmsMatched}');

    expect(first.failed, isFalse, reason: 'the first page failed outright');
    expect(first.items, isNotEmpty, reason: 'the first page is empty');
    expect(first.hasMore, isTrue);
    expect(second, isNotNull, reason: 'no second page with reels within $kHops more pages');

    final ids1 = first.items.map((r) => r.id).toList();
    final ids2 = second!.items.map((r) => r.id).toList();
    expect(ids1.toSet().length, ids1.length, reason: 'a repeat on page 1');
    expect(ids2.toSet().length, ids2.length, reason: 'a repeat on the second page');
    expect(ids1.toSet().intersection(ids2.toSet()), isEmpty, reason: 'the second page repeats page 1');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// How many pages past the first are fetched for one with reels on it —
/// what the feed provider skips over in one go.
const int kHops = 3;

void _dump(String label, ReelsPage page, {required int ms, required int searched, required int matched}) {
  int inLane(ReelLane lane) => page.items.where((r) => r.lane == lane).length;
  // ignore: avoid_print
  print('--- $label: ${page.items.length} reels (${inLane(ReelLane.film)} films, '
      '${inLane(ReelLane.series)} series, ${inLane(ReelLane.anime)} anime) in $ms ms; '
      'catalogue titles looked at: $searched, with an official short: $matched; '
      'hasMore=${page.hasMore} failed=${page.failed}');
}

Future<void> _check(ReelsPage page, ReelStreamResolver resolver) async {
  for (final (i, r) in page.items.indexed) {
    final p = await resolver.probe(r.id);
    final measured = p == null
        ? 'could not be probed'
        : '${p.height}×${p.width} ${p.portrait ? 'portrait' : 'landscape'} '
            '${p.duration?.inMilliseconds ?? '?'} ms';
    final item = r.catalogItem;
    final entry = item == null ? '[no catalogue entry]' : '[${r.lane.name} #${item.id} ${item.enTitle}]';
    final channel = r.author == kReelTrailerAuthor ? '(channel unknown)' : r.author;
    // ignore: avoid_print
    print('  ${(i + 1).toString().padLeft(2)}. ${r.title}  — $channel  (${r.id})  $measured  $entry'
        '${r.thumbnail == null ? '  [no poster]' : ''}');
    expect(p, isNotNull, reason: '${r.id} could not be probed');
    expect(p!.portrait, isTrue, reason: '${r.title} (${r.id}) is not upright');
    expect(p.quality, greaterThanOrEqualTo(kReelMinQuality), reason: '${r.title} (${r.id}) is under 1080p');
    expect(p.maxHeight, greaterThanOrEqualTo(kReelMinQuality));
    expect(p.duration, isNotNull, reason: '${r.id} has no length');
    expect(p.duration!, lessThanOrEqualTo(const Duration(seconds: 60)), reason: '${r.title} (${r.id}) is over 60 s');
    expect(r.isTrailer, isTrue, reason: '${r.id} is not a trailer');
    expect(r.title, isNotEmpty);
    expect(item, isNotNull, reason: '${r.title} (${r.id}) is not a title of the catalogue');
    expect(item!.id, isNotEmpty);
    expect(r.isAnime, r.lane == ReelLane.anime, reason: '${r.id} does not agree with its own lane');
    if (r.isAnime) {
      expect(item.isSeries, isTrue, reason: '${r.title} (${r.id}) is of the anime lane, so a series entry');
    }
    expect(r.thumbnail, isNotNull, reason: '${r.title} (${r.id}) has no catalogue poster');
    expect(reelIsFanClip(r.author), isFalse, reason: '${r.title} (${r.id}) comes from a fan channel: ${r.author}');
    expect(isFilmNoise('', author: r.author), isFalse, reason: '${r.title} (${r.id}) comes from a news channel');
  }
}
