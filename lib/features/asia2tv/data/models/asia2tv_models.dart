import 'package:flutter/foundation.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';

enum Asia2TvCategory {
  newEpisodes('الحلقات الجديدة', 'category/new-episodes/'),
  korean('دراما كورية', 'category/asian-drama/korean/'),
  japanese('دراما يابانية', 'category/asian-drama/japanese/'),
  chinese('دراما صينية', 'category/asian-drama/chinese-taiwanese/'),
  thai('دراما تايلاندية', 'category/asian-drama/thai/'),
  movies('أفلام آسيوية', 'category/asian-movies/'),
  completed('دراما مكتملة', 'completed-dramas/');

  final String label;
  final String path;
  const Asia2TvCategory(this.label, this.path);
}

@immutable
class Asia2TvItem {
  final String id;
  final String title;
  final String url;
  final String posterUrl;
  final String? year;
  final String? category;
  final bool isMovie;
  final bool isEpisode;
  final int? episodeNumber;
  final String? story;
  final String? country;
  final String? genre;
  final String? otherNames;

  const Asia2TvItem({
    required this.id,
    required this.title,
    required this.url,
    required this.posterUrl,
    this.year,
    this.category,
    this.isMovie = false,
    this.isEpisode = false,
    this.episodeNumber,
    this.story,
    this.country,
    this.genre,
    this.otherNames,
  });

  Asia2TvItem copyWith({
    String? id,
    String? title,
    String? url,
    String? posterUrl,
    String? year,
    String? category,
    bool? isMovie,
    bool? isEpisode,
    int? episodeNumber,
    String? story,
    String? country,
    String? genre,
    String? otherNames,
  }) {
    return Asia2TvItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      posterUrl: posterUrl ?? this.posterUrl,
      year: year ?? this.year,
      category: category ?? this.category,
      isMovie: isMovie ?? this.isMovie,
      isEpisode: isEpisode ?? this.isEpisode,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      story: story ?? this.story,
      country: country ?? this.country,
      genre: genre ?? this.genre,
      otherNames: otherNames ?? this.otherNames,
    );
  }

  /// This title as a [CinemanaItem], so it can sit in a row beside the
  /// app's own catalogue.
  ///
  /// [CinemanaItem.externalSource] marks it, because the id below is this
  /// catalogue's, not Cinemana's: a card must route it to its own page.
  /// [CinemanaItem.kind] is '1' for a film and '2' for a series - the values
  /// `isSeries` actually reads.
  CinemanaItem toCinemanaItem() {
    remember(this);
    return CinemanaItem(
      id: id,
      arTitle: title,
      enTitle: otherNames ?? title,
      stars: '',
      year: year ?? '',
      kind: isMovie ? '1' : '2',
      arContent: story ?? '',
      enContent: story ?? '',
      imgUrl: posterUrl,
      imgMediumUrl: posterUrl,
      imgThumbUrl: posterUrl,
      externalSource: externalSourceKey,
    );
  }

  /// The value [CinemanaItem.externalSource] carries for this catalogue.
  static const String externalSourceKey = 'asian-catalogue';

  /// Every title seen so far, by id.
  ///
  /// A merged row hands a generic card a [CinemanaItem], which keeps only
  /// the id; opening it needs this entry back, so converting one files it
  /// here. Bounded: a listing page is a few dozen titles and the map is
  /// trimmed once it grows past a few hundred.
  static final Map<String, Asia2TvItem> _byId = {};

  static void remember(Asia2TvItem item) {
    if (_byId.length > 600) _byId.clear();
    _byId[item.id] = item;
  }

  /// The entry behind a converted [CinemanaItem], or null if it was never
  /// seen (a cold start restoring a saved list, say).
  static Asia2TvItem? byId(String id) => _byId[id];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Asia2TvItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class Asia2TvEpisode {
  final int number;
  final String title;
  final String url;

  const Asia2TvEpisode({
    required this.number,
    required this.title,
    required this.url,
  });

  @override
  String toString() => 'Asia2TvEpisode($number, $title, $url)';
}

@immutable
class Asia2TvServer {
  final String name;
  final String serverUrl;
  final String serverClass;

  const Asia2TvServer({
    required this.name,
    required this.serverUrl,
    required this.serverClass,
  });
}

@immutable
class Asia2TvPlayback {
  final List<CinemanaStreamFile> streams;
  final List<Asia2TvServer> servers;
  final String activeServerName;
  final String? defaultStreamUrl;
  final String? highestResolution;

  const Asia2TvPlayback({
    required this.streams,
    required this.servers,
    required this.activeServerName,
    this.defaultStreamUrl,
    this.highestResolution,
  });
}
