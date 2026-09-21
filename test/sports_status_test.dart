import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/sports/data/match_merge.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';

SportMatchItem _m(String status, {DateTime? kickoff}) => SportMatchItem(
      id: 1,
      kickoffAt: (kickoff ?? DateTime.now().toUtc().subtract(const Duration(minutes: 30))).toIso8601String(),
      status: status,
      home: TeamInfo(name: 'Barcelona'),
      away: TeamInfo(name: 'Valencia'),
    );

/// The live-matches row must show only games in play. These pin down which
/// raw statuses count as live / ended, and — the bug behind "yesterday's
/// Barcelona game is in the live row" — that a finished match can never be
/// promoted to live by a channel feed's placeholder or a stale status.
void main() {
  test('live statuses (recent kick-off)', () {
    for (final s in ['live', 'LIVE', 'Live', 'in_progress', 'IN_PROGRESS', '1H', 'HT', '2h', 'ET', 'PEN']) {
      expect(_m(s).isLive, isTrue, reason: '"$s" should be live');
      expect(_m(s).isEnded, isFalse, reason: '"$s" must not be ended');
    }
  });

  test('ended statuses', () {
    for (final s in ['ended', 'ENDED', 'finished', 'Finished', 'FT', 'ft', 'full_time', 'AET', 'completed']) {
      expect(_m(s).isEnded, isTrue, reason: '"$s" should be ended');
      expect(_m(s).isLive, isFalse, reason: '"$s" must not be live');
    }
  });

  test('the channel feed placeholder مباشر is a listing, not a live game', () {
    final m = _m('مباشر');
    expect(m.isLive, isFalse);
    expect(m.isEnded, isFalse);
    expect(m.isScheduled, isTrue);
  });

  test('a stale "live" from yesterday is not live', () {
    final old = _m('live', kickoff: DateTime.now().toUtc().subtract(const Duration(hours: 20)));
    expect(old.isLive, isFalse, reason: 'kick-off 20h ago cannot still be in play');
    expect(old.isEnded, isTrue, reason: 'long past kick-off counts as over, whatever the feed says');
    // Same for a game the feed never flipped from "scheduled": it is over,
    // not upcoming — the case that left a finished match with a dead play button.
    final forgotten = _m('scheduled', kickoff: DateTime.now().toUtc().subtract(const Duration(hours: 5)));
    expect(forgotten.isEnded, isTrue);
    expect(forgotten.isScheduled, isFalse);
    final justOver = _m('live', kickoff: DateTime.now().toUtc().subtract(const Duration(hours: 4)));
    expect(justOver.isLive, isFalse);
    final playing = _m('live', kickoff: DateTime.now().toUtc().subtract(const Duration(minutes: 70)));
    expect(playing.isLive, isTrue);
  });

  test('a "live" flag on a match that has not kicked off yet is a phantom', () {
    // The feed marks games live hours before kick-off (Inter–Udinese at
    // 18:45Z was "live" at 14:01Z). Not started means not live.
    final hoursAway = _m('live', kickoff: DateTime.now().toUtc().add(const Duration(hours: 2)));
    expect(hoursAway.isLive, isFalse, reason: 'kick-off in 2h cannot be in play');
    expect(hoursAway.isScheduled, isTrue, reason: 'it belongs with the upcoming games');
    // A few minutes early is within tolerance (clocks and early whistles).
    final aboutToStart = _m('live', kickoff: DateTime.now().toUtc().add(const Duration(minutes: 5)));
    expect(aboutToStart.isLive, isTrue);
  });

  test('merge: a finished match is never promoted to live, in either order', () {
    final ended = _m('ended');
    final channel = _m('مباشر');
    for (final merged in [MatchMerge.combine(ended, channel), MatchMerge.combine(channel, ended)]) {
      expect(merged.isEnded, isTrue, reason: 'ended must win over the channel placeholder');
      expect(merged.isLive, isFalse);
    }
    final staleLive = _m('live', kickoff: DateTime.now().toUtc().subtract(const Duration(hours: 20)));
    for (final merged in [MatchMerge.combine(ended, staleLive), MatchMerge.combine(staleLive, ended)]) {
      expect(merged.isEnded, isTrue, reason: 'ended must win over a stale live status');
      expect(merged.isLive, isFalse);
    }
  });

  test('merge: a genuinely live match beats a scheduled copy', () {
    final scheduled = _m('scheduled');
    final live = _m('live');
    expect(MatchMerge.combine(scheduled, live).isLive, isTrue);
    expect(MatchMerge.combine(live, scheduled).isLive, isTrue);
  });
}
