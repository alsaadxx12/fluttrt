import 'media_item.dart';
import 'media_key.dart';

/// Folds several providers' catalogues into one list with nothing shown
/// twice.
///
/// The order the lists arrive in IS the priority: the first provider that
/// carries a work owns how it is shown, later providers only add themselves
/// to its [MediaItem.sources] as a fallback.
class MediaMerger {
  MediaMerger._();

  /// [lists] in priority order (Cinemana first today).
  static List<MediaItem> merge(List<List<MediaItem>> lists) {
    final byKey = <String, MediaItem>{};
    final order = <String>[];
    // Movies missing a year cannot form an exact key; they are matched by
    // title similarity against what is already in, per kind.
    final undated = <MediaKind, List<String>>{};

    for (final list in lists) {
      for (final item in list) {
        final key = MediaKey.of(item);
        final existing = byKey[key];
        if (existing != null) {
          byKey[key] = existing.mergedWith(item);
          continue;
        }
        final loose = (item.kind == MediaKind.movie && item.year == null) ? _looseMatch(byKey, undated, item) : null;
        if (loose != null) {
          byKey[loose] = byKey[loose]!.mergedWith(item);
          continue;
        }
        byKey[key] = item;
        order.add(key);
        if (item.kind == MediaKind.movie && item.year == null) (undated[item.kind] ??= []).add(key);
      }
    }
    return [for (final k in order) byKey[k]!];
  }

  /// A work with no year: accept it as an existing one only when the titles
  /// are all but identical AND the kinds agree.
  static String? _looseMatch(
    Map<String, MediaItem> byKey,
    Map<MediaKind, List<String>> undated,
    MediaItem item,
  ) {
    final title = item.originalTitle.isNotEmpty ? item.originalTitle : item.title;
    // Against other undated works of the same kind.
    for (final k in undated[item.kind] ?? const <String>[]) {
      final other = byKey[k]!;
      if (MediaKey.sameTitle(title, other.originalTitle.isNotEmpty ? other.originalTitle : other.title)) {
        return k;
      }
    }
    // And against dated ones: a dated work is still the same work when the
    // newcomer simply does not know the year.
    for (final entry in byKey.entries) {
      final other = entry.value;
      if (other.kind != item.kind || other.year == null) continue;
      if (MediaKey.sameTitle(title, other.originalTitle.isNotEmpty ? other.originalTitle : other.title)) {
        return entry.key;
      }
    }
    return null;
  }
}
