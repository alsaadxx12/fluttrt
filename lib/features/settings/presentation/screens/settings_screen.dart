import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_theme.dart';
import 'package:youtube_downloader/core/localization/app_localizations.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/auth/presentation/providers/auth_provider.dart';
import 'package:youtube_downloader/features/subscription/presentation/providers/subscription_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final subscription = ref.watch(sportsSubscriptionProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.navSettings,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Section 1: Account
                _buildSectionCard(
                  context,
                  title: 'الحساب',
                  icon: Icons.person_rounded,
                  isDark: isDark,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.person_rounded, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.fullName.isNotEmpty == true ? profile!.fullName : 'مستخدم CineBall',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                profile?.phone.isNotEmpty == true ? profile!.phone : 'رقم الهاتف غير محدد',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('تسجيل الخروج'),
                                content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج من حسابك؟'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('إلغاء'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('تسجيل الخروج'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && context.mounted) {
                              await ref.read(userProfileProvider.notifier).logout();
                              if (context.mounted) {
                                context.go('/login');
                              }
                            }
                          },
                          icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                          label: const Text('خروج', style: TextStyle(color: AppColors.error, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.error, width: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Section 2: Sports Subscription
                _buildSectionCard(
                  context,
                  title: 'اشتراك المباريات',
                  icon: Icons.sports_soccer_rounded,
                  isDark: isDark,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'حالة الاشتراك:',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (subscription?.isActive ?? false)
                                      ? AppColors.successContainer
                                      : AppColors.errorContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  (subscription?.isActive ?? false)
                                      ? 'فعال'
                                      : (subscription?.hasSubscription ?? false)
                                          ? 'منتهي'
                                          : 'غير مفعل',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: (subscription?.isActive ?? false)
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (subscription?.isActive ?? false) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ينتهي في:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                                Text(
                                  subscription?.expiresAt != null
                                      ? intl.DateFormat('yyyy/MM/dd').format(subscription!.expiresAt!)
                                      : '—',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'المدة المتبقية:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                                Text(
                                  '${subscription?.remainingDays ?? 0} يوماً',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                                ),
                              ),
                              onPressed: () => context.push('/sports-activation'),
                              icon: const Icon(Icons.vpn_key_rounded, size: 16),
                              label: Text(
                                (subscription?.isActive ?? false) ? 'إدخال كود جديد' : 'تجديد / تفعيل الاشتراك',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Section 2: Language
                _buildSectionCard(
                  context,
                  title: strings.languageSection,
                  icon: Icons.translate_rounded,
                  isDark: isDark,
                  children: [
                    Text(
                      strings.selectLanguage,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<AppLanguage>(
                      segments: const [
                        ButtonSegment(
                          value: AppLanguage.arabic,
                          label: Text('العربية (RTL)'),
                        ),
                        ButtonSegment(
                          value: AppLanguage.english,
                          label: Text('English (LTR)'),
                        ),
                      ],
                      selected: {settings.language},
                      onSelectionChanged: (set) =>
                          ref.read(settingsProvider.notifier).setLanguage(set.first),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Section 3: Download Directory
                _buildSectionCard(
                  context,
                  title: strings.downloadSection,
                  icon: Icons.folder_outlined,
                  isDark: isDark,
                  children: [
                    Text(
                      strings.defaultFolder,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSecondaryBg : AppColors.lightSecondaryBg,
                              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                              border: Border.all(
                                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                              ),
                            ),
                            child: Text(
                              settings.downloadFolder.isNotEmpty
                                  ? settings.downloadFolder
                                  : 'C:\\Users\\...\\Downloads',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () =>
                              ref.read(settingsProvider.notifier).pickDownloadFolder(),
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: Text(strings.changeFolder),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Options
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.maxConcurrentDownloads,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              '1 - 5',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        DropdownButton<int>(
                          value: settings.maxConcurrentDownloads,
                          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                          items: [1, 2, 3, 4, 5].map((val) {
                            return DropdownMenuItem(value: val, child: Text('$val'));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(settingsProvider.notifier).setMaxConcurrentDownloads(val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          strings.defaultVideoQuality,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        DropdownButton<String>(
                          value: settings.defaultVideoQuality,
                          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                          items: ['1080p', '720p', '480p', '360p'].map((val) {
                            return DropdownMenuItem(value: val, child: Text(val));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(settingsProvider.notifier).setDefaultVideoQuality(val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          strings.defaultAudioFormat,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        DropdownButton<String>(
                          value: settings.defaultAudioFormat,
                          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                          items: ['mp3', 'm4a'].map((val) {
                            return DropdownMenuItem(value: val, child: Text(val.toUpperCase()));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(settingsProvider.notifier).setDefaultAudioFormat(val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.askBeforeOverwrite,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      activeColor: AppColors.primary,
                      value: settings.askBeforeOverwrite,
                      onChanged: (val) =>
                          ref.read(settingsProvider.notifier).setAskBeforeOverwrite(val),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
