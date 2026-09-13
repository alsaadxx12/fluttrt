/// What version.json says about the latest release.
class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final bool forceUpdate;
  final int minSupportedVersion;
  final String notes;

  /// Hex SHA-256 of the APK; when present the download is verified against
  /// it before anything is installed.
  final String? sha256;

  /// Lets the server switch update prompts off entirely.
  final bool updateEnabled;

  /// Bytes, when the server says (shown on the prompt).
  final int? sizeBytes;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.forceUpdate = false,
    this.minSupportedVersion = 0,
    this.notes = '',
    this.sha256,
    this.updateEnabled = true,
    this.sizeBytes,
  });

  /// Throws [FormatException] on anything that is not a usable manifest.
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    int intOf(Object? v, {int? fallback}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      final parsed = int.tryParse('${v ?? ''}'.trim());
      if (parsed != null) return parsed;
      if (fallback != null) return fallback;
      throw FormatException('missing or invalid number: $v');
    }

    bool boolOf(Object? v, bool fallback) {
      if (v is bool) return v;
      final s = '${v ?? ''}'.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
      return fallback;
    }

    final apk = '${json['apkUrl'] ?? ''}'.trim();
    if (apk.isEmpty) throw const FormatException('apkUrl missing');
    final sha = '${json['sha256'] ?? ''}'.trim().toLowerCase();
    if (sha.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw const FormatException('sha256 must be 64 hex characters');
    }
    return AppUpdateInfo(
      versionCode: intOf(json['versionCode']),
      versionName: '${json['versionName'] ?? ''}'.trim(),
      apkUrl: apk,
      forceUpdate: boolOf(json['forceUpdate'], false),
      minSupportedVersion: intOf(json['minSupportedVersion'], fallback: 0),
      notes: '${json['notes'] ?? ''}'.trim(),
      sha256: sha.isEmpty ? null : sha,
      updateEnabled: boolOf(json['updateEnabled'], true),
      sizeBytes: json['sizeBytes'] == null ? null : intOf(json['sizeBytes'], fallback: 0),
    );
  }

  /// A newer build than [currentCode] that the server wants shown.
  bool isNewerThan(int currentCode) => updateEnabled && versionCode > currentCode;

  /// The user may not go on with [currentCode] installed.
  bool mustUpdate(int currentCode) => forceUpdate || currentCode < minSupportedVersion;

  /// The APK link is https and on one of [allowedHosts].
  bool apkUrlAllowed(List<String> allowedHosts) {
    final uri = Uri.tryParse(apkUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return allowedHosts.any((h) => host == h.toLowerCase());
  }
}
