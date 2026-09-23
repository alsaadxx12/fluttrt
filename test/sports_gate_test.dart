import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/features/sports/data/models/sports_models.dart';
import 'package:youtube_downloader/features/sports/presentation/screens/sports_player_screen.dart';
import 'package:youtube_downloader/features/subscription/data/models/sports_subscription.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';

/// Stands in for the server: answers with whatever it was told, and counts
/// how often it was asked again.
class FakeSubscription extends SportsSubscriptionNotifier {
  FakeSubscription(this.answer, {this.slow = false});

  final SportsSubscription answer;
  final bool slow;
  int refreshes = 0;
  final Completer<void> _hold = Completer<void>();

  @override
  FutureOr<SportsSubscription> build() async {
    if (slow) await _hold.future;
    return answer;
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    if (slow) {
      state = const AsyncValue.loading();
      await _hold.future;
    }
    state = AsyncValue.data(answer);
  }
}

final match = SportMatchItem(
  id: 1,
  kickoffAt: '2026-09-22T20:00:00Z',
  status: 'live',
  home: TeamInfo(name: 'الزوراء'),
  away: TeamInfo(name: 'الجوية'),
);

Widget app(FakeSubscription fake) => ProviderScope(
      overrides: [sportsSubscriptionProvider.overrideWith(() => fake)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => SportsPlayerScreen(match: match)),
          GoRoute(
            path: '/sports-activation',
            builder: (_, __) => const Scaffold(body: Text('activation page')),
          ),
        ]),
      ),
    );

void main() {
  testWidgets('without a subscription the match is not shown; the joker is', (tester) async {
    final fake = FakeSubscription(SportsSubscription.inactive());
    await tester.pumpWidget(app(fake));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HouseNotice), findsOneWidget);
    expect(find.text(SportsPlayerScreen.lockedLine), findsOneWidget);
    expect(find.text(SportsPlayerScreen.lockedReason), findsOneWidget);
    expect(SportsPlayerScreen.lockedLine, contains('محد مات'));
    expect(SportsPlayerScreen.lockedReason, contains('ضامهن'));
    expect(tester.widget<HouseNotice>(find.byType(HouseNotice)).animation,
        'assets/animations/funny_joker.json');
    expect(fake.refreshes, 1, reason: 'the server is asked once more before anyone is turned away');
  });

  testWidgets('the button leads to the activation page', (tester) async {
    await tester.pumpWidget(app(FakeSubscription(SportsSubscription.inactive())));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text(SportsPlayerScreen.lockedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('activation page'), findsOneWidget);
    expect(find.byType(SportsPlayerScreen), findsNothing, reason: 'replaced, not stacked');
  });

  testWidgets('a tap elsewhere on the joker does nothing; only the button and the close mark act',
      (tester) async {
    await tester.pumpWidget(app(FakeSubscription(SportsSubscription.inactive())));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tapAt(const Offset(10, 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(SportsPlayerScreen.lockedLine), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget, reason: 'a way back');
  });

  testWidgets('while the answer is still coming, neither the match nor the joker is shown',
      (tester) async {
    await tester.pumpWidget(app(FakeSubscription(SportsSubscription.inactive(), slow: true)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(HouseNotice), findsNothing);
  });
}
