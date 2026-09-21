import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionPlan {
  final String id;
  final String title;
  final String durationText;
  final int months;
  final int days;
  final int price;
  final String priceText;
  final String? badge;
  final bool isPopular;
  final bool isBestValue;

  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.durationText,
    required this.months,
    required this.days,
    required this.price,
    required this.priceText,
    this.badge,
    this.isPopular = false,
    this.isBestValue = false,
  });

  static const List<SubscriptionPlan> defaultPlans = [
    SubscriptionPlan(
      id: '1m',
      title: 'شهر',
      durationText: '30 يوماً',
      months: 1,
      days: 30,
      price: 5000,
      priceText: '5,000 دينار',
      badge: 'الأساسية',
    ),
    SubscriptionPlan(
      id: '2m',
      title: 'شهرين',
      durationText: '60 يوماً',
      months: 2,
      days: 60,
      price: 9000,
      priceText: '9,000 دينار',
      badge: 'توفير 1,000 د.ع',
    ),
    SubscriptionPlan(
      id: '3m',
      title: '3 أشهر',
      durationText: '90 يوماً',
      months: 3,
      days: 90,
      price: 14000,
      priceText: '14,000 دينار',
      badge: 'الأكثر طلباً ⭐',
      isPopular: true,
    ),
    SubscriptionPlan(
      id: '6m',
      title: '6 أشهر',
      durationText: '180 يوماً',
      months: 6,
      days: 180,
      price: 29000,
      priceText: '29,000 دينار',
      badge: 'نصف سنوي',
    ),
    SubscriptionPlan(
      id: '12m',
      title: '12 شهر',
      durationText: 'سنة كاملة (365 يوماً)',
      months: 12,
      days: 365,
      price: 49000,
      priceText: '49,000 دينار',
      badge: 'أفضل قيمة 👑',
      isBestValue: true,
    ),
  ];

  static Future<bool> openWhatsAppSales({
    SubscriptionPlan? plan,
    BuildContext? context,
  }) async {
    const rawPhone = '9647714289278';
    String message = 'مرحباً، أود الحصول على كود تفعيل لقسم المباريات';
    if (plan != null) {
      message =
          'مرحباً، أود تفعيل اشتراك المباريات: باقة (${plan.title} - ${plan.priceText})';
    }
    final encodedMessage = Uri.encodeComponent(message);

    // 1. Direct native WhatsApp intent scheme (bypasses browser, opens app directly)
    final nativeUri =
        Uri.parse('whatsapp://send?phone=$rawPhone&text=$encodedMessage');
    try {
      if (await launchUrl(nativeUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}

    // 2. Official wa.me shortlink
    final waMeUri =
        Uri.parse('https://wa.me/$rawPhone?text=$encodedMessage');
    try {
      if (await launchUrl(waMeUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}

    // 3. Fallback api.whatsapp.com
    final apiUri = Uri.parse(
        'https://api.whatsapp.com/send?phone=$rawPhone&text=$encodedMessage');
    try {
      if (await launchUrl(apiUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}

    // 4. Platform default fallback
    try {
      if (await launchUrl(waMeUri, mode: LaunchMode.platformDefault)) {
        return true;
      }
    } catch (_) {}

    // 5. If all fail, copy phone to clipboard and notify user
    await Clipboard.setData(const ClipboardData(text: '+9647714289278'));
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم نسخ رقم المبيعات (+9647714289278). يمكنك مراسلتهم مباشرة عبر واتساب.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Color(0xFF25D366),
          duration: Duration(seconds: 4),
        ),
      );
    }
    return false;
  }
}
