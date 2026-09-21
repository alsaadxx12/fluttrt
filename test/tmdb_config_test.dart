import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/trailers/tmdb_config.dart';

void main() {
  test('TMDB is always configured, even with no --dart-define and no asset', () {
    // This test runs with no TMDB_TOKEN define and no Flutter asset bundle,
    // so it proves the baked-in fallback keeps the trailers section enabled.
    expect(TmdbConfig.isConfigured, isTrue);
    expect(TmdbConfig.bearerToken.startsWith('eyJ'), isTrue);
    expect(TmdbConfig.bearerToken.length, greaterThan(100));
  });
}
