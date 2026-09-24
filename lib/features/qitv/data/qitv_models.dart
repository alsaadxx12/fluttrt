/// Qi TV (Iraq) catalogue types, read from the public APIs.
library;

int _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
String _str(Object? v) => v == null ? '' : '$v'.trim();

String? _url(Object? v) {
  final s = _str(v);
  return s.startsWith('http') ? s : null;
}

/// A live channel from Qi TV.
class QiChannel {
  final int id;
  final String title;
  final bool active;
  final String streamMpd;
  final String streamM3u8;
  final String? drmPrefix;
  final String? logoUrl;
  final String? category;
  final bool isFree;

  const QiChannel({
    required this.id,
    required this.title,
    this.active = false,
    this.streamMpd = '',
    this.streamM3u8 = '',
    this.drmPrefix,
    this.logoUrl,
    this.category,
    this.isFree = false,
  });

  bool get hasDrm => drmPrefix != null && drmPrefix!.isNotEmpty;

  /// True for a channel the app's own player can show: a clear stream. The
  /// others are Widevine / FairPlay encrypted and play only in Qi TV's app.
  bool get playable => !hasDrm && (streamM3u8.isNotEmpty || streamMpd.isNotEmpty);

  factory QiChannel.fromJson(Map<String, dynamic> j) {
    final plans = j['plans'];
    final isFree =
        plans is List && plans.any((p) => p is Map && (p['title'] == 'Free' || (p['price'] is num && p['price'] == 0)));
    String? logo;
    if (j['logo'] is Map) {
      final l = j['logo'] as Map;
      logo = _str(l['large'] ?? l['medium'] ?? l['small'] ?? l['thumbnail']);
      if (logo.isEmpty) logo = null;
    }
    String? cat;
    if (j['category'] is Map) {
      cat = _str((j['category'] as Map)['title']);
    }
    return QiChannel(
      id: _int(j['id']),
      title: _str(j['title']),
      active: j['active'] == true,
      streamMpd: _str(j['stream_path_android']),
      streamM3u8: _str(j['stream_path_ios']),
      drmPrefix: j['drm_prefix'] is String ? j['drm_prefix'] as String : null,
      logoUrl: logo,
      category: cat,
      isFree: isFree,
    );
  }
}

/// A showcase content item (movie or series from the landing page).
class QiShowcase {
  final int id;
  final String title;
  final String type;
  final String? posterUrl;

  const QiShowcase({
    required this.id,
    required this.title,
    required this.type,
    this.posterUrl,
  });

  bool get isMovie => type == 'MOVIE';
  bool get isSeries => type == 'SERIES';

  factory QiShowcase.fromJson(Map<String, dynamic> j) => QiShowcase(
        id: _int(j['id']),
        title: _str(j['title']),
        type: _str(j['type']),
        posterUrl: _url(j['posterUrl']),
      );
}

/// An exclusive original work from Qi TV.
class QiExclusiveWork {
  final int id;
  final String title;
  final String description;
  final String? posterUrl;
  final String? logoUrl;

  const QiExclusiveWork({
    required this.id,
    required this.title,
    this.description = '',
    this.posterUrl,
    this.logoUrl,
  });

  factory QiExclusiveWork.fromJson(Map<String, dynamic> j) => QiExclusiveWork(
        id: _int(j['id']),
        title: _str(j['title']),
        description: _str(j['description']),
        posterUrl: _url(j['posterUrl']),
        logoUrl: _url(j['logoUrl']),
      );
}

class QiException implements Exception {
  final String message;
  const QiException(this.message);
  @override
  String toString() => message;
}

/// The channels that can play first, then the rest in their own order.
List<QiChannel> sortPlayableFirst(List<QiChannel> channels) {
  final playable = channels.where((c) => c.playable).toList();
  final locked = channels.where((c) => !c.playable).toList();
  return [...playable, ...locked];
}
