import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'series_models.dart';

class SeriesParserService {
  // Common noise keywords that indicate clips, teasers, or summaries rather than full episodes
  static final List<String> _noiseKeywords = [
    'برومو',
    'إعلان',
    'اعلان',
    'تريلر',
    'ملخص',
    'أبرز لقطات',
    'كواليس',
    'مشهد',
    'تسريب',
    'مراجعة',
    'trailer',
    'teaser',
    'promo',
    'review',
    'preview',
    'shorts',
    '#shorts',
  ];

  /// Returns true if the video is likely a promo, clip, or trailer instead of a full episode
  bool isNoiseVideo(Video video) {
    final titleLower = video.title.toLowerCase();

    // Check if title contains noise keyword unless it explicitly contains 'الحلقة كاملة'
    final isExplicitlyFull = titleLower.contains('كاملة') || titleLower.contains('full episode');

    if (!isExplicitlyFull) {
      for (final keyword in _noiseKeywords) {
        if (titleLower.contains(keyword)) {
          return true;
        }
      }
    }

    // Check duration: if duration is less than 3 minutes, it's almost certainly a promo or clip
    final duration = video.duration;
    if (duration != null && duration.inSeconds < 180 && !isExplicitlyFull) {
      return true;
    }

    return false;
  }

  int extractSeasonNumber(String title) {
    // 1. S01E02 standard format (e.g. S03E01, S3E5)
    final seMatch = RegExp(r'[sS](\d{1,2})[eE]\d{1,4}', caseSensitive: false).firstMatch(title);
    if (seMatch != null) {
      final val = int.tryParse(seMatch.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 2. English Season: Season 3, S3, Season.3, Season-3, S03
    final sEngMatch = RegExp(r'(?:\bSeason\s*|\bS)(\d{1,2})(?:E|\b|\s|\.)', caseSensitive: false).firstMatch(title);
    if (sEngMatch != null) {
      final val = int.tryParse(sEngMatch.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 3. English Part: Part 3, Part 03, Part.3, Part-3, Pt 3, Pt.3
    final partEng = RegExp(r'\b(?:Part|Pt)\s*[:#\-.]?\s*(\d{1,2})\b', caseSensitive: false).firstMatch(title);
    if (partEng != null) {
      final val = int.tryParse(partEng.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 4. Arabic transliterated "البارت" / "بارت": بارت 3, البارت 3, بارت3, البارت ٠٣
    final partArab = RegExp(r'(?:البارت|بارت)\s*[:#\-.]?\s*(\d{1,2})').firstMatch(title);
    if (partArab != null) {
      final val = int.tryParse(partArab.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 5. Arabic word "البارت": البارت الاول to العاشر
    final partWord = RegExp(
      r'(?:البارت|بارت)\s+(الاول|الأول|الثاني|الثالث|الرابع|الخامس|السادس|السابع|الثامن|التاسع|العاشر)',
    ).firstMatch(title);
    if (partWord != null) {
      const wordMap = {
        'الاول': 1, 'الأول': 1, 'الثاني': 2, 'الثالث': 3, 'الرابع': 4,
        'الخامس': 5, 'السادس': 6, 'السابع': 7, 'الثامن': 8, 'التاسع': 9, 'العاشر': 10,
      };
      final val = wordMap[partWord.group(1)!];
      if (val != null) return val;
    }

    // 6. Arabic formats with digits: الموسم 2, الجزء 3, موسم 4, جزء 5
    final sArabMatch = RegExp(r'(?:الموسم|الجزء|موسم|جزء)\s*[:#\-.]?\s*(\d{1,2})').firstMatch(title);
    if (sArabMatch != null) {
      final val = int.tryParse(sArabMatch.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 7. Abbreviated Arabic part: ج3, ج 3, جـ3, جـ 3, ج.3
    final sAbbrMatch = RegExp(r'(?:^|\s)(?:جـ|ج)\s*[:#\-.]?\s*(\d{1,2})(?:\s|[^\w\u0600-\u06FF]|$)').firstMatch(title);
    if (sAbbrMatch != null) {
      final val = int.tryParse(sAbbrMatch.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 8. Arabic compound word seasons: الجزء الحادي عشر, الموسم الثاني عشر
    final sCompoundMatch = RegExp(
      r'(?:الموسم|الجزء|موسم|جزء)\s+(الحادي|الثاني|الثالث|الرابع|الخامس)\s+عشر',
    ).firstMatch(title);
    if (sCompoundMatch != null) {
      const compoundMap = {
        'الحادي': 11,
        'الثاني': 12,
        'الثالث': 13,
        'الرابع': 14,
        'الخامس': 15,
      };
      return compoundMap[sCompoundMatch.group(1)!] ?? 1;
    }

    // 9. Arabic word seasons: الموسم الاول to العاشر
    final sWordsMatch = RegExp(
      r'(?:الموسم|الجزء|موسم|جزء)\s+(الاول|الأول|الثاني|الثالث|الرابع|الخامس|السادس|السابع|الثامن|التاسع|العاشر)',
    ).firstMatch(title);
    if (sWordsMatch != null) {
      const wordMap = {
        'الاول': 1, 'الأول': 1, 'الثاني': 2, 'الثالث': 3, 'الرابع': 4,
        'الخامس': 5, 'السادس': 6, 'السابع': 7, 'الثامن': 8, 'التاسع': 9, 'العاشر': 10,
      };
      return wordMap[sWordsMatch.group(1)!] ?? 1;
    }

    // 10. Pattern: Number followed by separator and (الحلقة / حلقة / Ep)
    // e.g. "ايام الدراسة 3 الحلقة 1", "باب الحارة 2 - الحلقة 14"
    final seriesNumBeforeEp = RegExp(
      r'(?:^|\s)(\d{1,2})\s*(?:[-–—|:]|\s)\s*(?:الحلقة|حلقة|حـ|ح|Episode|Ep|E)\s*[:#\-]?\s*(\d{1,4})',
      caseSensitive: false,
    ).firstMatch(title);
    if (seriesNumBeforeEp != null) {
      final val = int.tryParse(seriesNumBeforeEp.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    // 11. Pattern: "Series 3 | 1" (Number pipe Number)
    final pipeMatch = RegExp(r'(?:^|\s)(\d{1,2})\s*\|\s*(\d{1,4})(?:\s|$)').firstMatch(title);
    if (pipeMatch != null) {
      final val = int.tryParse(pipeMatch.group(1)!);
      if (val != null && val >= 1 && val <= 15) return val;
    }

    return 1;
  }

  /// Normalizes Arabic characters for robust pattern matching
  String normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '') // Tashkeel / diacritics
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .trim();
  }

  /// Parses Arabic written numbers (e.g. الأولى -> 1, الثالثة والعشرون -> 23, الأربعون -> 40)
  int? parseArabicTextNumber(String phrase) {
    final clean = normalizeArabic(phrase);

    // 1. Compound numbers with 'و': e.g. "الثالثه والثلاثون", "الواحده والاربعون", "الخامس والعشرين" (21 to 99)
    final compoundRegex = RegExp(
      r'(?:^|\s)(الواحد|الواحده|الثاني|الثانيه|الثالث|الثالثه|الرابع|الرابعه|الخامس|الخامسه|السادس|السادسه|السابع|السابعه|الثامن|الثامنه|التاسع|التاسعه)\s+و(العشرون|العشرين|الثلاثون|الثلاثين|الاربعون|الاربعين|الخمسون|الخمسين|الستون|الستين|السبعون|السبعين|الثمانون|الثمانين|التسعون|التسعين)(?:\s|$)',
    );

    final compMatch = compoundRegex.firstMatch(clean);
    if (compMatch != null) {
      final unitWord = compMatch.group(1)!;
      final tensWord = compMatch.group(2)!;

      int unit = 0;
      const unitPrefixes = {
        'الواحد': 1, 'الثاني': 2, 'الثالث': 3, 'الرابع': 4,
        'الخامس': 5, 'السادس': 6, 'السابع': 7, 'الثامن': 8, 'التاسع': 9,
      };
      for (final entry in unitPrefixes.entries) {
        if (unitWord.startsWith(entry.key)) {
          unit = entry.value;
          break;
        }
      }

      int tens = 0;
      const tensPrefixes = {
        'العشر': 20, 'الثلاث': 30, 'الاربع': 40, 'الخمس': 50,
        'الست': 60, 'السبع': 70, 'الثمان': 80, 'التسع': 90,
      };
      for (final entry in tensPrefixes.entries) {
        if (tensWord.startsWith(entry.key)) {
          tens = entry.value;
          break;
        }
      }

      return tens + unit;
    }

    // 2. Teens: e.g. "الثالث عشر", "الرابعه عشره" (11 to 19)
    final teenRegex = RegExp(
      r'(?:^|\s)(الحادي|الحاديه|الثاني|الثانيه|الثالث|الثالثه|الرابع|الرابعه|الخامس|الخامسه|السادس|السادسه|السابع|السابعه|الثامن|الثامنه|التاسع|التاسعه)\s+عشر',
    );
    final teenMatch = teenRegex.firstMatch(clean);
    if (teenMatch != null) {
      final unitWord = teenMatch.group(1)!;
      const teenPrefixes = {
        'الحادي': 11, 'الثاني': 12, 'الثالث': 13, 'الرابع': 14,
        'الخامس': 15, 'السادس': 16, 'السابع': 17, 'الثامن': 18, 'التاسع': 19,
      };
      for (final entry in teenPrefixes.entries) {
        if (unitWord.startsWith(entry.key)) {
          return entry.value;
        }
      }
    }

    // 3. Tens alone: e.g. "العشرون", "الثلاثون", "الاربعون", "الخمسون"
    final tensRegex = RegExp(
      r'(?:^|\s)(العشرون|العشرين|الثلاثون|الثلاثين|الاربعون|الاربعين|الخمسون|الخمسين|الستون|الستين|السبعون|السبعين|الثمانون|الثمانين|التسعون|التسعين|المائه|المئه)(?:\s|$)',
    );
    final tensMatch = tensRegex.firstMatch(clean);
    if (tensMatch != null) {
      final w = tensMatch.group(1)!;
      const tensAlone = {
        'العشر': 20, 'الثلاث': 30, 'الاربع': 40, 'الخمس': 50,
        'الست': 60, 'السبع': 70, 'الثمان': 80, 'التسع': 90, 'الم': 100,
      };
      for (final entry in tensAlone.entries) {
        if (w.startsWith(entry.key)) {
          return entry.value;
        }
      }
    }

    // 4. Units alone: e.g. "الاول", "الاولى", "الثانية", "العاشرة"
    final unitRegex = RegExp(
      r'(?:^|\s)(الاول|الاولى|الاولي|الاوله|الثاني|الثانيه|الثالث|الثالثه|الرابع|الرابعه|الخامس|الخامسه|السادس|السادسه|السابع|السابعه|الثامن|الثامنه|التاسع|التاسعه|العاشر|العاشره)(?:\s|$)',
    );
    final unitMatch = unitRegex.firstMatch(clean);
    if (unitMatch != null) {
      final u = unitMatch.group(1)!;
      const unitAlone = {
        'الاول': 1, 'الثاني': 2, 'الثالث': 3, 'الرابع': 4, 'الخامس': 5,
        'السادس': 6, 'السابع': 7, 'الثامن': 8, 'التاسع': 9, 'العاشر': 10,
      };
      for (final entry in unitAlone.entries) {
        if (u.startsWith(entry.key)) {
          return entry.value;
        }
      }
    }

    return null;
  }

  /// Extracts the episode number from the video title
  int? extractEpisodeNumber(String title) {
    // 1. S01E02 standard format
    final seMatch = RegExp(r'[sS]\d{1,2}[eE](\d{1,4})\b', caseSensitive: false).firstMatch(title);
    if (seMatch != null) {
      return int.tryParse(seMatch.group(1)!);
    }

    // 2. Digits after explicit episode markers:
    // "الحلقة 15", "حلقة 04", "ح 5", "حـ 6", "Episode 12", "Ep 03"
    final regexes = [
      RegExp(r'(?:الحلقة|حلقة|الحلق|حـ|ح)\s*[:#\-]?\s*(\d{1,4})', caseSensitive: false),
      RegExp(r'\b(?:Episode|Ep)\s*[:#\-.]?\s*(\d{1,4})\b', caseSensitive: false),
      RegExp(r'\[(?:Ep|E|الحلقة|حلقة)?\s*(\d{1,4})\]', caseSensitive: false),
      RegExp(r'\((?:Ep|E|الحلقة|حلقة)?\s*(\d{1,4})\)', caseSensitive: false),
      RegExp(r'\b(\d{1,3})\s*(?:الحلقة|حلقة|الحلق)\b', caseSensitive: false),
      RegExp(r'(?:^|\s)\d{1,2}\s*\|\s*(\d{1,4})(?:\s|$)'), // "Series 3 | 1"
      RegExp(r'[-–—|]\s*(\d{1,3})\s*[-–—|]?$'), // Trailing episode number e.g. "Series Name - 15"
    ];

    for (final reg in regexes) {
      final match = reg.firstMatch(title);
      if (match != null) {
        final num = int.tryParse(match.group(1)!);
        if (num != null && num > 0 && num < 2000) {
          return num;
        }
      }
    }

    // 2. Arabic textual numbers: "الحلقة الرابعة والعشرون", "الحلقة الثالثة والثلاثون", "الحلقة الأربعون", etc.
    return parseArabicTextNumber(title);
  }

  /// Calculates a quality and confidence score for a video candidate
  double scoreVideo(Video video) {
    double score = 0.0;

    // Full episode duration score
    final dur = video.duration;
    if (dur != null) {
      final mins = dur.inMinutes;
      if (mins >= 20 && mins <= 65) {
        score += 50.0; // Standard TV episode length
      } else if (mins >= 15 && mins <= 90) {
        score += 35.0;
      } else if (mins < 10) {
        score -= 20.0; // Likely a clip
      }
    }

    // Title confidence keywords
    final lowerTitle = video.title.toLowerCase();
    if (lowerTitle.contains('كاملة') || lowerTitle.contains('full')) {
      score += 25.0;
    }
    if (lowerTitle.contains('1080p') || lowerTitle.contains('hd')) {
      score += 10.0;
    }
    if (lowerTitle.contains('رسمي') || lowerTitle.contains('official')) {
      score += 15.0;
    }

    return score;
  }

  /// Groups a raw list of videos into an organized SeriesModel with deduplicated sequential episodes
  SeriesModel groupIntoSeries({
    required String seriesName,
    required List<Video> rawVideos,
  }) {
    final Map<int, Map<int, List<Video>>> seasonEpisodeMap = {};
    final Set<int> discoveredSeasons = {};
    int totalSourcesCount = 0;

    for (final video in rawVideos) {
      if (isNoiseVideo(video)) continue;

      final epNumber = extractEpisodeNumber(video.title);
      if (epNumber == null) continue;

      final seasonNumber = extractSeasonNumber(video.title);
      discoveredSeasons.add(seasonNumber);

      seasonEpisodeMap.putIfAbsent(seasonNumber, () => {});
      seasonEpisodeMap[seasonNumber]!.putIfAbsent(epNumber, () => []);
      seasonEpisodeMap[seasonNumber]![epNumber]!.add(video);
      totalSourcesCount++;
    }

    final List<EpisodeItem> episodesList = [];

    final sortedSeasons = seasonEpisodeMap.keys.toList()..sort();
    for (final s in sortedSeasons) {
      final epMap = seasonEpisodeMap[s]!;
      final sortedEpNumbers = epMap.keys.toList()..sort();

      for (final epNum in sortedEpNumbers) {
        final candidates = epMap[epNum]!;
        // Sort candidates by best score descending
        candidates.sort((a, b) => scoreVideo(b).compareTo(scoreVideo(a)));

        final primary = candidates.first;
        final alternatives = candidates.sublist(1);

        episodesList.add(
          EpisodeItem(
            episodeNumber: epNum,
            seasonNumber: s,
            primaryVideo: primary,
            alternativeVideos: alternatives,
            cleanTitle: 'الحلقة $epNum',
          ),
        );
      }
    }

    return SeriesModel(
      seriesName: seriesName,
      episodes: episodesList,
      availableSeasons: discoveredSeasons.isNotEmpty ? (discoveredSeasons.toList()..sort()) : [1],
      totalSourcesFound: totalSourcesCount,
    );
  }
}
