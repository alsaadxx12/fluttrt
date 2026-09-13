import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/data/services/sports_service.dart';
import 'package:youtube_downloader/features/sports/data/services/stream_warmup.dart';

/// Counts what actually reaches the network.
class _CountingService extends SportsService {
  int calls = 0;
  final Map<int, StreamInfo?> answers;
  _CountingService(this.answers);

  @override
  Future<StreamInfo?> fetchStream(int streamId) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return answers[streamId];
  }
}

StreamInfo _info(String url) => StreamInfo(ok: true, play: 'hls', url: url, headers: const {});

void main() {
  test('a resolved stream is reused instead of asked for again', () async {
    final service = _CountingService({7: _info('https://cdn.example/live/7.m3u8')});
    final warmup = StreamWarmup(service);

    final first = await warmup.resolve(7);
    expect(first?.url, 'https://cdn.example/live/7.m3u8');
    expect(service.calls, 1);

    // Re-entering the match costs nothing.
    expect(warmup.cached(7)?.url, 'https://cdn.example/live/7.m3u8');
    await warmup.resolve(7);
    expect(service.calls, 1, reason: 'the second visit never reached the network');
  });

  test('two screens asking at once share one request', () async {
    final service = _CountingService({9: _info('https://cdn.example/live/9.m3u8')});
    final warmup = StreamWarmup(service);

    final results = await Future.wait([warmup.resolve(9), warmup.resolve(9)]);
    expect(service.calls, 1, reason: 'the racing caller waits rather than duplicating the work');
    expect(results.where((r) => r != null).length, greaterThanOrEqualTo(1));
  });

  test('a failed resolve is not cached as success', () async {
    final service = _CountingService({4: null});
    final warmup = StreamWarmup(service);

    expect(await warmup.resolve(4), isNull);
    expect(warmup.cached(4), isNull, reason: 'nothing usable to remember');
    await warmup.resolve(4);
    expect(service.calls, 2, reason: 'it is retried rather than stuck on a failure');
  });

  test('prefetch warms only what is not known, and stays bounded', () async {
    final service = _CountingService({
      for (var i = 1; i <= 10; i++) i: _info('https://cdn.example/live/$i.m3u8'),
    });
    final warmup = StreamWarmup(service)..remember(1, _info('https://cdn.example/live/1.m3u8'));

    await warmup.prefetch([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(service.calls, lessThanOrEqualTo(StreamWarmup.prefetchLimit),
        reason: 'speculative work on mobile data stays small');
    expect(service.calls, greaterThan(0));
    expect(warmup.cached(1), isNotNull, reason: 'the one already known was not re-fetched');
  });

  test('a stale entry is dropped rather than handed out', () {
    final warmup = StreamWarmup(_CountingService({}));
    warmup.remember(3, _info('https://cdn.example/live/3.m3u8'));
    expect(warmup.cached(3), isNotNull);

    warmup.clear();
    expect(warmup.cached(3), isNull);
    expect(StreamWarmup.ttl.inMinutes, lessThanOrEqualTo(5),
        reason: 'a signed live url must never be reused for long');
  });

  test('preconnect ignores anything that is not a real address', () async {
    final warmup = StreamWarmup(_CountingService({}));
    // Must complete quietly rather than throw into the caller.
    await warmup.preconnect('');
    await warmup.preconnect('not a url');
    await warmup.preconnect('file:///local/x.m3u8');
  });
}
