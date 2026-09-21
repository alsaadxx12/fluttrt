import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../subscription/data/models/subscription_plan.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

class SubscriptionPlansShowcase extends ConsumerWidget {
  const SubscriptionPlansShowcase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUnlocked = ref.watch(isSportsUnlockedProvider);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.card_membership_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'أنواع الاشتراكات',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primary.withOpacity(0.75),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'باقات المباريات',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اختر الباقة المناسبة لتفعيل قسم المباريات والبث المباشر',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/sports-activation'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'تفعيل كود',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios_rounded, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Horizontal scroll of plan cards
          SizedBox(
            height: 195,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: SubscriptionPlan.defaultPlans.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final plan = SubscriptionPlan.defaultPlans[index];
                return _PlanCard(plan: plan, isDark: isDark);
              },
            ),
          ),

          // Subscribed badge
          if (isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.successContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.success.withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'اشتراكك في قسم المباريات فعال حالياً. يمكنك تمديد الاشتراك بأي وقت.',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isDark;

  const _PlanCard({required this.plan, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final borderColor = plan.isBestValue
        ? const Color(0xFFFFD700).withOpacity(0.7)
        : plan.isPopular
            ? AppColors.primary.withOpacity(0.6)
            : (isDark
                ? Colors.white.withOpacity(0.12)
                : Colors.black.withOpacity(0.08));

    final cardBg = isDark ? AppColors.darkCard : Colors.white;

    return Container(
      width: 155,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: borderColor,
            width: plan.isPopular || plan.isBestValue ? 1.8 : 1),
        boxShadow: [
          BoxShadow(
            color: plan.isPopular
                ? AppColors.primary.withOpacity(0.15)
                : plan.isBestValue
                    ? const Color(0xFFFFD700).withOpacity(0.12)
                    : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Plan title
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 2),
                Text(
                  plan.durationText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),

                const Spacer(),

                // Price display
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.priceText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: plan.isPopular
                              ? AppColors.primary
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // WhatsApp Action Button
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: () =>
                        SubscriptionPlan.openWhatsAppSales(plan: plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'طلب الكود',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Top Badge
          if (plan.badge != null)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: plan.isBestValue
                      ? const Color(0xFFFFD700)
                      : (plan.isPopular
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white.withOpacity(0.15)
                              : Colors.grey.shade300)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.badge!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: plan.isBestValue
                        ? Colors.black87
                        : (plan.isPopular
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
