import 'models/sports_models.dart';

/// The order a day's matches are shown in on the home row: what is being
/// played now first, then what is still to come (soonest kick-off first).
///
/// Finished games are not shown at all: there is nothing left to watch, and
/// a tap on one only produces a "match ended" notice. The source already
/// drops them; this keeps the row correct even if a merge lets one through.
class MatchOrder {
  MatchOrder._();

  static int _kick(SportMatchItem m) => DateTime.tryParse(m.kickoffAt)?.millisecondsSinceEpoch ?? 0;

  static List<SportMatchItem> dayOrder(List<SportMatchItem> matches, {bool includeEnded = false}) {
    final live = matches.where((m) => m.isLive || m.status == 'live').toList()..sort((a, b) => _kick(a).compareTo(_kick(b)));
    final upcoming = matches.where((m) => m.isScheduled && m.status != 'live' && m.status != 'finished' && !m.isEnded).toList()..sort((a, b) => _kick(a).compareTo(_kick(b)));
    if (!includeEnded) {
      return [...live, ...upcoming];
    }
    final ended = matches.where((m) => m.isEnded || m.status == 'finished' || m.status == 'ended').toList()..sort((a, b) => _kick(b).compareTo(_kick(a)));
    return [...live, ...upcoming, ...ended];
  }
}
