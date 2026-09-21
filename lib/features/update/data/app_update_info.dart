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

  /// Architecture-specific APKs for ultra-fast downloads (18MB instead of 55MB)
  final String? apkUrlArm64;
  final String? apkUrlArm32;
  final String? sha256Arm64;
  final String? sha256Arm32;

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
    this.apkUrlArm64,
    this.apkUrlArm32,
    this.sha256Arm64,
    this.sha256Arm32,
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

    String? cleanHex(Object? v) {
      final s = '${v ?? ''}'.trim().toLowerCase();
      return (s.isNotEmpty && RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) ? s : null;
    }

    String? cleanUrl(Object? v) {
      final s = '${v ?? ''}'.trim();
      return s.isNotEmpty ? s : null;
    }

    final apk = '${json['apkUrl'] ?? ''}'.trim();
    if (apk.isEmpty) throw const FormatException('apkUrl missing');

    return AppUpdateInfo(
      versionCode: intOf(json['versionCode']),
      versionName: '${json['versionName'] ?? ''}'.trim(),
      apkUrl: apk,
      forceUpdate: boolOf(json['forceUpdate'], false),
      minSupportedVersion: intOf(json['minSupportedVersion'], fallback: 0),
      notes: '${json['notes'] ?? ''}'.trim(),
      sha256: cleanHex(json['sha256']),
      apkUrlArm64: cleanUrl(json['apkUrlArm64']),
      apkUrlArm32: cleanUrl(json['apkUrlArm32']),
      sha256Arm64: cleanHex(json['sha256Arm64']),
      sha256Arm32: cleanHex(json['sha256Arm32']),
      updateEnabled: boolOf(json['updateEnabled'], true),
      sizeBytes: json['sizeBytes'] == null ? null : intOf(json['sizeBytes'], fallback: 0),
    );
  }

  /// A newer build than [currentCode] that the server wants shown.
  bool isNewerThan(int currentCode) => updateEnabled && versionCode > currentCode;

  /// The user may not go on with [currentCode] installed.
  bool mustUpdate(int currentCode) => forceUpdate || currentCode < minSupportedVersion;

  /// The APK link is https and on one of [allowedHosts].
  bool apkUrlAllowed(List<String> allowedHosts) =>
      _hostAllowed(apkUrl, allowedHosts) &&
      (apkUrlArm64 == null || _hostAllowed(apkUrlArm64!, allowedHosts)) &&
      (apkUrlArm32 == null || _hostAllowed(apkUrlArm32!, allowedHosts));

  static bool _hostAllowed(String url, List<String> allowedHosts) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return allowedHosts.any((h) => host == h.toLowerCase());
  }
}
