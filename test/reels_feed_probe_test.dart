import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/reels/data/reel_stream_resolver.dart';
import 'package:youtube_downloader/features/reels/data/reels_service.dart';

/// Live probe (network): a film search must come back with the official
/// vertical 1080p shorts of the titles the app's own catalogue finds for
/// the query — with their artwork and their catalogue entry — every one of
/// them probed upright, 1080 across and no longer than a minute; and a
/// second batch must not repeat the first. Prints every reel with its
/// measurements so a breakage can be placed. The feed itself is probed in
/// `reels_vertical_probe_test.dart`.
///
/// No TestWidgetsFlutterBinding here: it installs a mock HttpClient that
/// fails every real request.
void main() {
  test('search: the catalogue’s own titles, their official vertical shorts; never a landscape or low clip',
      () async {
    final service = ReelsService();
    final resolver = ReelStreamResolver.instance;
    final sw = Stopwatch()..start();
    final page = await service.search('Dune Part Two');
    final ms = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('--- search "Dune Part Two": ${page.items.length} reels in $ms ms (hasMore=${page.hasMore}, failed=${page.failed})');
    await _check(page, resolver);

    sw.reset();
    final next = await service.search('Dune Part Two', after: page);
    // ignore: avoid_print
    print('--- next batch: ${next.items.length} reels in ${sw.elapsedMilliseconds} ms (hasMore=${next.hasMore})');
    await _check(next, resolver);
    service.dispose();

    expect(page.failed, isFalse, reason: 'the search failed outright');
    expect(page.items, isNotEmpty, reason: 'no vertical short of Dune: Part Two at all');
    expect(page.items.first.thumbnail, isNotNull, reason: 'the film’s own short (with its poster) is not first');
    expect(page.items.every((r) => r.catalogItem != null), isTrue, reason: 'a reel that is not of the catalogue');
    final ids1 = page.items.map((r) => r.id).toSet();
    expect(ids1.length, page.items.length, reason: 'a repeat in the first batch');
    expect(next.items.map((r) => r.id).toSet().intersection(ids1), isEmpty, reason: 'the next batch repeats the first');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _check(ReelsPage page, ReelStreamResolver resolver) async {
  for (final (i, r) in page.items.indexed) {
    final p = await resolver.probe(r.id);
    final measured = p == null
        ? 'could not be probed'
        : '${p.height}×${p.width} ${p.portrait ? 'portrait' : 'landscape'} ${p.duration?.inMilliseconds ?? '?'} ms';
    // ignore: avoid_print
    print('  ${(i + 1).toString().padLeft(2)}. ${r.title}  — ${r.author}  (${r.id})  $measured');
    expect(p, isNotNull, reason: '${r.id} could not be probed');
    expect(p!.portrait, isTrue, reason: '${r.title} (${r.id}) is not upright');
    expect(p.quality, greaterThanOrEqualTo(kReelMinQuality), reason: '${r.title} (${r.id}) is under 1080p');
    expect(p.duration, isNotNull, reason: '${r.id} has no length');
    expect(p.duration!, lessThanOrEqualTo(kReelShortMaxDuration), reason: '${r.title} (${r.id}) is over a minute');
    expect(r.isTrailer, isTrue);
    expect(isFilmNoise(r.title, author: r.author), isFalse, reason: '${r.title} is noise');
  }
}
