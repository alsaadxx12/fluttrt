import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/link_speed.dart';


/// How sharp a picture to send the other screen.
///
/// This is a real choice rather than a preference, because the ceiling is
/// not the app's to set alone. Sending 4K means the phone pulling roughly
/// 24 Mbit/s down and pushing the same back out over the wifi it is already
/// receiving on, and it means the far screen decoding 4K H.264 — which a
/// great many television players will not do at all, whatever their panel
/// can show. When any link in that chain cannot keep up, the result is a
/// black screen rather than a softer picture.
///
/// So the app defaults to what reliably arrives and lets anyone who knows
/// their network and their television ask for more.
enum CastQuality {
  /// Decided for each film from how fast the internet is at that moment:
  /// 1080p when the link carries it, 720p or 480p when it does not.
  ///
  /// The default, because the honest answer to «which quality» on a link
  /// that changes from one hour to the next is «measure it». See
  /// [LinkSpeed].
  auto(label: 'تلقائي حسب سرعة الإنترنت', short: 'تلقائي', maxHeight: 1080),

  /// 1080p at most. What every receiver here handles.
  balanced(label: 'جودة عالية', short: '1080p', maxHeight: 1080),

  /// The sharpest the catalogue offers, 4K included.
  sharpest(label: 'الأعلى المتاح', short: '4K', maxHeight: 4320),

  /// For a slow network or a set that struggles with anything more.
  light(label: 'أخف', short: '720p', maxHeight: 720);

  const CastQuality({
    required this.label,
    required this.short,
    required this.maxHeight,
  });

  /// Spelled out, for the menu.
  final String label;

  /// The number alone, for the line it shares with the pairing button —
  /// where the spelled-out form overflowed the sheet by sixty pixels.
  final String short;

  final int maxHeight;

  /// True when the link is measured before each film and the ceiling set
  /// from that.
  bool get adaptive => this == CastQuality.auto;

  static CastQuality byName(String? name) => values.firstWhere(
        (q) => q.name == name,
        orElse: () => CastQuality.auto,
      );
}

/// The chosen quality, remembered between runs.
class CastQualityNotifier extends StateNotifier<CastQuality> {
  CastQualityNotifier() : super(CastQuality.auto) {
    _load();
  }

  static const String _key = 'cast_quality';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = CastQuality.byName(prefs.getString(_key));
    } catch (_) {
      // A preference that cannot be read is not worth failing over; the
      // default is the safe one anyway.
    }
  }

  Future<void> set(CastQuality quality) async {
    state = quality;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, quality.name);
    } catch (_) {}
  }
}

final castQualityProvider =
    StateNotifierProvider<CastQualityNotifier, CastQuality>(
  (ref) => CastQualityNotifier(),
);

/// The height ceiling to resolve a stream with right now.
final castMaxHeightProvider = Provider<int>(
  (ref) => ref.watch(castQualityProvider).maxHeight,
);
