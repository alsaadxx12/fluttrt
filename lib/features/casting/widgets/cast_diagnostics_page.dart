import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../controllers/cast_controller.dart';
import '../models/cast_models.dart';
import '../services/cast_log.dart';
import '../services/local_network.dart';

/// «تشخيص البث»: what the casting code has been saying, read back on the
/// phone.
///
/// Reached by a long press on the cast button, not from any menu: it is
/// for the evening something does not play, and for nobody else. The top
/// answers the usual questions in a line each — which network, which
/// screen, how fast the link was, whether the set ever came for the film,
/// how long the first bytes took — and the log under it is the whole story
/// for whoever wants it, with a button to copy it out.
class CastDiagnosticsPage extends ConsumerWidget {
  const CastDiagnosticsPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const CastDiagnosticsPage()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final cast = ref.watch(castControllerProvider);
    final network = ref.watch(localNetworkProvider);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        title: Text('تشخيص البث',
            style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w900)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'نسخ السجل',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _report(cast, network)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('نُسخ التقرير'), behavior: SnackBarBehavior.floating),
                );
              }
            },
          ),
          const IconButton(
            tooltip: 'مسح السجل',
            icon: Icon(Icons.delete_sweep_rounded, size: 21),
            onPressed: CastLog.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: CastLog.revision,
        builder: (context, _, __) {
          final lines = CastLog.lines;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Fact(
                icon: Icons.wifi_rounded,
                label: 'الشبكة',
                value: network.when(
                  data: (s) => switch (s) {
                    LocalNetworkStatus.wifi => 'واي فاي — يمكن الوصول للتلفاز',
                    LocalNetworkStatus.cellularOnly => 'بيانات الجوال فقط — التلفاز غير قابل للوصول',
                    LocalNetworkStatus.offline => 'لا شبكة',
                  },
                  loading: () => '…',
                  error: (_, __) => 'تعذّر الفحص',
                ),
                warn: network.valueOrNull != null && network.valueOrNull != LocalNetworkStatus.wifi,
              ),
              _Fact(
                icon: Icons.tv_rounded,
                label: 'الجهاز',
                value: cast.device == null
                    ? 'غير متصل'
                    : '${cast.device!.name} · ${cast.status.name}'
                        '${cast.error != null ? ' · ${cast.error}' : ''}',
                warn: cast.error != null,
              ),
              _Fact(
                icon: Icons.speed_rounded,
                label: 'سرعة الإنترنت المقاسة',
                value: _after(CastLog.last('link '), 'link ') ?? 'لم تُقَس بعد (اختر «تلقائي» في الجودة)',
              ),
              _Fact(
                icon: Icons.timer_outlined,
                label: 'زمن التحضير',
                value: _after(CastLog.last('timings:'), 'timings:') ?? '—',
              ),
              _Fact(
                icon: Icons.download_rounded,
                label: 'هل طلب التلفاز الفيلم؟',
                value: CastLog.last('the television asked') == null
                    ? 'لا — لم يصل أي طلب من التلفاز إلى الهاتف'
                    : 'نعم (${CastLog.last('the television asked')!.clock})',
                warn: CastLog.last('the television asked') == null && cast.media != null,
              ),
              _Fact(
                icon: Icons.bolt_rounded,
                label: 'أول بايت خرج من الهاتف',
                value: _after(CastLog.last('first '), 'first ') ?? '—',
              ),
              _Fact(
                icon: Icons.play_circle_outline_rounded,
                label: 'التلفاز أبلغ أنه يعرض',
                value: CastLog.last('${cast.device?.name ?? ''} reports') == null
                    ? '—'
                    : CastLog.last('${cast.device?.name ?? ''} reports')!.text,
              ),
              const SizedBox(height: 16),
              Text('السجل (${lines.length})',
                  style: TextStyle(color: p.textMuted, fontSize: 12.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (lines.isEmpty)
                Text('لا شيء بعد — ابدأ بثًا ثم عد إلى هنا',
                    style: TextStyle(color: p.textFaint, fontSize: 12.5))
              else
                for (final line in lines.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${line.clock}  ${line.text}',
                        style: TextStyle(
                          color: line.text.contains('refused') ||
                                  line.text.contains('failed') ||
                                  line.text.contains('did not') ||
                                  line.text.contains('لم ')
                              ? const Color(0xFFFF6B75)
                              : p.textMuted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  static String? _after(CastLogLine? line, String prefix) {
    if (line == null) return null;
    final text = line.text;
    final at = text.indexOf(prefix);
    return at < 0 ? text : text.substring(at + prefix.length).trim();
  }

  static String _report(CastState cast, AsyncValue<LocalNetworkStatus> network) => [
        'CineBall cast report',
        'network: ${network.valueOrNull?.name ?? '?'}',
        'device: ${cast.device?.name ?? '-'} (${cast.device?.transport.name ?? '-'}) status=${cast.status.name}',
        'media: ${cast.media?.title ?? '-'} quality=${cast.media?.quality ?? '-'}',
        'error: ${cast.error ?? '-'}',
        '',
        CastLog.asText,
      ].join('\n');
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: warn ? const Color(0xFFFFB020) : p.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: p.textFaint, fontSize: 11.5)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: warn ? const Color(0xFFFFB020) : p.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
