/// Cinemana subtitle files: where to find them and how to read them into
/// timed lines the player draws itself.
library;

/// A video's subtitle file URLs (Arabic / English), when Cinemana has them.
class CinemanaSubtitleSources {
  final String? ar;
  final String? en;

  const CinemanaSubtitleSources({this.ar, this.en});

  bool get isEmpty => ar == null && en == null;

  /// Reads `translationFiles/id/{id}` (or `allVideoInfo`) JSON. A missing
  /// language comes back as a placeholder like "defaultImages/loading.gif",
  /// so only real .srt/.vtt links count. Episodes carry only the
  /// `*TranslationFilePath` fields; films also list them in `translations`.
  factory CinemanaSubtitleSources.fromJson(Map<String, dynamic> json) {
    String? ar = _subtitleUrl(json['arTranslationFilePath']);
    String? en = _subtitleUrl(json['enTranslationFilePath']);
    final list = json['translations'];
    if (list is List) {
      for (final t in list.whereType<Map>()) {
        final url = _subtitleUrl(t['file']);
        if (url == null) continue;
        final type = '${t['type'] ?? ''}'.toLowerCase();
        if (type == 'ar') ar ??= url;
        if (type == 'en') en ??= url;
      }
    }
    return CinemanaSubtitleSources(ar: ar, en: en);
  }

  static String? _subtitleUrl(Object? value) {
    final s = value is String ? value.trim() : '';
    if (!s.startsWith('http')) return null;
    final path = Uri.tryParse(s)?.path.toLowerCase() ?? '';
    return path.endsWith('.srt') || path.endsWith('.vtt') ? s : null;
  }
}

/// One subtitle line group and when it is on screen.
class SubtitleCue {
  final int startMs;
  final int endMs;
  final String text;

  const SubtitleCue(this.startMs, this.endMs, this.text);
}

final _timing = RegExp(
  r'^\s*((?:\d+:)?\d{1,2}:\d{1,2}[,.]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{1,2}[,.]\d{1,3})',
);
final _counter = RegExp(r'^\d+$');
// Markup the app does not style: <font>, <i>, {\an8} and the like.
final _tag = RegExp(r'<[^>\n]*>');
final _assTag = RegExp(r'\{\\[^}]*\}');

/// Reads SRT (or WebVTT) text into cues, markup removed.
List<SubtitleCue> parseSubtitles(String source) {
  final lines = source
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final cues = <SubtitleCue>[];

  var i = 0;
  while (i < lines.length) {
    final m = _timing.firstMatch(lines[i]);
    if (m == null) {
      i++;
      continue;
    }
    final start = _millis(m.group(1)!);
    final end = _millis(m.group(2)!);
    i++;
    final text = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      // A cue with no blank line before the next one: stop at its timing.
      if (_timing.hasMatch(lines[i])) break;
      final line = _decodeEntities(
        lines[i].replaceAll(_assTag, '').replaceAll(_tag, ''),
      ).trim();
      if (line.isNotEmpty) text.add(line);
      i++;
    }
    // Drop the next cue's SRT counter if it slipped into this cue's text.
    if (text.isNotEmpty && i < lines.length && _timing.hasMatch(lines[i]) &&
        _counter.hasMatch(text.last)) {
      text.removeLast();
    }
    if (text.isEmpty || start == null || end == null || end <= start) continue;
    cues.add(SubtitleCue(start, end, text.join('\n')));
  }
  cues.sort((a, b) => a.startMs.compareTo(b.startMs));
  return cues;
}

/// "1:02:03,4" -> 3723400; null if the numbers make no sense.
int? _millis(String t) {
  final parts = t.replaceAll(',', '.').split(':');
  final secParts = parts.removeLast().split('.');
  final h = parts.length == 2 ? int.tryParse(parts[0]) : 0;
  final m = int.tryParse(parts.isEmpty ? '0' : parts.last);
  final s = int.tryParse(secParts[0]);
  final ms = int.tryParse(
    secParts.length > 1 ? secParts[1].padRight(3, '0').substring(0, 3) : '0',
  );
  if (h == null || m == null || s == null || ms == null || m > 59 || s > 59) return null;
  return ((h * 60 + m) * 60 + s) * 1000 + ms;
}

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
