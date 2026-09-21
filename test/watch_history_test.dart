import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/history/presentation/providers/watch_history_provider.dart';

CinemanaItem _item(String id, {String kind = '1', String? backdrop}) => CinemanaItem(
      id: id,
      arTitle: 'عنوان $id',
      enTitle: 'Title $id',
      stars: '7.5',
      year: '2021',
      kind: kind,
      arContent: 'نبذة',
      enContent: 'Plot',
      imgUrl: 'https://img.test/$id/poster.jpg',
      imgThumbUrl: 'https://img.test/$id/thumb.jpg',
      imgMediumUrl: 'https://img.test/$id/medium.jpg',
      backdropUrl: backdrop,
      categories: const ['دراما', 'إثارة'],
      categoriesEn: const ['Drama', 'Thriller'],
      season: '3',
      episodeNummer: '12',
      itemDate: '2021-05-01',
      mDate: '2024-01-02',
    );

/// A fresh container whose history has finished loading from the mock store.
Future<(ProviderContainer, WatchHistoryNotifier)> _open() async {
  final container = ProviderContainer();
  final notifier = container.read(watchHistoryProvider.notifier);
  await notifier.ready;
  return (container, notifier);
}

List<String> _ids(ProviderContainer c) => c.read(watchHistoryProvider).map((e) => e.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty when nothing was saved', () async {
    final (container, _) = await _open();
    addTearDown(container.dispose);
    expect(container.read(watchHistoryProvider), isEmpty);
  });

  test('record puts the newest first and de-duplicates by id', () async {
    final (container, notifier) = await _open();
    addTearDown(container.dispose);

    await notifier.record(_item('a'));
    await notifier.record(_item('b'));
    await notifier.record(_item('c'));
    expect(_ids(container), ['c', 'b', 'a']);

    // Opening "a" again moves it to the front instead of adding a copy.
    await notifier.record(_item('a'));
    expect(_ids(container), ['a', 'c', 'b']);
    expect(container.read(watchHistoryProvider).where((e) => e.id == 'a').length, 1);
  });

  test('an item with no id is ignored', () async {
    final (container, notifier) = await _open();
    addTearDown(container.dispose);

    await notifier.record(_item(''));
    expect(container.read(watchHistoryProvider), isEmpty);
  });

  test('the list is capped at maxEntries, dropping the oldest', () async {
    final (container, notifier) = await _open();
    addTearDown(container.dispose);

    const extra = 10;
    for (var i = 0; i < WatchHistoryNotifier.maxEntries + extra; i++) {
      await notifier.record(_item('t$i'));
    }
    final ids = _ids(container);
    expect(WatchHistoryNotifier.maxEntries, 60);
    expect(ids.length, WatchHistoryNotifier.maxEntries);
    expect(ids.first, 't${WatchHistoryNotifier.maxEntries + extra - 1}');
    expect(ids.last, 't$extra');
    expect(ids, isNot(contains('t0')));
  });

  test('remove takes out one entry and clear empties the list', () async {
    final (container, notifier) = await _open();
    addTearDown(container.dispose);

    await notifier.record(_item('a'));
    await notifier.record(_item('b'));
    await notifier.record(_item('c'));

    await notifier.remove('b');
    expect(_ids(container), ['c', 'a']);

    // Removing something that is not there changes nothing.
    await notifier.remove('zzz');
    expect(_ids(container), ['c', 'a']);

    await notifier.clear();
    expect(container.read(watchHistoryProvider), isEmpty);
  });

  test('persists across instances via SharedPreferences, newest first', () async {
    final (first, notifier) = await _open();
    await notifier.record(_item('movie'));
    await notifier.record(_item('show', kind: '2'));
    first.dispose();

    final (second, _) = await _open();
    addTearDown(second.dispose);
    expect(_ids(second), ['show', 'movie']);
  });

  test('removal and clearing are persisted too', () async {
    final (first, notifier) = await _open();
    await notifier.record(_item('a'));
    await notifier.record(_item('b'));
    await notifier.remove('a');
    first.dispose();

    final (second, notifier2) = await _open();
    expect(_ids(second), ['b']);
    await notifier2.clear();
    second.dispose();

    final (third, _) = await _open();
    addTearDown(third.dispose);
    expect(third.read(watchHistoryProvider), isEmpty);
  });

  test('every field the history screen shows round-trips through storage', () async {
    final (first, notifier) = await _open();
    await notifier.record(_item('show', kind: '2', backdrop: 'https://img.test/show/cover.jpg'));
    await notifier.record(_item('movie'));
    first.dispose();

    final (second, _) = await _open();
    addTearDown(second.dispose);
    final items = second.read(watchHistoryProvider);
    expect(items.length, 2);

    final show = items.firstWhere((e) => e.id == 'show');
    expect(show.displayTitle, 'عنوان show');
    expect(show.arTitle, 'عنوان show');
    expect(show.enTitle, 'Title show');
    expect(show.year, '2021');
    expect(show.stars, '7.5');
    expect(show.kind, '2');
    expect(show.isSeries, isTrue);
    expect(show.arContent, 'نبذة');
    expect(show.enContent, 'Plot');
    expect(show.imgUrl, 'https://img.test/show/poster.jpg');
    expect(show.imgThumbUrl, 'https://img.test/show/thumb.jpg');
    expect(show.imgMediumUrl, 'https://img.test/show/medium.jpg');
    expect(show.bestPosterUrl, 'https://img.test/show/poster.jpg');
    expect(show.cardImageUrl, 'https://img.test/show/medium.jpg');
    // The backdrop is not part of toJson; the history stores it itself.
    expect(show.backdropUrl, 'https://img.test/show/cover.jpg');
    expect(show.bestBackdropUrl, 'https://img.test/show/cover.jpg');
    expect(show.categories, ['دراما', 'إثارة']);
    expect(show.categoriesEn, ['Drama', 'Thriller']);
    expect(show.season, '3');
    expect(show.episodeNummer, '12');
    expect(show.itemDate, '2021-05-01');
    expect(show.mDate, '2024-01-02');

    final movie = items.firstWhere((e) => e.id == 'movie');
    expect(movie.isSeries, isFalse);
    // No backdrop stored: the poster stands in, as it does for API payloads.
    expect(movie.backdropUrl, 'https://img.test/movie/poster.jpg');
    expect(movie.bestBackdropUrl, 'https://img.test/movie/poster.jpg');
  });

  test('a corrupt store is ignored and the history starts empty', () async {
    SharedPreferences.setMockInitialValues({'watch_history_v1': '{not json'});
    final (container, notifier) = await _open();
    addTearDown(container.dispose);
    expect(container.read(watchHistoryProvider), isEmpty);

    // ...and it is usable afterwards.
    await notifier.record(_item('a'));
    expect(_ids(container), ['a']);
  });

  test('a write issued before the load finishes keeps the saved entries', () async {
    // Seed the store with an older history through a first instance.
    final (first, seed) = await _open();
    await seed.record(_item('old'));
    first.dispose();

    // The second instance is written to immediately, before `ready`.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(watchHistoryProvider.notifier);
    await notifier.record(_item('new'));
    expect(_ids(container), ['new', 'old']);
  });
}
