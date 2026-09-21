import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../subscription/data/models/subscription_plan.dart';
import '../../../subscription/presentation/widgets/subscription_plan_card.dart';

class SubscriptionPlansShowcase extends ConsumerWidget {
  const SubscriptionPlansShowcase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 0, bottom: 6),
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
                  child: Text(
                    'أنواع الاشتراكات',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
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

          const SizedBox(height: 10),

          // Two subscription plan cards side-by-side
          SizedBox(
            height: 172,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (int index = 0; index < SubscriptionPlan.defaultPlans.length; index++) ...[
                    if (index > 0) const SizedBox(width: 12),
                    Expanded(
                      child: SubscriptionPlanCard(
                        plan: SubscriptionPlan.defaultPlans[index],
                        isDark: isDark,
                        width: double.infinity,
                        onWhatsApp: () => SubscriptionPlan.openWhatsAppSales(
                          plan: SubscriptionPlan.defaultPlans[index],
                          context: context,
                        ),
                        onTap: () => context.push('/sports-activation'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
