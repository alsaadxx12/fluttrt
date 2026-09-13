import 'dart:math';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'series_models.dart';
import 'series_parser_service.dart';

class SeriesAggregatorService {
  final YoutubeExplode _yt = YoutubeExplode();
  final SeriesParserService _parser = SeriesParserService();

  static const Map<int, String> seasonOrdinalWords = {
    1: 'الاول',
    2: 'الثاني',
    3: 'الثالث',
    4: 'الرابع',
    5: 'الخامس',
    6: 'السادس',
    7: 'السابع',
    8: 'الثامن',
    9: 'التاسع',
    10: 'العاشر',
    11: 'الحادي عشر',
    12: 'الثاني عشر',
    13: 'الثالث عشر',
    14: 'الرابع عشر',
    15: 'الخامس عشر',
  };

  /// Extracts the clean base title of a series without season or episode keywords
  String cleanBaseTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'(?:الموسم|الجزء|موسم|جزء|البارت|بارت)\s*(?:\d+|الاول|الأول|الثاني|الثالث|الرابع|الخامس|السادس|السابع|الثامن|التاسع|العاشر|الحادي عشر|الثاني عشر|الثالث عشر|الرابع عشر|الخامس عشر)', caseSensitive: false), '')
        .replaceAll(RegExp(r'(?:Season|Part|Pt|S)\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'(?:^|\s)(?:جـ|ج)\s*\d+'), '')
        .replaceAll(RegExp(r'(?:الحلقة|حلقة|الحلق)\s*\d+'), '')
        .trim();
  }

  /// Searches across YouTube using deep multi-query pagination and smart gap recovery
  /// to discover and group episodes from all channels into a structured SeriesModel
  Future<SeriesModel> aggregateSeries(String seriesName) async {
    final cleanName = seriesName.trim();
    if (cleanName.isEmpty) {
      return const SeriesModel(seriesName: '', episodes: []);
    }

    final baseTitle = cleanBaseTitle(cleanName);
    final effectiveTitle = baseTitle.isNotEmpty ? baseTitle : cleanName;

    final Set<String> seenVideoIds = {};
    final List<Video> collectedVideos = [];

    void addVideos(Iterable<Video> videos) {
      for (final v in videos) {
        if (seenVideoIds.add(v.id.value)) {
          collectedVideos.add(v);
        }
      }
    }

    final querySeason = _parser.extractSeasonNumber(cleanName);
    final userSpecifiedSeason = cleanName.contains('الموسم') ||
        cleanName.contains('الجزء') ||
        cleanName.contains('موسم') ||
        cleanName.contains('جزء') ||
        cleanName.contains('البارت') ||
        cleanName.contains('بارت') ||
        cleanName.toLowerCase().contains('season') ||
        cleanName.toLowerCase().contains('part') ||
        RegExp(r'\bS\d+\b', caseSensitive: false).hasMatch(cleanName);

    final List<(String, int)> primaryQueries = [];

    if (userSpecifiedSeason && querySeason > 1) {
      // User specifically searched for a particular season (e.g. "وادي الذئاب الجزء 7")
      final sWord = seasonOrdinalWords[querySeason] ?? '$querySeason';
      primaryQueries.addAll([
        ('$effectiveTitle الجزء $sWord', 3),
        ('$effectiveTitle الجزء $querySeason', 3),
        ('$effectiveTitle الموسم $querySeason', 2),
        ('$effectiveTitle الجزء $sWord الحلقة', 2),
      ]);
    } else {
      // Broad search covering the series and initial seasons
      primaryQueries.addAll([
        (effectiveTitle, 3),
        ('$effectiveTitle الحلقة', 3),
        ('$effectiveTitle كاملة', 2),
        ('$effectiveTitle الجزء الثاني', 2),
        ('$effectiveTitle الجزء الثالث', 2),
      ]);
    }

    await Future.wait(
      primaryQueries.map((item) async {
        final q = item.$1;
        final maxPages = item.$2;
        try {
          var searchList = await _yt.search.search(q);
          addVideos(searchList);

          for (int p = 1; p < maxPages; p++) {
            try {
              final nextPage = await searchList.nextPage();
              if (nextPage == null || nextPage.isEmpty) break;
              searchList = nextPage;
              addVideos(searchList);
            } catch (_) {
              break;
            }
          }
        } catch (_) {}
      }),
    );

    // Initial analysis: what episode numbers were discovered?
    final discoveredNumbers = <int>{};
    for (final v in collectedVideos) {
      if (_parser.isNoiseVideo(v)) continue;
      final epNum = _parser.extractEpisodeNumber(v.title);
      if (epNum != null) {
        discoveredNumbers.add(epNum);
      }
    }

    // Smart Gap Auto-Recovery:
    if (discoveredNumbers.isNotEmpty) {
      final maxDiscovered = discoveredNumbers.reduce(max);
      final missingEpisodes = <int>[];

      for (int i = 1; i <= maxDiscovered; i++) {
        if (!discoveredNumbers.contains(i)) {
          missingEpisodes.add(i);
        }
      }

      if (maxDiscovered < 200) {
        missingEpisodes.add(maxDiscovered + 1);
      }

      await Future.wait(
        missingEpisodes.map((missingNum) async {
          try {
            final targetSearch = await _yt.search.search('$effectiveTitle الحلقة $missingNum');
            for (final v in targetSearch) {
              final epNum = _parser.extractEpisodeNumber(v.title);
              if (epNum == missingNum && !_parser.isNoiseVideo(v)) {
                addVideos([v]);
                break;
              }
            }
          } catch (_) {}
        }),
      );
    }

    // Group into organized chronological series model
    return _parser.groupIntoSeries(
      seriesName: effectiveTitle,
      rawVideos: collectedVideos,
    );
  }

  /// Targeted on-demand fetch for a specific season of a series
  Future<List<EpisodeItem>> fetchSeasonEpisodes({
    required String seriesName,
    required int seasonNumber,
  }) async {
    final baseTitle = cleanBaseTitle(seriesName);
    final effectiveTitle = baseTitle.isNotEmpty ? baseTitle : seriesName;

    final sWord = seasonOrdinalWords[seasonNumber] ?? '$seasonNumber';
    final queries = [
      ('$effectiveTitle الجزء $sWord', 3),
      ('$effectiveTitle الجزء $seasonNumber', 3),
      ('$effectiveTitle الموسم $seasonNumber', 2),
      ('$effectiveTitle الجزء $sWord الحلقة', 2),
    ];

    final Set<String> seenVideoIds = {};
    final List<Video> collectedVideos = [];

    void addVideos(Iterable<Video> videos) {
      for (final v in videos) {
        if (seenVideoIds.add(v.id.value)) {
          collectedVideos.add(v);
        }
      }
    }

    await Future.wait(
      queries.map((item) async {
        final q = item.$1;
        final maxPages = item.$2;
        try {
          var searchList = await _yt.search.search(q);
          addVideos(searchList);

          for (int p = 1; p < maxPages; p++) {
            try {
              final nextPage = await searchList.nextPage();
              if (nextPage == null || nextPage.isEmpty) break;
              searchList = nextPage;
              addVideos(searchList);
            } catch (_) {
              break;
            }
          }
        } catch (_) {}
      }),
    );

    // Group and filter strictly for this season
    final fullModel = _parser.groupIntoSeries(
      seriesName: effectiveTitle,
      rawVideos: collectedVideos,
    );

    final seasonEpisodes = fullModel.getEpisodesForSeason(seasonNumber);

    // If some numbers are missing between 1 and max, attempt fast gap recovery
    if (seasonEpisodes.isNotEmpty) {
      final foundNumbers = seasonEpisodes.map((e) => e.episodeNumber).toSet();
      final maxEp = foundNumbers.reduce(max);
      final missingEps = <int>[];
      for (int i = 1; i <= maxEp; i++) {
        if (!foundNumbers.contains(i)) missingEps.add(i);
      }

      if (missingEps.isNotEmpty && missingEps.length < 20) {
        await Future.wait(
          missingEps.map((missingNum) async {
            try {
              final res = await _yt.search.search('$effectiveTitle الجزء $sWord الحلقة $missingNum');
              for (final v in res) {
                final s = _parser.extractSeasonNumber(v.title);
                final ep = _parser.extractEpisodeNumber(v.title);
                if (s == seasonNumber && ep == missingNum && !_parser.isNoiseVideo(v)) {
                  addVideos([v]);
                  break;
                }
              }
            } catch (_) {}
          }),
        );

        // Re-group with recovered videos
        final updatedModel = _parser.groupIntoSeries(
          seriesName: effectiveTitle,
          rawVideos: collectedVideos,
        );
        return updatedModel.getEpisodesForSeason(seasonNumber);
      }
    }

    return seasonEpisodes;
  }

  void dispose() {
    _yt.close();
  }
}
