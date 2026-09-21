import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';

import '../data/app_update_info.dart';
import '../data/update_service.dart';
import 'update_controller.dart';

/// Wraps the app (MaterialApp.router's `builder`). Starts the update check
/// in the background after the first frame, then shows the prompt over the
/// running app: a card for an optional update, a full screen for a forced
/// one.
///
/// The prompt is part of this widget's own tree rather than a `showDialog`
/// route: MaterialApp's builder sits above the Navigator, so a dialog route
/// pushed from here would have no Navigator to push onto.
class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, so the home page never waits for the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) ref.read(updateControllerProvider.notifier).checkForUpdate();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(updateControllerProvider.notifier).onResumed();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    if (!state.shouldPrompt) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (state.isForced) const _ForcedUpdateScreen() else const _UpdateCard(),
      ],
    );
  }
}

// ---------------------------------------------------------------- texts

String updateFailureMessage(UpdateFailure? f) {
  switch (f) {
    case UpdateFailure.noInternet:
      return 'لا يوجد اتصال بالإنترنت';
    case UpdateFailure.manifestUnavailable:
      return 'تعذّر الوصول إلى خادم التحديث';
    case UpdateFailure.manifestInvalid:
      return 'بيانات التحديث غير صالحة';
    case UpdateFailure.downloadFailed:
      return 'فشل تنزيل التحديث، تحقق من الاتصال ثم أعد المحاولة';
    case UpdateFailure.notEnoughSpace:
      return 'لا توجد مساحة كافية على الجهاز';
    case UpdateFailure.checksumMismatch:
      return 'الملف الذي تم تنزيله تالف أو غير مطابق، أعد المحاولة';
    case UpdateFailure.installPermissionDenied:
      return 'يجب السماح للتطبيق بتثبيت التحديثات';
    case UpdateFailure.installerFailed:
      return 'تعذّر فتح مثبّت التطبيقات';
    case null:
      return 'حدث خطأ غير متوقع';
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

// ----------------------------------------------------------- optional

/// An optional update: a card over a dimmed app, with "لاحقًا" to put it off.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final info = state.info;
    if (info == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final busy = state.status == UpdateStatus.downloading || state.status == UpdateStatus.installing;
    return Material(
      color: Colors.black.withOpacity(0.62),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141926) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: isDark ? null : palette.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.system_update_rounded, color: Color(0xFFE50914)),
                          const SizedBox(width: 8),
                          Text('يتوفر تحديث جديد',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _UpdateBody(state: state, info: info, isDark: isDark),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (!busy && state.status != UpdateStatus.error)
                            TextButton(
                              onPressed: ref.read(updateControllerProvider.notifier).dismiss,
                              child: Text('لاحقًا',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w700)),
                            )
                          else
                            const SizedBox.shrink(),
                          _PrimaryAction(state: state),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------- forced screen

/// A forced update: the app is unusable until it is installed. There is no
/// "later"; the back button closes the app, and the screen returns on the
/// next start.
class _ForcedUpdateScreen extends ConsumerWidget {
  const _ForcedUpdateScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final info = state.info;
    if (info == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: isDark ? const Color(0xFF07090E) : Colors.white,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.system_update_rounded, color: Color(0xFFE50914), size: 44),
                  ),
                  const SizedBox(height: 18),
                  Text('يتوفر تحديث جديد',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Text(
                    'هذا التحديث ضروري لمتابعة استخدام التطبيق',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5, color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 22),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141926) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : palette.border),
                      ),
                      child: _UpdateBody(state: state, info: info, isDark: isDark),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: SizedBox(width: double.infinity, height: 48, child: _PrimaryAction(state: state)),
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

// ---------------------------------------------------------- shared body

class _UpdateBody extends StatelessWidget {
  final UpdateState state;
  final AppUpdateInfo info;
  final bool isDark;
  const _UpdateBody({required this.state, required this.info, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final text = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? Colors.white60 : Colors.black54;
    final current = state.current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('الإصدار الحالي', current == null ? '-' : '${current.versionName} (${current.versionCode})', muted, text),
        const SizedBox(height: 6),
        _line('الإصدار الجديد', '${info.versionName} (${info.versionCode})', muted, const Color(0xFFE50914)),
        if (info.sizeBytes != null) ...[
          const SizedBox(height: 6),
          _line('الحجم', _mb(info.sizeBytes!), muted, text),
        ],
        if (info.notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('ما الجديد', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: text)),
          const SizedBox(height: 4),
          Text(info.notes, style: TextStyle(fontSize: 12.5, height: 1.5, color: muted)),
        ],
        if (state.status == UpdateStatus.downloading) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: state.total == null ? null : state.progress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white12 : const Color(0xFFE3E8F1),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFE50914)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            state.total == null
                ? 'جارٍ التنزيل… ${_mb(state.received)}'
                : 'جارٍ التنزيل… ${(state.progress * 100).round()}%  (${_mb(state.received)} / ${_mb(state.total!)})',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted),
          ),
        ],
        if (state.status == UpdateStatus.installing) ...[
          const SizedBox(height: 14),
          Row(children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE50914))),
            const SizedBox(width: 8),
            Text('جارٍ فتح المثبّت…', style: TextStyle(fontSize: 12.5, color: muted, fontWeight: FontWeight.w700)),
          ]),
        ],
        if (state.needsInstallPermission) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB800).withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'اكتمل التنزيل. لتثبيت التحديث اسمح للتطبيق بتثبيت التطبيقات من الإعدادات، ثم ارجع إلى هنا.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: text, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (state.status == UpdateStatus.error) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text(updateFailureMessage(state.failure),
                    style: TextStyle(fontSize: 12.5, color: text, fontWeight: FontWeight.w600))),
          ]),
        ],
      ],
    );
  }

  Widget _line(String k, String v, Color kc, Color vc) => Row(
        children: [
          Text('$k: ', style: TextStyle(fontSize: 13, color: kc, fontWeight: FontWeight.w700)),
          Flexible(
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: vc, fontWeight: FontWeight.w900))),
        ],
      );
}

class _PrimaryAction extends ConsumerWidget {
  final UpdateState state;
  const _PrimaryAction({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(updateControllerProvider.notifier);
    String label;
    VoidCallback? onTap;
    IconData icon = Icons.download_rounded;
    switch (state.status) {
      case UpdateStatus.downloading:
        label = 'إلغاء';
        icon = Icons.close_rounded;
        onTap = c.cancelDownload;
      case UpdateStatus.installing:
        label = 'جارٍ التثبيت…';
        onTap = null;
      case UpdateStatus.error:
        label = 'إعادة المحاولة';
        icon = Icons.refresh_rounded;
        onTap = c.retry;
      case UpdateStatus.downloadCompleted:
        if (state.needsInstallPermission) {
          label = 'فتح الإعدادات';
          icon = Icons.settings_rounded;
          onTap = c.requestInstallPermission;
        } else {
          label = 'تثبيت الآن';
          icon = Icons.install_mobile_rounded;
          onTap = c.install;
        }
      default:
        label = 'تحديث الآن';
        onTap = c.downloadAndInstall;
    }
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: state.status == UpdateStatus.downloading ? const Color(0xFF475569) : const Color(0xFFE50914),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }
}
