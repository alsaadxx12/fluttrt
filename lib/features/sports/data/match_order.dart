import 'models/sports_models.dart';

/// The order a day's matches are shown in on the home row: what is being
/// played now first, then what is still to come (soonest kick-off first),
/// then what is over (most recently finished first).
///
/// The three buckets are exhaustive and disjoint (`isScheduled` is "neither
/// live nor ended"), so every match appears exactly once.
class MatchOrder {
  MatchOrder._();

  static int _kick(SportMatchItem m) => DateTime.tryParse(m.kickoffAt)?.millisecondsSinceEpoch ?? 0;

  static List<SportMatchItem> dayOrder(List<SportMatchItem> matches) {
    final live = matches.where((m) => m.isLive).toList()..sort((a, b) => _kick(a).compareTo(_kick(b)));
    final upcoming = matches.where((m) => m.isScheduled).toList()..sort((a, b) => _kick(a).compareTo(_kick(b)));
    final finished = matches.where((m) => m.isEnded).toList()..sort((a, b) => _kick(b).compareTo(_kick(a)));
    return [...live, ...upcoming, ...finished];
  }
}
