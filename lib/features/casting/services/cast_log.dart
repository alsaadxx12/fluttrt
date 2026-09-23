import 'dart:collection';

import 'package:flutter/foundation.dart';

/// The casting log, kept in memory so a page in the app can show it.
///
/// Every line the casting code prints starts with `[cast]`; the same lines
/// that go to logcat are kept here, the last few hundred of them, with the
/// time they were printed. The diagnostics page reads them back, so «why
/// did it not play» can be answered on the phone, in the room, without a
/// cable and a computer.
class CastLog {
  CastLog._();

  static const int _keep = 400;
  static const String _mark = '[cast]';

  static final Queue<CastLogLine> _lines = Queue<CastLogLine>();
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _installed = false;

  /// Starts keeping `[cast]` lines. Call once, at start-up.
  static void install() {
    if (_installed) return;
    _installed = true;
    final downstream = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains(_mark)) add(message);
      downstream(message, wrapWidth: wrapWidth);
    };
  }

  static void add(String message) {
    final text = message.replaceFirst(_mark, '').trim();
    _lines.addLast(CastLogLine(DateTime.now(), text));
    while (_lines.length > _keep) {
      _lines.removeFirst();
    }
    revision.value++;
  }

  static List<CastLogLine> get lines => List<CastLogLine>.unmodifiable(_lines);

  static void clear() {
    _lines.clear();
    revision.value++;
  }

  /// The last line that starts with [prefix], or null.
  static CastLogLine? last(String prefix) {
    for (final line in _lines.toList().reversed) {
      if (line.text.startsWith(prefix)) return line;
    }
    return null;
  }

  /// The whole log as text, for copying.
  static String get asText => _lines
      .map((l) => '${_clock(l.at)}  ${l.text}')
      .join('\n');

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

@immutable
class CastLogLine {
  const CastLogLine(this.at, this.text);
  final DateTime at;
  final String text;

  String get clock => CastLog._clock(at);
}
