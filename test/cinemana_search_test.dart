import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/data/services/cinemana_service.dart';
import 'package:youtube_downloader/features/cinemana/data/services/krmzi_service.dart';
import 'package:youtube_downloader/features/cinemana/data/services/turkish_serie_service.dart';

/// The extra sources return nothing, so each test is about Cinemana search
/// and the merge, not the live Krmzi/Turkish backends.
class _NoKrmzi implements KrmziService {
  @override
  Future<List<CinemanaItem>> search(String query) async => <CinemanaItem>[];
  @override
  Future<List<CinemanaItem>> fetchMovies({int page = 1}) async => <CinemanaItem>[];
  @override
  Future<List<CinemanaItem>> fetchSeries({int page = 1, bool translated = false}) async => <CinemanaItem>[];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoTurkish implements TurkishSerieService {
  @override
  Future<List<CinemanaItem>> search(String query) async => <CinemanaItem>[];
  @override
  Future<List<CinemanaItem>> fetchCatalog({bool forceRefresh = false}) async => <CinemanaItem>[];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Answers canned JSON and records every path that was asked for.
class _RecordingAdapter implements HttpClientAdapter {
  final List<String> paths = [];
  final Map<String, List<Map<String, dynamic>>> byFragment;
  _RecordingAdapter(this.byFragment);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    for (final entry in byFragment.entries) {
      if (options.path.contains(entry.key)) {
        return ResponseBody.fromString(
          _encode(entry.value),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }
    return ResponseBody.fromString('[]', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  static String _encode(List<Map<String, dynamic>> rows) {
    final parts = rows.map((r) =>
        '{"nb":"${r['nb']}","en_title":"${r['en_title']}","ar_title":"${r['ar_title']}","year":"${r['year']}","kind":"1","stars":"7","categories":[]}');
    return '[${parts.join(',')}]';
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row(String nb, String title) =>
    {'nb': nb, 'en_title': title, 'ar_title': title, 'year': '2024'};

CinemanaService _service(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://cinemana.shabakaty.com/api/android/'))
    ..httpClientAdapter = adapter;
  return CinemanaService(dio: dio, krmziService: _NoKrmzi(), turkishSerieService: _NoTurkish());
}

void main() {
  test('search returns the titles that matched, and nothing else', () async {
    final adapter = _RecordingAdapter({
      'video_title_search': [_row('1', 'The Matrix'), _row('2', 'The Matrix Reloaded')],
      // If this were ever asked for, it would answer with unrelated films:
      // the backend ignores the name and returns its newest titles.
      'video_actor_search': [for (var i = 0; i < 20; i++) _row('90$i', 'Unrelated Film $i')],
    });

    final results = await _service(adapter).search('matrix');

    expect(results, isNotEmpty);
    expect(results.first.enTitle, 'The Matrix', reason: 'the Cinemana match leads the results');
    expect(
      adapter.paths.any((p) => p.contains('video_actor_search')),
      isFalse,
      reason: 'the endpoint that ignores its query is no longer called',
    );
  });

  test('a search that matches nothing returns nothing', () async {
    // No title rows, so Cinemana finds nothing; the extra sources are stubbed
    // empty, so the merged result is empty too.
    final adapter = _RecordingAdapter({});

    final results = await _service(adapter).search('zzzz not a real title 9999');

    expect(results, isEmpty, reason: 'an empty result is the honest answer, not a list of random films');
  });

  test('an empty query never reaches the network', () async {
    final adapter = _RecordingAdapter({});
    expect(await _service(adapter).search('   '), isEmpty);
    expect(adapter.paths, isEmpty);
  });

  test('a failing backend yields no results instead of throwing', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://cinemana.shabakaty.com/api/android/'))
      ..httpClientAdapter = _ThrowingAdapter();
    final service = CinemanaService(dio: dio, krmziService: _NoKrmzi(), turkishSerieService: _NoTurkish());
    // A query no other test caches, so this exercises the failing backend
    // rather than the shared title-search cache.
    expect(await service.search('zq-failing-backend-unique-8712'), isEmpty);
  });

  test('relevance sorting puts closest matches at the beginning', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://cinemana.shabakaty.com/api/android/'))
      ..httpClientAdapter = _RecordingAdapter({});

    final mockTurkish = _TestTurkish([
      const CinemanaItem(
        id: 'ts_serie_esaret',
        arTitle: 'الأسيرة (Esaret)',
        enTitle: 'esaret',
        stars: '8.4',
        year: '2024',
        kind: '2',
        arContent: '',
        enContent: '',
      ),
    ]);

    final mockKrmzi = _TestKrmzi([
      const CinemanaItem(
        id: 'krmzi_ser_10',
        arTitle: 'مسلسل التحول مترجم',
        enTitle: '',
        stars: '8.0',
        year: '2025',
        kind: '2',
        arContent: '',
        enContent: '',
      ),
    ]);

    final service = CinemanaService(
      dio: dio,
      krmziService: mockKrmzi,
      turkishSerieService: mockTurkish,
    );

    final results = await service.search('Esaret');
    expect(results, isNotEmpty);
    expect(results.first.id, 'ts_serie_esaret', reason: 'closest/exact match must appear at the beginning');
    expect(results.first.arTitle, 'الأسيرة (Esaret)');
  });
}

class _TestTurkish implements TurkishSerieService {
  final List<CinemanaItem> items;
  _TestTurkish(this.items);

  @override
  Future<List<CinemanaItem>> search(String query) async => items;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _TestKrmzi implements KrmziService {
  final List<CinemanaItem> items;
  _TestKrmzi(this.items);

  @override
  Future<List<CinemanaItem>> search(String query) async => items;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}
