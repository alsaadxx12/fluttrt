import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sports_subscription.dart';
import '../../data/services/subscription_service.dart';

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

class SportsSubscriptionNotifier extends AsyncNotifier<SportsSubscription> {
  @override
  FutureOr<SportsSubscription> build() async {
    final service = ref.read(subscriptionServiceProvider);
    return await service.fetchSubscriptionStatus();
  }

  /// Forces an update of the subscription status from Supabase
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(subscriptionServiceProvider);
      return await service.fetchSubscriptionStatus();
    });
  }

  /// Resets the subscription state to inactive (e.g. on logout)
  void reset() {
    state = AsyncValue.data(SportsSubscription.inactive());
  }

  /// Redeems an activation code and refreshes state if valid
  Future<RedemptionResult> redeem(String code) async {
    final service = ref.read(subscriptionServiceProvider);
    final result = await service.redeemActivationCode(code);

    if (result.success) {
      // Refresh current subscription state from server
      await refresh();
    }

    return result;
  }
}

final sportsSubscriptionProvider =
    AsyncNotifierProvider<SportsSubscriptionNotifier, SportsSubscription>(
  SportsSubscriptionNotifier.new,
);

/// Helper provider returning whether the sports section is currently unlocked
final isSportsUnlockedProvider = Provider<bool>((ref) {
  final sub = ref.watch(sportsSubscriptionProvider).valueOrNull;
  return sub?.isUnlocked ?? false;
});

/// Lifecycle observer to re-validate subscription whenever app resumes from background
class SubscriptionLifecycleObserver with WidgetsBindingObserver {
  final WidgetRef ref;
  SubscriptionLifecycleObserver(this.ref);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(sportsSubscriptionProvider.notifier).refresh();
    }
  }
}
