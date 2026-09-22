import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/cinemana/data/models/cinemana_models.dart';
import 'package:youtube_downloader/features/cinemana/presentation/providers/cinemana_provider.dart';
import 'package:youtube_downloader/features/home/presentation/widgets/film_deck.dart';

CinemanaItem film(String id, String title, {String year = '2026', String stars = '7.4'}) => CinemanaItem(
      id: id,
      arTitle: title,
      enTitle: title,
      stars: stars,
      year: year,
      kind: '1',
      arContent: '',
      enContent: '',
      // Every artwork field set, so the card has a picture whichever one the
      // card chooses.
      imgUrl: 'https://img.example/$id.jpg',
      imgThumbUrl: 'https://img.example/$id-t.jpg',
      imgMediumUrl: 'https://img.example/$id-m.jpg',
      backdropUrl: 'https://img.example/$id-b.jpg',
    );

Widget _app(List<CinemanaItem> films) => ProviderScope(
      overrides: [homeLatestMoviesProvider.overrideWith((ref) async => films)],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Stack(children: [FilmDeck()])),
        ),
      ),
    );

void main() {
  testWidgets('only the tab shows until it is pulled out', (tester) async {
    await tester.pumpWidget(_app([film('1', 'فيلم أول'), film('2', 'فيلم ثان')]));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.movie_rounded), findsOneWidget, reason: 'the tab is on the rail');
    expect(find.text('فيلم أول'), findsNothing, reason: 'nothing is thrown in front of the viewer');
  });

  testWidgets('pulling the tab fans the newest films, and a tap outside puts them away', (tester) async {
    await tester.pumpWidget(_app([film('1', 'فيلم أول', year: '2026'), film('2', 'فيلم ثان')]));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.movie_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The card carries no name: the poster is the name. What it does carry
    // is what a picture cannot say for itself.
    expect(find.text('فيلم أول'), findsNothing,
        reason: 'the home page shows no titles on its cards');
    expect(find.text('2026'), findsWidgets, reason: 'the year is on the card');

    // The veil covers the screen; a tap in a corner away from the cards
    // closes the hand.
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2026'), findsNothing, reason: 'the hand is away');
    expect(find.byIcon(Icons.movie_rounded), findsOneWidget, reason: 'the tab is back on the rail');
  });

  testWidgets('no films means no tab at all', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.movie_rounded), findsNothing);
  });
}
