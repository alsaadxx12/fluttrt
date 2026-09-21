/// One entry from MBC Shahid's public catalogue: a live channel, a show, a
/// series or a movie. Only public metadata is kept - playback always happens on
/// Shahid's own page, with Shahid's own player, ads and sign-in.
class ShahidItem {
  final int id;
  final String title;

  /// LIVESTREAM, SHOW, SERIES, MOVIE ...
  final String productType;

  /// The official Shahid page for this item.
  final String pageUrl;

  final String? posterTemplate;
  final String? landscapeTemplate;
  final String? logoTemplate;

  /// Shahid's branded 16:9 channel tile (logo on a coloured background).
  /// The bare logo JPEG has its black background baked in; this does not.
  final String? thumbnailTemplate;

  /// Shahid offers it free to everyone (AVOD, ad-supported). Anything else
  /// (SVOD / BROWSE_ONLY) needs a Shahid VIP subscription on their side.
  final bool isFree;

  final List<String> genres;

  /// Resolved HLS address for a live channel (free, unencrypted ones only).
  final String? streamUrl;

  const ShahidItem({
    required this.id,
    required this.title,
    required this.productType,
    required this.pageUrl,
    this.posterTemplate,
    this.landscapeTemplate,
    this.logoTemplate,
    this.thumbnailTemplate,
    this.isFree = false,
    this.genres = const [],
    this.streamUrl,
  });

  ShahidItem copyWith({String? streamUrl}) => ShahidItem(
        id: id,
        title: title,
        productType: productType,
        pageUrl: pageUrl,
        posterTemplate: posterTemplate,
        landscapeTemplate: landscapeTemplate,
        logoTemplate: logoTemplate,
        thumbnailTemplate: thumbnailTemplate,
        isFree: isFree,
        genres: genres,
        streamUrl: streamUrl ?? this.streamUrl,
      );

  bool get isLive => productType == 'LIVESTREAM';

  /// Shahid serves every image from a template with {width}/{height}
  /// placeholders and resizes it server-side, so a card downloads a few KB
  /// instead of the original artwork.
  static String? sized(String? template, int width, int height) {
    if (template == null || template.isEmpty) return null;
    return template
        .replaceAll('{width}', '$width')
        .replaceAll('{height}', '$height')
        .replaceAll('{croppingPoint}', 'mc');
  }

  String? posterUrl(int width, int height) =>
      sized(posterTemplate ?? landscapeTemplate, width, height);

  String? landscapeUrl(int width, int height) =>
      sized(landscapeTemplate ?? posterTemplate, width, height);

  /// The channel's branded tile at exactly 16:9, so the server's resize
  /// crops nothing.
  String? tileUrl(int width) =>
      sized(thumbnailTemplate, width, (width * 9 / 16).round());

  /// Channel logo at its own proportions. Asking for a fixed box makes the
  /// image server centre-crop the logo (they are ~2.7:1), so only the width
  /// is sent and the height follows the artwork.
  String? logoUrl(int width) {
    final t = logoTemplate ?? landscapeTemplate;
    if (t == null || t.isEmpty) return null;
    return t
        .replaceAll(RegExp(r'height=\{height\}&?'), '')
        .replaceAll(RegExp(r'&?croppingPoint=\{croppingPoint\}'), '')
        .replaceAll('{width}', '$width');
  }

  factory ShahidItem.fromJson(Map<String, dynamic> json) {
    final image = json['image'] is Map ? json['image'] as Map : const {};
    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    final plans = (json['pricingPlans'] as List? ?? const [])
        .whereType<Map>()
        .map((p) => p['type']?.toString() ?? '')
        .toSet();

    final genres = (json['genres'] as List? ?? const [])
        .whereType<Map>()
        .map((g) => (g['title']?.toString() ?? '').trim())
        .where((g) => g.isNotEmpty)
        .toList();

    final productUrl = json['productUrl'] is Map ? json['productUrl'] as Map : const {};

    return ShahidItem(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      title: json['title']?.toString() ?? '',
      productType: json['productType']?.toString() ?? '',
      pageUrl: productUrl['url']?.toString() ?? '',
      posterTemplate: str(image['posterClean']) ?? str(image['posterImage']),
      landscapeTemplate: str(image['landscapeClean']) ?? str(image['thumbnailImage']),
      logoTemplate: str(json['logoTitleImage']),
      thumbnailTemplate: str(image['thumbnailImage']),
      isFree: plans.contains('AVOD'),
      genres: genres,
    );
  }
}
