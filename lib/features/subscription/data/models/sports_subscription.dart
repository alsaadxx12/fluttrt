class SportsSubscription {
  final bool hasSubscription;
  final bool isActive;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int remainingDays;
  final DateTime? serverNow;

  const SportsSubscription({
    required this.hasSubscription,
    required this.isActive,
    required this.status,
    this.startedAt,
    this.expiresAt,
    this.remainingDays = 0,
    this.serverNow,
  });

  /// Default inactive / locked state
  factory SportsSubscription.inactive() {
    return const SportsSubscription(
      hasSubscription: false,
      isActive: false,
      status: 'none',
      remainingDays: 0,
    );
  }

  factory SportsSubscription.fromJson(Map<String, dynamic> json) {
    final hasSub = json['has_subscription'] == true;
    final isActive = json['is_active'] == true;
    final status = json['status'] as String? ?? (isActive ? 'active' : 'none');

    final startedAt = json['started_at'] != null
        ? DateTime.tryParse(json['started_at'].toString())
        : null;

    final expiresAt = json['expires_at'] != null
        ? DateTime.tryParse(json['expires_at'].toString())
        : null;

    final remainingDays = (json['remaining_days'] as num?)?.toInt() ?? 0;

    final serverNow = json['server_now'] != null
        ? DateTime.tryParse(json['server_now'].toString())
        : null;

    return SportsSubscription(
      hasSubscription: hasSub,
      isActive: isActive,
      status: status,
      startedAt: startedAt,
      expiresAt: expiresAt,
      remainingDays: remainingDays,
      serverNow: serverNow,
    );
  }

  bool get isUnlocked => isActive;

  SportsSubscription copyWith({
    bool? hasSubscription,
    bool? isActive,
    String? status,
    DateTime? startedAt,
    DateTime? expiresAt,
    int? remainingDays,
    DateTime? serverNow,
  }) {
    return SportsSubscription(
      hasSubscription: hasSubscription ?? this.hasSubscription,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      remainingDays: remainingDays ?? this.remainingDays,
      serverNow: serverNow ?? this.serverNow,
    );
  }
}

class RedemptionResult {
  final bool success;
  final String? error;
  final String message;
  final DateTime? expiresAt;
  final int? durationDays;

  const RedemptionResult({
    required this.success,
    this.error,
    required this.message,
    this.expiresAt,
    this.durationDays,
  });

  factory RedemptionResult.fromJson(Map<String, dynamic> json) {
    final success = json['success'] == true;
    final expiresAt = json['expires_at'] != null
        ? DateTime.tryParse(json['expires_at'].toString())
        : null;

    return RedemptionResult(
      success: success,
      error: json['error'] as String?,
      message: json['message'] as String? ??
          (success ? 'تم التفعيل بنجاح.' : 'فشل تفعيل الكود.'),
      expiresAt: expiresAt,
      durationDays: (json['duration_days'] as num?)?.toInt(),
    );
  }

  factory RedemptionResult.failure(String message, [String? errorCode]) {
    return RedemptionResult(
      success: false,
      error: errorCode,
      message: message,
    );
  }
}
