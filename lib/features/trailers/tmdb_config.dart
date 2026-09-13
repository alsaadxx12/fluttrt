/// The Movie Database (TMDB) access.
///
/// TMDB is an official, free API. Get a key at
/// https://www.themoviedb.org/settings/api (a v4 "API Read Access Token", the
/// long one that starts with `eyJ...`), then paste it below. Until it is set,
/// the trailers section stays hidden rather than showing an error.
class TmdbConfig {
  TmdbConfig._();

  /// The v4 bearer token ("API Read Access Token"). Leave empty to disable.
  static const String bearerToken = String.fromEnvironment('TMDB_TOKEN', defaultValue: '');

  static bool get isConfigured => bearerToken.isNotEmpty;

  static const String apiBase = 'https://api.themoviedb.org/3';

  /// TMDB serves images from a separate CDN; the path from the API is appended
  /// to a size folder. w780 is a good balance for a phone backdrop.
  static String backdrop(String path, {String size = 'w780'}) => 'https://image.tmdb.org/t/p/$size$path';
  static String poster(String path, {String size = 'w500'}) => 'https://image.tmdb.org/t/p/$size$path';
}
