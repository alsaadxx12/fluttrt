import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/phone_normalizer.dart';
import '../models/user_profile.dart';

class AuthService {
  final SupabaseClient _client;

  AuthService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isAuthenticated => currentSession != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Creates a new user account with phone and password (NO OTP, NO SMS)
  Future<UserProfile> signUpWithPhoneAndPassword({
    required String fullName,
    required String rawPhone,
    required String password,
  }) async {
    final normalizedPhone = PhoneNormalizer.normalize(rawPhone);
    if (!PhoneNormalizer.isValid(normalizedPhone)) {
      throw const AuthCustomException('يرجى إدخال رقم هاتف صالح.');
    }

    if (password.length < 6) {
      throw const AuthCustomException('كلمة المرور يجب ألا تقل عن 6 أحرف أو أرقام.');
    }

    final authEmail = PhoneNormalizer.toAuthEmail(normalizedPhone);

    try {
      final res = await _client.auth.signUp(
        email: authEmail,
        password: password,
        data: {
          'full_name': fullName.trim(),
          'phone': normalizedPhone,
        },
      );

      final user = res.user;
      if (user == null) {
        throw const AuthCustomException('تعذر إنشاء الحساب. حاول مرة أخرى.');
      }

      // Ensure profile row exists in case trigger is pending
      try {
        await _client.from('profiles').upsert({
          'id': user.id,
          'full_name': fullName.trim(),
          'phone': normalizedPhone,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Profile upsert note: $e');
      }

      return UserProfile(
        id: user.id,
        fullName: fullName.trim(),
        phone: normalizedPhone,
        createdAt: DateTime.now(),
      );
    } on AuthException catch (e) {
      debugPrint('Supabase AuthException: ${e.message} (${e.statusCode})');
      if (e.message.toLowerCase().contains('already registered') ||
          e.message.toLowerCase().contains('user already exists')) {
        throw const AuthCustomException('رقم الهاتف مستخدم بالفعل. يرجى تسجيل الدخول.');
      }
      throw AuthCustomException(_friendlyAuthError(e.message));
    } catch (e) {
      debugPrint('Unexpected signup error: $e');
      if (e is AuthCustomException) rethrow;
      throw const AuthCustomException('تعذر الاتصال بالخادم. يرجى التحقق من اتصالك والمحاولة مجددًا.');
    }
  }

  /// Signs in an existing user using phone and password
  Future<UserProfile> signInWithPhoneAndPassword({
    required String rawPhone,
    required String password,
  }) async {
    final normalizedPhone = PhoneNormalizer.normalize(rawPhone);
    if (!PhoneNormalizer.isValid(normalizedPhone)) {
      throw const AuthCustomException('يرجى إدخال رقم هاتف صالح.');
    }

    final authEmail = PhoneNormalizer.toAuthEmail(normalizedPhone);

    try {
      final res = await _client.auth.signInWithPassword(
        email: authEmail,
        password: password,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthCustomException('تعذر تسجيل الدخول. حاول مرة أخرى.');
      }

      return await fetchCurrentProfile();
    } on AuthException catch (e) {
      debugPrint('Supabase signIn AuthException: ${e.message}');
      if (e.message.toLowerCase().contains('invalid login credentials') ||
          e.message.toLowerCase().contains('invalid credentials')) {
        throw const AuthCustomException('رقم الهاتف أو كلمة المرور غير صحيحة.');
      }
      throw AuthCustomException(_friendlyAuthError(e.message));
    } catch (e) {
      debugPrint('Unexpected login error: $e');
      if (e is AuthCustomException) rethrow;
      throw const AuthCustomException('تعذر الاتصال بالخادم. يرجى التحقق من اتصالك والمحاولة مجددًا.');
    }
  }

  /// Fetches the profile of the currently signed-in user
  Future<UserProfile> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthCustomException('المستخدم غير مسجل الدخول.');
    }

    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        return UserProfile.fromJson(data);
      }

      // Fallback from user metadata if table query was empty
      final metadata = user.userMetadata ?? {};
      final profile = UserProfile(
        id: user.id,
        fullName: metadata['full_name'] as String? ?? 'مستخدم CineBall',
        phone: metadata['phone'] as String? ?? '',
        createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
      );

      // Attempt upserting to table
      try {
        await _client.from('profiles').upsert(profile.toJson());
      } catch (_) {}

      return profile;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      final metadata = user.userMetadata ?? {};
      return UserProfile(
        id: user.id,
        fullName: metadata['full_name'] as String? ?? 'مستخدم CineBall',
        phone: metadata['phone'] as String? ?? '',
        createdAt: DateTime.now(),
      );
    }
  }

  /// Signs out and destroys the local session
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('SignOut error: $e');
    }
  }

  String _friendlyAuthError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials') || lower.contains('invalid_credentials')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    }
    if (lower.contains('user already registered') || lower.contains('already exists')) {
      return 'رقم الهاتف مسجل مسبقًا.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'تعذر الاتصال بالخادم. حاول مرة أخرى.';
    }
    if (lower.contains('rate limit')) {
      return 'تم تجاوز الحد المسموح من المحاولات. يرجى الانتظار قليلاً.';
    }
    return 'حدث خطأ أثناء المصادقة. حاول مجددًا.';
  }
}

class AuthCustomException implements Exception {
  final String message;
  const AuthCustomException(this.message);

  @override
  String toString() => message;
}
