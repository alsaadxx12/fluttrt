import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/casting/services/source_cache.dart';

/// A CDN that counts what it is asked for and can be throttled.
class CountingSource {
  CountingSource(int size) : bytes = Uint8List.fromList(List<int>.generate(size, (i) => (i * 7) % 251));

  final Uint8List bytes;
  final List<(int, int)> asked = <(int, int)>[];
  int failNext = 0;

  Future<Uint8List> fetch(int from, int to) async {
    asked.add((from, to));
    if (failNext > 0) {
      failNext--;
      throw const HttpException('link dropped');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return Uint8List.sublistView(bytes, from, to + 1);
  }
}

void main() {
  late Directory dir;
  const url = 'https://cdn.example.com/films/one.mp4?Signature=abc';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cineball_cache_test_');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('a read is answered from the file the second time round', () async {
    final cdn = CountingSource(3 * SourceCache.chunk + 1000);
    final cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    addTearDown(cache.close);

    final first = await cache.read(100, 5000, cdn.fetch);
    expect(first, cdn.bytes.sublist(100, 5001));
    expect(cdn.asked, hasLength(1));
    // Whole chunks are fetched, whatever was asked for.
    expect(cdn.asked.single, (0, SourceCache.chunk - 1));

    final again = await cache.read(200, 4000, cdn.fetch);
    expect(again, cdn.bytes.sublist(200, 4001));
    expect(cdn.asked, hasLength(1), reason: 'the second read never left the phone');
  });

  test('a read across chunks fetches only the ones missing, as one run', () async {
    final cdn = CountingSource(4 * SourceCache.chunk);
    final cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    addTearDown(cache.close);

    await cache.read(0, 10, cdn.fetch); // chunk 0
    cdn.asked.clear();

    const from = SourceCache.chunk ~/ 2;
    const to = 3 * SourceCache.chunk + 5;
    final bytes = await cache.read(from, to, cdn.fetch);
    expect(bytes, cdn.bytes.sublist(from, to + 1));
    expect(cdn.asked, [(SourceCache.chunk, 4 * SourceCache.chunk - 1)],
        reason: 'chunks 1 to 3 in one request; chunk 0 was here');
  });

  test('the last chunk is clamped to the end of the film', () async {
    final cdn = CountingSource(SourceCache.chunk + 777);
    final cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    addTearDown(cache.close);

    final tail = await cache.read(SourceCache.chunk + 700, cdn.bytes.length - 1, cdn.fetch);
    expect(tail, cdn.bytes.sublist(SourceCache.chunk + 700));
    expect(cdn.asked.single, (SourceCache.chunk, cdn.bytes.length - 1));
    expect(cache.isComplete, isFalse);
    expect(cache.fetchedBytes, 777);
  });

  test('what was fetched is still there when the cache is opened again', () async {
    final cdn = CountingSource(2 * SourceCache.chunk);
    var cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    await cache.read(0, 10, cdn.fetch);
    await cache.close();

    // Another visit, another signature on the url, the same film.
    cache = (await SourceCache.open(dir, url.replaceAll('abc', 'xyz'), cdn.bytes.length))!;
    addTearDown(cache.close);
    cdn.asked.clear();

    final bytes = await cache.read(5, 50, cdn.fetch);
    expect(bytes, cdn.bytes.sublist(5, 51));
    expect(cdn.asked, isEmpty, reason: 'no internet needed for a second viewing');
    expect(cache.fetchedBytes, SourceCache.chunk);
  });

  test('a film of another length under the same address starts over', () async {
    final cdn = CountingSource(2 * SourceCache.chunk);
    var cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    await cache.read(0, 10, cdn.fetch);
    await cache.close();

    cache = (await SourceCache.open(dir, url, cdn.bytes.length + 1))!;
    addTearDown(cache.close);
    expect(cache.fetchedBytes, 0);
  });

  test('the prefetch brings the rest of the film in on its own', () async {
    final cdn = CountingSource(6 * SourceCache.chunk);
    final cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    addTearDown(cache.close);

    // The set reads from the middle; the prefetch starts there and wraps.
    await cache.read(2 * SourceCache.chunk, 2 * SourceCache.chunk + 10, cdn.fetch);
    cache.prefetch(cdn.fetch);

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!cache.isComplete && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(cache.isComplete, isTrue);
    expect(cache.fetchedBytes, cdn.bytes.length);

    // And every byte of it is right.
    final whole = await cache.read(0, cdn.bytes.length - 1, cdn.fetch);
    expect(whole, cdn.bytes);
    // Forward from the set first, one chunk at a time, then round to the
    // start: the chunk just behind the set is the last one in.
    expect(cdn.asked[1].$1, 3 * SourceCache.chunk);
    expect(cdn.asked.last.$1, SourceCache.chunk);
  });

  test('a dropped fetch during prefetch is tried again, not given up on', () async {
    final cdn = CountingSource(3 * SourceCache.chunk);
    final cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    addTearDown(cache.close);

    // The set reads once - the prefetch waits for that - then the link
    // drops the next request.
    await cache.read(0, 10, cdn.fetch);
    cdn.failNext = 1;
    cache.prefetch(cdn.fetch);

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!cache.isComplete && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(cache.isComplete, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('two readers wanting the same stretch make one trip', () async {
    final cdn = CountingSource(SourceCache.chunk);
    final cache = (await SourceCache.open(dir, url, cdn.bytes.length))!;
    addTearDown(cache.close);

    final results = await Future.wait([
      cache.read(0, 100, cdn.fetch),
      cache.read(50, 150, cdn.fetch),
    ]);
    expect(results[0], cdn.bytes.sublist(0, 101));
    expect(results[1], cdn.bytes.sublist(50, 151));
    expect(cdn.asked, hasLength(1));
  });

  test('pruning drops the oldest film once the directory is over budget', () async {
    // The budget is gigabytes; pruning by age is what can be shown here.
    final old = File('${dir.path}/old.part')..writeAsBytesSync(List.filled(10, 1));
    File('${dir.path}/old.map').writeAsBytesSync(List.filled(10, 1));
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
    final fresh = File('${dir.path}/fresh.part')..writeAsBytesSync(List.filled(10, 1));

    await SourceCache.prune(dir);

    expect(old.existsSync(), isFalse);
    expect(File('${dir.path}/old.map').existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });
}
