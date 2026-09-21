import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../data/models/subscription_plan.dart';

class SubscriptionPlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onWhatsApp;
  final bool isDark;
  final double width;

  const SubscriptionPlanCard({
    super.key,
    required this.plan,
    this.isSelected = false,
    this.onTap,
    this.onWhatsApp,
    required this.isDark,
    this.width = 138,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        // The card is the page, not a panel laid over it: the page's own
        // colour, no edge and no shadow. It used to sit on a lighter navy
        // gradient inside a hairline frame, which read as a box pasted on
        // top. What shows now is the red header, the mark and the price.
        color: AppPalette.of(context).bg,
        borderRadius: BorderRadius.circular(16),
        // A chosen plan is still marked - but by the brand ring alone.
        border: isSelected ? Border.all(color: AppColors.primary, width: 2) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ?? onWhatsApp,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Colored Top Header Bar (Brand Red Gradient)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isSelected
                          ? [
                              AppColors.primary,
                              const Color(0xFF8E040B),
                            ]
                          : (isDark
                              ? [
                                  AppColors.primary.withOpacity(0.95),
                                  const Color(0xFF7A040A),
                                ]
                              : [
                                  AppColors.primary,
                                  const Color(0xFFB80710),
                                ]),
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSelected) ...[
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          'اشتراك ${plan.title}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Middle Content with Centered App Logo and Centered Price
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Centered App Icon
                        Container(
                          width: 46,
                          height: 46,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [
                                      const Color(0xFF222B3D),
                                      const Color(0xFF181F2E),
                                    ]
                                  : [
                                      Colors.white,
                                      const Color(0xFFEFF3F8),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(isDark ? 0.2 : 0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/app_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.sports_soccer_rounded,
                                size: 26,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Centered Price
                        Text(
                          plan.priceText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Bottom WhatsApp Action Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: onWhatsApp ?? onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_rounded, size: 13),
                          SizedBox(width: 4),
                          Text(
                            'طلب الكود',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
