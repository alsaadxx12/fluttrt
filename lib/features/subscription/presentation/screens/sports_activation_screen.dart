import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_palette.dart';
import '../../../../core/constants/app_theme.dart';
import '../providers/subscription_provider.dart';

class SportsActivationScreen extends ConsumerStatefulWidget {
  const SportsActivationScreen({super.key});

  @override
  ConsumerState<SportsActivationScreen> createState() =>
      _SportsActivationScreenState();
}

class _SportsActivationScreenState
    extends ConsumerState<SportsActivationScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null && data!.text!.trim().isNotEmpty) {
        setState(() {
          _codeController.text = data.text!.trim().toUpperCase();
          _errorMessage = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp() async {
    const phone = '9647714289278';
    final message = Uri.encodeComponent(
        'مرحباً، أود الحصول على كود تفعيل لقسم المباريات في تطبيق CineBall.');
    final url = Uri.parse('https://wa.me/$phone?text=$message');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
    }
  }

  Future<void> _handleActivation() async {
    final rawCode = _codeController.text.trim();
    if (rawCode.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال كود التفعيل.';
      });
      return;
    }

    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(sportsSubscriptionProvider.notifier)
          .redeem(rawCode);

      if (!mounted) return;

      if (result.success) {
        setState(() => _isLoading = false);
        _showSuccessDialog(result.expiresAt);
      } else {
        setState(() {
          _errorMessage = result.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر الاتصال بالخادم. حاول مرة أخرى.';
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog(DateTime? expiresAt) {
    final formattedDate = expiresAt != null
        ? intl.DateFormat('yyyy/MM/dd').format(expiresAt)
        : '30 يوماً من اليوم';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor:
              isDark ? AppColors.darkCard : AppColors.lightCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.successContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.success, width: 2),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'تم التفعيل بنجاح',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'تم فتح قسم المباريات بالكامل!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'الاشتراك صالح حتى: $formattedDate',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF374151),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    // Replace activation screen with sports screen
                    context.pushReplacement('/sports');
                  },
                  child: const Text(
                    'الانتقال إلى المباريات',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Lock / Sports Graphic
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryContainer,
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.35),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.sports_soccer_rounded,
                              size: 48,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkCard
                                  : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'فعّل قسم المباريات',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.primary.withOpacity(0.12)
                          : const Color(0xFFFEF2F2),
                      borderRadius:
                          BorderRadius.circular(AppTheme.borderRadius),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.local_offer_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'سعر الاشتراك الشهري 5 آلاف دينار فقط',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.borderRadius),
                        border:
                            Border.all(color: AppColors.error.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Activation Code Input Box
                  Text(
                    'كود التفعيل',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeController,
                    enabled: !_isLoading,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: 'CINE-XXXX-XXXX',
                      hintStyle: TextStyle(
                        letterSpacing: 1.5,
                        color: isDark
                            ? Colors.white24
                            : const Color(0xFF9CA3AF),
                      ),
                      prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste_rounded, size: 20),
                        tooltip: 'لصق الكود',
                        onPressed: _isLoading ? null : _pasteFromClipboard,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withOpacity(0.04)
                          : const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.borderRadius),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.borderRadius),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.borderRadius),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.8),
                      ),
                    ),
                    onSubmitted: (_) => _handleActivation(),
                  ),
                  const SizedBox(height: 22),

                  // Activate Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleActivation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.borderRadius),
                        ),
                      ),
                      child: _isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'جارٍ التحقق من الكود...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'تفعيل الاشتراك',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Divider with "أو"
                  Row(
                    children: [
                      Expanded(child: Divider(color: palette.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'أو',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: palette.border)),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // WhatsApp Contact Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _openWhatsApp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.borderRadius),
                        ),
                      ),
                      icon: const Icon(
                        Icons.chat_bubble_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'طلب كود التفعيل عبر واتساب',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
