import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/core/network/http_cache.dart';

/// A fake adapter: succeeds N times then fails, so we can test the offline
/// fallback path of HttpCache. [body] can be swapped between calls to tell a
/// fresh network answer from a cached one.
class _FakeAdapter implements HttpClientAdapter {
  int calls = 0;
  bool failNow = false;
  String body;
  _FakeAdapter(this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (failNow) throw DioException(requestOptions: options, error: 'offline');
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The clock handed to HttpCache. It only ever moves forward, across tests
/// too, so a markStale() watermark set by one test never outruns the entries
/// stored by the next (the cache is a singleton shared by every test).
int _now = DateTime.now().millisecondsSinceEpoch;
void _advance(Duration d) => _now += d.inMilliseconds;

/// A Dio on the fake network — for the test's own calls and, through
/// [HttpCache.newDio], for the cache's background revalidations.
Dio _dioOn(_FakeAdapter fake) {
  HttpCache.instance.newDio = () => Dio()..httpClientAdapter = fake;
  return createDio(BaseOptions(baseUrl: 'https://example.com'))..httpClientAdapter = fake;
}

/// Polls until [done] holds, so a test can wait for a background refresh.
Future<void> _settle(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('background request never completed');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Uri _uri(String path) => Uri.parse('https://example.com$path');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => HttpCache.instance.now = () => _now);
  tearDown(() {
    HttpCache.instance.now = () => DateTime.now().millisecondsSinceEpoch;
    HttpCache.instance.newDio = Dio.new;
  });

  test('cache forwards responses and never hangs', () async {
    final dio = createDio(BaseOptions(baseUrl: 'https://example.com'));
    final fake = _FakeAdapter('{"results":[{"id":1}]}');
    dio.httpClientAdapter = fake;

    final r = await dio.get<Map<String, dynamic>>('/discover').timeout(const Duration(seconds: 5));
    expect(r.statusCode, 200);
    expect((r.data?['results'] as List).length, 1);
    expect(fake.calls, 1);
  });

  test('serves cached body when the network fails', () async {
    final dio = createDio(BaseOptions(baseUrl: 'https://example.com'));
    final fake = _FakeAdapter('{"ok":true}');
    dio.httpClientAdapter = fake;

    // First call populates the in-memory cache.
    await dio.get<Map<String, dynamic>>('/x?p=99').timeout(const Duration(seconds: 5));
    // Now the network fails; the cached body should come back.
    fake.failNow = true;
    final r = await dio.get<Map<String, dynamic>>('/x?p=99').timeout(const Duration(seconds: 5));
    expect(r.data?['ok'], true);
  });

  test('a hit younger than 10 min is served from cache without a network call', () async {
    final fake = _FakeAdapter('{"v":1}');
    final dio = _dioOn(fake);
    await dio.get<Map<String, dynamic>>('/fresh');
    expect(fake.calls, 1);

    _advance(const Duration(minutes: 9));
    final r = await dio.get<Map<String, dynamic>>('/fresh');
    expect(r.data?['v'], 1);
    expect(r.headers.value('x-from-cache'), '1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.calls, 1);
  });

  test('a hit older than 10 min but younger than 24 h is served from cache and revalidated once', () async {
    final fake = _FakeAdapter('{"v":1}');
    final dio = _dioOn(fake);
    await dio.get<Map<String, dynamic>>('/stale');
    fake.body = '{"v":2}';

    _advance(const Duration(minutes: 11));
    // Two hits while stale: both get the old body at once ...
    final hits = await Future.wait([
      dio.get<Map<String, dynamic>>('/stale'),
      dio.get<Map<String, dynamic>>('/stale'),
    ]);
    for (final r in hits) {
      expect(r.data?['v'], 1);
      expect(r.headers.value('x-from-cache'), '1');
    }
    // ... and exactly one background request replaces the entry.
    await _settle(() => HttpCache.instance.storedAt(_uri('/stale')) == _now);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.calls, 2);

    final r = await dio.get<Map<String, dynamic>>('/stale');
    expect(r.data?['v'], 2);
    expect(r.headers.value('x-from-cache'), '1');
    expect(fake.calls, 2);
  });

  test('after markStale() the next request goes to the network', () async {
    final fake = _FakeAdapter('{"v":1}');
    final dio = _dioOn(fake);
    await dio.get<Map<String, dynamic>>('/refresh');
    fake.body = '{"v":2}';

    _advance(const Duration(seconds: 1));
    HttpCache.instance.markStale();
    final r = await dio.get<Map<String, dynamic>>('/refresh');
    expect(fake.calls, 2);
    expect(r.data?['v'], 2);
    expect(r.headers.value('x-from-cache'), isNull);

    // The fresh answer is cached again for the hits that follow.
    _advance(const Duration(seconds: 1));
    final again = await dio.get<Map<String, dynamic>>('/refresh');
    expect(again.data?['v'], 2);
    expect(again.headers.value('x-from-cache'), '1');
    expect(fake.calls, 2);
  });

  test('a cached answer is not stored again: its timestamp does not change on a hit', () async {
    final fake = _FakeAdapter('{"v":1}');
    final dio = _dioOn(fake);
    await dio.get<Map<String, dynamic>>('/keep');
    final storedAt = HttpCache.instance.storedAt(_uri('/keep'));
    expect(storedAt, _now);

    _advance(const Duration(minutes: 9));
    await dio.get<Map<String, dynamic>>('/keep');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(HttpCache.instance.storedAt(_uri('/keep')), storedAt);
    expect(fake.calls, 1);

    // Had the hit reset the age, the entry would still count as fresh here
    // and nothing would revalidate it.
    _advance(const Duration(minutes: 2));
    await dio.get<Map<String, dynamic>>('/keep');
    await _settle(() => HttpCache.instance.storedAt(_uri('/keep')) == _now);
    expect(fake.calls, 2);
  });

  test('an entry older than 24 h goes to the network, and stays the offline fallback', () async {
    final fake = _FakeAdapter('{"v":1}');
    final dio = _dioOn(fake);
    await dio.get<Map<String, dynamic>>('/old');
    fake.body = '{"v":2}';

    _advance(const Duration(hours: 25));
    final r = await dio.get<Map<String, dynamic>>('/old');
    expect(fake.calls, 2);
    expect(r.data?['v'], 2);
    expect(r.headers.value('x-from-cache'), isNull);

    _advance(const Duration(hours: 25));
    fake.failNow = true;
    final offline = await dio.get<Map<String, dynamic>>('/old');
    expect(fake.calls, 3);
    expect(offline.data?['v'], 2);
    expect(offline.headers.value('x-from-cache'), '1');
  });

  test('a failed background revalidation keeps the cached copy and is retried on a later hit', () async {
    final fake = _FakeAdapter('{"v":1}');
    final dio = _dioOn(fake);
    await dio.get<Map<String, dynamic>>('/flaky');
    final storedAt = HttpCache.instance.storedAt(_uri('/flaky'));

    _advance(const Duration(minutes: 11));
    fake.failNow = true;
    final r = await dio.get<Map<String, dynamic>>('/flaky');
    expect(r.data?['v'], 1);
    await _settle(() => fake.calls == 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(HttpCache.instance.storedAt(_uri('/flaky')), storedAt);

    fake.failNow = false;
    fake.body = '{"v":2}';
    final r2 = await dio.get<Map<String, dynamic>>('/flaky');
    expect(r2.data?['v'], 1);
    await _settle(() => HttpCache.instance.storedAt(_uri('/flaky')) == _now);
    expect(fake.calls, 3);
  });
}
