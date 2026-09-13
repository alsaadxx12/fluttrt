import 'models/sports_models.dart';
import 'services/sports_service.dart';

/// Folds the feeds' match lists into one list with no fixture twice.
///
/// The feeds number their matches independently, so the same fixture carries
/// a different id in each. Anything that de-duplicates by id therefore lets
/// both copies through, which is how one match came to sit twice in the same
/// table. Identity here is the two teams.
///
/// A fixture both feeds carry survives once, keeping every channel either
/// feed knew about, so the viewer picks the source inside the match instead
/// of picking between two identical rows.
class MatchMerge {
  MatchMerge._();

  /// The same fixture: both sides agree. Feeds sometimes disagree on which
  /// side is at home, and that does not make it another match.
  static bool sameFixture(SportMatchItem a, SportMatchItem b) {
    final straight =
        SportsService.teamsMatch(a.home.name, b.home.name) && SportsService.teamsMatch(a.away.name, b.away.name);
    final swapped =
        SportsService.teamsMatch(a.home.name, b.away.name) && SportsService.teamsMatch(a.away.name, b.home.name);
    return straight || swapped;
  }

  /// [into] keeps how the match is shown; [extra] only adds what it knows.
  static SportMatchItem combine(SportMatchItem into, SportMatchItem extra) {
    final channels = <BroadcastChannel>[...into.broadcasters];
    for (final c in extra.broadcasters) {
      final known = channels.any((x) => x.id == c.id || x.name == c.name);
      if (!known) channels.add(c);
    }
    return into.copyWith(
      hasWatch: into.hasWatch || extra.hasWatch,
      streamId: into.streamId ?? extra.streamId,
      directUrl: into.directUrl ?? extra.directUrl,
      broadcasters: channels,
      broadcasterName: into.broadcasterName ?? extra.broadcasterName,
      // A feed that has it live is more current than one that does not.
      status: into.isLive ? into.status : (extra.isLive ? extra.status : into.status),
      homeScore: into.homeScore ?? extra.homeScore,
      awayScore: into.awayScore ?? extra.awayScore,
    );
  }

  /// The record in [candidates] that is the same fixture as [target], or
  /// null when none of them is.
  ///
  /// An id is only meaningful inside the feed that issued it. Trusting one
  /// across feeds opens a different game whenever two unrelated matches
  /// happen to carry the same number, so whenever both records name their
  /// teams the names decide and a disagreement is refused outright: no
  /// stream is far better than another match's stream. Ids are the fallback
  /// only when there are no names to compare.
  static SportMatchItem? findSame(SportMatchItem target, List<SportMatchItem> candidates) {
    final named = target.home.name.isNotEmpty && target.away.name.isNotEmpty;
    for (final c in candidates) {
      final bothNamed = named && c.home.name.isNotEmpty && c.away.name.isNotEmpty;
      if (bothNamed) {
        if (sameFixture(target, c)) return c;
        continue;
      }
      if (c.id == target.id) return c;
      final src = target.sourceId;
      if (src != null && src.isNotEmpty && c.sourceId == src) return c;
    }
    return null;
  }

  /// The lists in priority order. The first list owns how a shared fixture
  /// is shown.
  static List<SportMatchItem> mergeAll(List<List<SportMatchItem>> lists) {
    final out = <SportMatchItem>[];
    for (final list in lists) {
      for (final m in list) {
        final i = out.indexWhere((x) => sameFixture(x, m));
        if (i >= 0) {
          out[i] = combine(out[i], m);
        } else {
          out.add(m);
        }
      }
    }
    return out;
  }
}
