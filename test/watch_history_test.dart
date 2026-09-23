import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/casting/services/resume_store.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/history/data/watch_history_entry.dart';
import 'package:youtube_downloader/features/history/presentation/providers/watch_history_provider.dart';

CinemanaItem film(String id, {String ar = '', String en = '', String kind = '1'}) => CinemanaItem(
      id: id,
      arTitle: ar.isEmpty ? 'فيلم $id' : ar,
      enTitle: en.isEmpty ? 'Film $id' : en,
      arContent: '',
      enContent: '',
      stars: '',
      kind: kind,
      year: '2024',
    );

void main() {
  late WatchHistoryNotifier history;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ResumeStore.reset();
    // On the device only: the cloud is a copy, and there is none here.
    history = WatchHistoryNotifier(cloud: false);
    await history.ready;
  });

  tearDown(() => history.dispose());

  test('a title opened goes to the front, once', () async {
    await history.record(film('a'));
    await history.record(film('b'));
    await history.record(film('a'));

    expect(history.state.map((e) => e.item.id), ['a', 'b']);
  });

  test('the minute reached is written down and shown', () async {
    await history.record(film('a'));
    await history.updatePosition('a', const Duration(minutes: 42, seconds: 10),
        duration: const Duration(hours: 2));

    final entry = history.state.single;
    expect(entry.position, const Duration(minutes: 42, seconds: 10));
    expect(entry.progress, closeTo(0.35, 0.01));
    expect(entry.hasPosition, isTrue);
  });

  test('opening again starts from the minute it was left at', () async {
    await history.record(film('a'));
    await history.updatePosition('a', const Duration(minutes: 30));

    // A new launch: a fresh notifier reads the same store.
    history.dispose();
    history = WatchHistoryNotifier(cloud: false);
    await history.ready;
    expect(history.state.single.position, const Duration(minutes: 30));

    // And a title the resume store knows is recorded with its minute.
    await ResumeStore.save('c', const Duration(minutes: 5));
    await history.record(film('c'));
    expect(history.state.first.position, const Duration(minutes: 5));
  });

  test('a series is one entry, on the episode being watched', () async {
    const ep1 = CinemanaEpisode(id: 'e1', episodeNumber: '1', seasonNumber: '2', arTitle: '', enTitle: '');
    const ep2 = CinemanaEpisode(id: 'e2', episodeNumber: '2', seasonNumber: '2', arTitle: '', enTitle: '');
    await history.record(film('show', kind: '2'), episode: ep1);
    await history.updatePosition('e1', const Duration(minutes: 20));
    await history.record(film('show', kind: '2'), episode: ep2);

    expect(history.state, hasLength(1));
    final entry = history.state.single;
    expect(entry.videoId, 'e2');
    expect(entry.episodeLabel, 'الموسم 2 · الحلقة 2');
    expect(entry.position, Duration.zero, reason: 'a new episode starts from its own beginning');
  });

  test('the page shows the last ten; a search looks through everything', () async {
    for (var i = 0; i < 15; i++) {
      await history.record(film('f$i', ar: 'عنوان $i', en: 'Title $i'));
    }
    expect(history.state.length, 15);
    expect(history.state.take(WatchHistoryNotifier.shown).length, 10);
    expect(history.state.first.item.id, 'f14');

    final hits = history.state.where((e) => e.matches('Title 1')).map((e) => e.item.id).toList();
    expect(hits, containsAll(['f1', 'f10', 'f14']));
    expect(history.state.where((e) => e.matches('عنوان 3')).single.item.id, 'f3');
  });

  test('removing and clearing', () async {
    await history.record(film('a'));
    await history.record(film('b'));
    await history.remove('a');
    expect(history.state.map((e) => e.item.id), ['b']);
    await history.clear();
    expect(history.state, isEmpty);
  });

  test('an entry survives the trip through json', () {
    final entry = WatchHistoryEntry(
      item: film('x', ar: 'عنوان', en: 'Title'),
      videoId: 'x',
      episodeLabel: 'الحلقة 3',
      position: const Duration(minutes: 7),
      duration: const Duration(minutes: 90),
      watchedAt: DateTime(2026, 9, 23, 12, 0),
    );
    final back = WatchHistoryEntry.fromJson(entry.toJson())!;
    expect(back.item.id, 'x');
    expect(back.item.arTitle, 'عنوان');
    expect(back.videoId, 'x');
    expect(back.episodeLabel, 'الحلقة 3');
    expect(back.position, const Duration(minutes: 7));
    expect(back.duration, const Duration(minutes: 90));
    expect(back.watchedAt, DateTime(2026, 9, 23, 12, 0));
  });
  test('an item with no id is ignored', () async {
    await history.record(film(''));
    expect(history.state, isEmpty);
  });

  test('the list is capped, dropping the oldest', () async {
    for (var i = 0; i < WatchHistoryNotifier.maxEntries + 5; i++) {
      await history.record(film('f$i'));
    }
    expect(history.state.length, WatchHistoryNotifier.maxEntries);
    expect(history.state.first.item.id, 'f${WatchHistoryNotifier.maxEntries + 4}');
    expect(history.state.any((e) => e.item.id == 'f0'), isFalse);
  });

  test('a corrupt store is ignored and the history starts empty', () async {
    SharedPreferences.setMockInitialValues({'watch_history_v2': 'not json at all'});
    history.dispose();
    history = WatchHistoryNotifier(cloud: false);
    await history.ready;
    expect(history.state, isEmpty);
    await history.record(film('a'));
    expect(history.state.single.item.id, 'a');
  });

  test('the old list, from before minutes were kept, is carried over', () async {
    SharedPreferences.setMockInitialValues({
      'watch_history_v1': '[{"nb":"old1","ar_title":"قديم","en_title":"Old","kind":"1","year":"2020"}]',
    });
    history.dispose();
    history = WatchHistoryNotifier(cloud: false);
    await history.ready;
    expect(history.state.map((e) => e.item.id), ['old1']);
    expect(history.state.single.hasPosition, isFalse);
  });
}

