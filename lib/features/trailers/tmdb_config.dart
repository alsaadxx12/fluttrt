/// The Movie Database (TMDB) access.
///
/// TMDB is an official, free API. The v4 "API Read Access Token" (the long one
/// that starts with `eyJ...`) is a compile-time constant: `--dart-define=
/// TMDB_TOKEN=...` when given, else the baked-in default below. Earlier
/// designs read it from an asset at startup or relied solely on the define,
/// and release builds repeatedly shipped without it, hiding the trailers
/// section for users. A single constant cannot be missing.
class TmdbConfig {
  TmdbConfig._();

  /// The baked-in v4 read token. A free, read-only key that already ships in
  /// every APK, so hardcoding it changes nothing about its exposure. Rotate it
  /// by replacing this string.
  static const String _bundled =
      'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJhYjNhNWE0Mzg5NjAyMDc0NGNhMzRmYTg5Y2M4NDA4NSIsIm5iZiI6MTc4OTMyNDIzNS43MDMsInN1YiI6IjZhYTZlYmNiYjI0ZDk1ODg0YTUzN2Y0MyIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.nhRvvlpoenrGuB5vjVmR_T6jjACOogxF0enQM16mtsU';

  /// The active token: `--dart-define=TMDB_TOKEN=...` when given, else the
  /// baked-in one. A single compile-time constant — no runtime loading, no
  /// asset, nothing the release compiler can tree-shake or a stale cache can
  /// drop — so it is present and non-empty in every build, debug or release.
  static const String bearerToken = String.fromEnvironment('TMDB_TOKEN', defaultValue: _bundled);

  /// Always true: the token above is a non-empty constant.
  static bool get isConfigured => bearerToken.isNotEmpty;

  /// Kept for callers; there is nothing left to load at runtime.
  static Future<void> ensureLoaded() async {}

  static const String apiBase = 'https://api.themoviedb.org/3';

  /// TMDB serves images from a separate CDN; the path from the API is appended
  /// to a size folder. 'original' delivers full uncompressed 4K master images.
  static String backdrop(String path, {String size = 'original'}) => 'https://image.tmdb.org/t/p/$size$path';
  static String poster(String path, {String size = 'original'}) => 'https://image.tmdb.org/t/p/$size$path';
}
