/// Where the app looks for updates. Change [versionUrl] to your own site
/// (Netlify or otherwise) - it must be https, and every APK link inside
/// version.json must be on one of [allowedHosts].
class UpdateConfig {
  UpdateConfig._();

  /// The manifest the app reads on start. Served with
  /// `Cache-Control: no-cache, no-store, must-revalidate` (see
  /// netlify/public/_headers) so a new release is seen at once.
  static const String versionUrl = 'https://cineball.netlify.app/download/version.json';

  /// Hosts an APK may be downloaded from. Anything else is refused, even if
  /// version.json says so.
  static const List<String> allowedHosts = ['cineball.netlify.app'];

  /// The app's Android package; an APK for any other package is not ours.
  static const String packageName = 'com.antigravity.yt.youtube_downloader';
}
