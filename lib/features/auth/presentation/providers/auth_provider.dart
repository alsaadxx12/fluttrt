import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/user_profile.dart';
import '../../data/services/auth_service.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  // Triggers update on auth state change
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).currentUser;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

class UserProfileStateNotifier extends AsyncNotifier<UserProfile?> {
  @override
  FutureOr<UserProfile?> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return null;

    final authService = ref.read(authServiceProvider);
    try {
      return await authService.fetchCurrentProfile();
    } catch (_) {
      return null;
    }
  }

  Future<UserProfile> login({
    required String phone,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final authService = ref.read(authServiceProvider);
      final profile = await authService.signInWithPhoneAndPassword(
        rawPhone: phone,
        password: password,
      );
      state = AsyncValue.data(profile);
      // Immediately refresh subscription status
      ref.read(sportsSubscriptionProvider.notifier).refresh();
      return profile;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<UserProfile> register({
    required String fullName,
    required String phone,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final authService = ref.read(authServiceProvider);
      final profile = await authService.signUpWithPhoneAndPassword(
        fullName: fullName,
        rawPhone: phone,
        password: password,
      );
      state = AsyncValue.data(profile);
      // Refresh subscription (initial state: inactive)
      ref.read(sportsSubscriptionProvider.notifier).refresh();
      return profile;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> logout() async {
    final authService = ref.read(authServiceProvider);
    await authService.signOut();
    state = const AsyncValue.data(null);
    // Reset sports subscription state to inactive
    ref.read(sportsSubscriptionProvider.notifier).reset();
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final authService = ref.read(authServiceProvider);
      return await authService.fetchCurrentProfile();
    });
  }
}

final userProfileProvider =
    AsyncNotifierProvider<UserProfileStateNotifier, UserProfile?>(
  UserProfileStateNotifier.new,
);
