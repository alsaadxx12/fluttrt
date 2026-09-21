class CinemanaItem {
  final String id;
  final String arTitle;
  final String enTitle;
  final String stars;
  final String year;
  final String kind; // '1' = Movie, '2' = Series
  final String arContent;
  final String enContent;
  final String? imgUrl;
  final String? imgThumbUrl;
  // 293x439 poster (~25KB) - what cards should load instead of the full
  // 1280x1920 one (up to ~2.4MB), which is only worth it for the hero.
  final String? imgMediumUrl;
  final List<String> categories;
  final List<String> categoriesEn;
  final String likes;
  final String dislikes;
  final String? trailerUrl;
  final String duration;
  final String season;
  final String episodeNummer;
  final String? itemDate;
  final String? mDate;
  final String? backdropUrl;

  const CinemanaItem({
    required this.id,
    required this.arTitle,
    required this.enTitle,
    required this.stars,
    required this.year,
    required this.kind,
    required this.arContent,
    required this.enContent,
    this.imgUrl,
    this.imgThumbUrl,
    this.imgMediumUrl,
    this.backdropUrl,
    this.categories = const [],
    this.categoriesEn = const [],
    this.likes = '0',
    this.dislikes = '0',
    this.trailerUrl,
    this.duration = '',
    this.season = '0',
    this.episodeNummer = '0',
    this.itemDate,
    this.mDate,
  });

  CinemanaItem copyWith({
    String? id,
    String? arTitle,
    String? enTitle,
    String? stars,
    String? year,
    String? kind,
    String? arContent,
    String? enContent,
    String? imgUrl,
    String? imgThumbUrl,
    String? imgMediumUrl,
    String? backdropUrl,
    List<String>? categories,
    List<String>? categoriesEn,
    String? likes,
    String? dislikes,
    String? trailerUrl,
    String? duration,
    String? season,
    String? episodeNummer,
    String? itemDate,
    String? mDate,
  }) {
    return CinemanaItem(
      id: id ?? this.id,
      arTitle: arTitle ?? this.arTitle,
      enTitle: enTitle ?? this.enTitle,
      stars: stars ?? this.stars,
      year: year ?? this.year,
      kind: kind ?? this.kind,
      arContent: arContent ?? this.arContent,
      enContent: enContent ?? this.enContent,
      imgUrl: imgUrl ?? this.imgUrl,
      imgThumbUrl: imgThumbUrl ?? this.imgThumbUrl,
      imgMediumUrl: imgMediumUrl ?? this.imgMediumUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      categories: categories ?? this.categories,
      categoriesEn: categoriesEn ?? this.categoriesEn,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      duration: duration ?? this.duration,
      season: season ?? this.season,
      episodeNummer: episodeNummer ?? this.episodeNummer,
      itemDate: itemDate ?? this.itemDate,
      mDate: mDate ?? this.mDate,
    );
  }

  bool get isSeries => kind == '2';

  String get bestPosterUrl => imgUrl ?? imgThumbUrl ?? '';

  /// Right-sized poster for a card: medium thumb first, full poster only when
  /// there is nothing smaller.
  String get cardImageUrl => imgMediumUrl ?? imgUrl ?? imgThumbUrl ?? '';

  /// The artwork for a card drawn [pixelWidth] physical pixels across.
  ///
  /// The medium poster is 293 px wide: sharp on a phone card, only soft on a
  /// genuinely large card. The full poster (up to ~2.4MB) is used only when
  /// the card is drawn wider than 640 physical pixels, and always when
  /// [hiRes] is set (desktop, where a big screen is viewed from close up and
  /// the card's pixel width under-reads the need). The decode is capped by
  /// memCacheWidth at the call site, so loading the full poster costs no
  /// extra memory.
  String imageForWidth(double pixelWidth, {bool hiRes = false}) =>
      (hiRes || (pixelWidth.isFinite && pixelWidth > 640)) ? (imgUrl ?? cardImageUrl) : cardImageUrl;
  String get bestBackdropUrl => backdropUrl ?? imgUrl ?? imgThumbUrl ?? '';

  /// True when this item carries the given Cinemana genre (matched on the
  /// English category title, which is stable across the API responses).
  bool hasCategoryEn(String enTitle) {
    final needle = enTitle.toLowerCase().trim();
    if (needle.isEmpty) return false;
    return categoriesEn.any((c) => c.toLowerCase().trim() == needle);
  }

  String get displayTitle => arTitle.isNotEmpty ? arTitle : enTitle;

  /// Normalizes titles and search terms across Arabic & English conventions
  static String normalizeTitle(String raw) {
    var t = raw.toLowerCase();
    t = t.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    t = t
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[ؤئ]'), 'ء');
    const stripWords = [
      'فيلم', 'مسلسل', 'مترجم', 'مدبلج', 'اونلاين', 'كامل', 'حصريا',
      'hd', 'season', 'episode'
    ];
    for (final w in stripWords) {
      t = t.replaceAll(w, ' ');
    }
    t = t.replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  factory CinemanaItem.fromJson(Map<String, dynamic> json) {
    List<String> cats = [];
    List<String> catsEn = [];
    if (json['categories'] != null && json['categories'] is List) {
      for (var c in json['categories']) {
        if (c is Map) {
          final title = c['ar_title']?.toString() ?? c['en_title']?.toString() ?? '';
          if (title.isNotEmpty) cats.add(title);
          final enTitle = c['en_title']?.toString() ?? '';
          if (enTitle.isNotEmpty) catsEn.add(enTitle);
        }
      }
    }

    // Banner payloads ship the medium thumb as a bare bucket path.
    String? absolute(String? url) {
      if (url == null || url.isEmpty) return null;
      return url.startsWith('http') ? url : 'https://cnth2.shabakaty.com/$url';
    }

    String? rawObj = json['imgObjUrl']?.toString();
    String? poster = absolute(rawObj);
    final String? medium = absolute(json['imgMediumThumbObjUrl']?.toString());
    if (poster == null || poster.isEmpty) {
      poster = medium;
    }
    if (poster == null || poster.isEmpty) {
      poster = absolute(json['imgThumbObjUrl']?.toString());
    }

    String? backdrop;
    if (rawObj != null && (rawObj.contains('cover') || rawObj.contains('backdrop'))) {
      backdrop = absolute(rawObj);
    } else if (json['coverUrl'] != null && json['coverUrl'].toString().isNotEmpty) {
      backdrop = absolute(json['coverUrl'].toString());
    } else {
      backdrop = poster;
    }

    return CinemanaItem(
      id: json['nb']?.toString() ?? '',
      arTitle: json['ar_title']?.toString() ?? '',
      enTitle: json['en_title']?.toString() ?? '',
      stars: json['stars']?.toString() ?? '0.0',
      year: json['year']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '1',
      arContent: json['ar_content']?.toString() ?? '',
      enContent: json['en_content']?.toString() ?? '',
      imgUrl: poster,
      imgThumbUrl: absolute(json['imgThumbObjUrl']?.toString()) ?? poster,
      imgMediumUrl: medium,
      backdropUrl: backdrop,
      categories: cats,
      categoriesEn: catsEn,
      likes: json['Likes']?.toString() ?? '0',
      dislikes: json['DisLikes']?.toString() ?? '0',
      trailerUrl: json['trailer']?.toString(),
      duration: json['duration']?.toString() ?? '',
      season: json['season']?.toString() ?? '0',
      episodeNummer: json['episodeNummer']?.toString() ?? '0',
      itemDate: json['itemDate']?.toString(),
      mDate: json['mDate']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nb': id,
      'ar_title': arTitle,
      'en_title': enTitle,
      'stars': stars,
      'year': year,
      'kind': kind,
      'ar_content': arContent,
      'en_content': enContent,
      'imgObjUrl': imgUrl,
      'imgThumbObjUrl': imgThumbUrl,
      'imgMediumThumbObjUrl': imgMediumUrl,
      'categories': [
        for (int i = 0; i < categories.length; i++)
          {
            'ar_title': categories[i],
            if (i < categoriesEn.length) 'en_title': categoriesEn[i],
          },
      ],
      'Likes': likes,
      'DisLikes': dislikes,
      'trailer': trailerUrl,
      'duration': duration,
    };
  }
}

class CinemanaCategoryItem {
  final int id;
  final String enTitle;
  final String arTitle;

  const CinemanaCategoryItem({
    required this.id,
    required this.enTitle,
    required this.arTitle,
  });

  factory CinemanaCategoryItem.fromJson(Map<String, dynamic> json) {
    return CinemanaCategoryItem(
      id: int.tryParse(json['nb']?.toString() ?? json['id']?.toString() ?? '0') ?? 0,
      enTitle: json['en_title']?.toString() ?? '',
      arTitle: json['ar_title']?.toString() ?? '',
    );
  }
}

class CinemanaEpisode {
  final String id;
  final String episodeNumber;
  final String seasonNumber;
  final String arTitle;
  final String enTitle;
  final String? imgUrl;
  final String duration;
  final String stars;

  const CinemanaEpisode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.arTitle,
    required this.enTitle,
    this.imgUrl,
    this.duration = '',
    this.stars = '',
  });

  int get intEpisodeNumber => int.tryParse(episodeNumber) ?? 0;
  int get intSeasonNumber => int.tryParse(seasonNumber) ?? 1;

  factory CinemanaEpisode.fromJson(Map<String, dynamic> json) {
    String? poster = json['imgObjUrl']?.toString();
    if (poster == null || poster.isEmpty) {
      poster = json['imgMediumThumbObjUrl']?.toString();
    }
    if (poster == null || poster.isEmpty) {
      poster = json['imgThumbObjUrl']?.toString();
    }

    return CinemanaEpisode(
      id: json['nb']?.toString() ?? '',
      episodeNumber: json['episodeNummer']?.toString() ?? '1',
      seasonNumber: json['season']?.toString() ?? '1',
      arTitle: json['ar_title']?.toString() ?? '',
      enTitle: json['en_title']?.toString() ?? '',
      imgUrl: poster,
      duration: json['duration']?.toString() ?? '',
      stars: json['stars']?.toString() ?? '',
    );
  }
}

class CinemanaStreamFile {
  final String name;
  final String resolution;
  final String container;
  final String videoUrl;

  const CinemanaStreamFile({
    required this.name,
    required this.resolution,
    required this.container,
    required this.videoUrl,
  });

  factory CinemanaStreamFile.fromJson(Map<String, dynamic> json) {
    return CinemanaStreamFile(
      name: json['name']?.toString() ?? '',
      resolution: json['resolution']?.toString() ?? '720p',
      container: json['container']?.toString() ?? 'mp4',
      videoUrl: json['videoUrl']?.toString() ?? '',
    );
  }
}
