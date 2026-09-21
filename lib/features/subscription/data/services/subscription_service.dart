import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sports_subscription.dart';

class SubscriptionService {
  final SupabaseClient _client;

  SubscriptionService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  /// Fetches the current sports subscription status from the server
  Future<SportsSubscription> fetchSubscriptionStatus() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return SportsSubscription.inactive();
    }

    try {
      final response = await _client.rpc('get_user_sports_subscription');

      if (response != null && response is Map) {
        final map = Map<String, dynamic>.from(response);
        return SportsSubscription.fromJson(map);
      }

      // Fallback direct table query if RPC is not deployed yet
      final sub = await _client
          .from('sports_subscriptions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (sub != null) {
        final expiresAt = sub['expires_at'] != null
            ? DateTime.tryParse(sub['expires_at'].toString())
            : null;
        final now = DateTime.now();
        final isActive = sub['status'] == 'active' &&
            expiresAt != null &&
            expiresAt.isAfter(now);
        final remainingDays = isActive
            ? expiresAt.difference(now).inDays + 1
            : 0;

        return SportsSubscription(
          hasSubscription: true,
          isActive: isActive,
          status: isActive ? 'active' : 'expired',
          startedAt: sub['started_at'] != null
              ? DateTime.tryParse(sub['started_at'].toString())
              : null,
          expiresAt: expiresAt,
          remainingDays: remainingDays,
          serverNow: now,
        );
      }

      return SportsSubscription.inactive();
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
      return SportsSubscription.inactive();
    }
  }

  /// Redeems an activation code atomically on the server
  Future<RedemptionResult> redeemActivationCode(String rawCode) async {
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) {
      return RedemptionResult.failure(
        'يرجى إدخال كود التفعيل.',
        'EMPTY_CODE',
      );
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      return RedemptionResult.failure(
        'يرجى تسجيل الدخول أولاً لتفعيل الاشتراك.',
        'UNAUTHORIZED',
      );
    }

    try {
      final res = await _client.rpc(
        'redeem_activation_code',
        params: {'code_input': cleanCode},
      );

      if (res != null && res is Map) {
        final map = Map<String, dynamic>.from(res);
        return RedemptionResult.fromJson(map);
      }

      return RedemptionResult.failure('استجابة غير صالحة من الخادم.');
    } on PostgrestException catch (e) {
      debugPrint('Redemption PostgrestException: ${e.message}');
      return RedemptionResult.failure(_friendlyErrorMessage(e.message));
    } catch (e) {
      debugPrint('Redemption general error: $e');
      return RedemptionResult.failure(
        'تعذر الاتصال بالخادم. حاول مرة أخرى.',
        'NETWORK_ERROR',
      );
    }
  }

  String _friendlyErrorMessage(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('network') || lower.contains('socket') || lower.contains('connection')) {
      return 'تعذر الاتصال بالخادم. حاول مرة أخرى.';
    }
    return 'حدث خطأ أثناء معالجة كود التفعيل. حاول مجددًا.';
  }
}
