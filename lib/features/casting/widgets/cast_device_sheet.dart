import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../controllers/cast_controller.dart';
import '../models/cast_models.dart';
import '../services/cast_service.dart';

/// «البث إلى جهاز» — the sheet the Cast button opens.
///
/// A browser is paired by a code it shows, not found on the network, so the
/// list holds whatever is already paired and the way in is the button at the
/// foot. Chromecast devices will join the same list once the Cast SDK is
/// wired in; nothing here needs to change for that.
Future<void> showCastDeviceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _CastSheet(),
  );
}

class _CastSheet extends ConsumerWidget {
  const _CastSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final cast = ref.watch(castControllerProvider);

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.textFaint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.cast_rounded, color: Color(0xFFE50914), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'البث إلى جهاز',
                    style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (cast.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B75), size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cast.error!,
                        style: const TextStyle(color: Color(0xFFFF6B75), fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (cast.isConnected)
              _ConnectedRow(device: cast.device!)
            else
              _EmptyState(status: cast.status),
            const SizedBox(height: 6),
            Divider(color: p.border, height: 24),
            _PairButton(connected: cast.isConnected),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});
  final CastStatus status;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final busy = status == CastStatus.connecting || status == CastStatus.searching;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2),
            )
          else
            Icon(Icons.tv_off_rounded, color: p.textFaint, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              busy ? 'جارٍ الاتصال…' : 'لا توجد أجهزة متصلة',
              style: TextStyle(color: p.textMuted, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedRow extends ConsumerWidget {
  const _ConnectedRow({required this.device});
  final CastDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: Color(0x22E50914), shape: BoxShape.circle),
            child: const Icon(Icons.desktop_windows_rounded, color: Color(0xFFE50914), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('متصل بـ', style: TextStyle(color: p.textFaint, fontSize: 11.5)),
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(castControllerProvider.notifier).disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text(
              'قطع الاتصال',
              style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairButton extends StatelessWidget {
  const _PairButton({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: () => showCastPairingDialog(context),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(connected ? 'ربط جهاز آخر' : 'ربط كمبيوتر أو تلفاز'),
          style: TextButton.styleFrom(
            foregroundColor: p.text,
            backgroundColor: p.cardAlt,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// Asks for the six digits the receiver page is showing.
Future<void> showCastPairingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _PairingDialog(),
  );
}

class _PairingDialog extends ConsumerStatefulWidget {
  const _PairingDialog();

  @override
  ConsumerState<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends ConsumerState<_PairingDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(castControllerProvider.notifier).pairWithCode(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } on CastException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AlertDialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'ربط شاشة',
        style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'افتح cineball.netlify.app/cast على التلفاز أو الكمبيوتر، ثم أدخل الرمز الظاهر عليه.',
            style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              color: p.text,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle: TextStyle(color: p.textFaint, letterSpacing: 8),
              filled: true,
              fillColor: p.cardAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF6B75), fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: TextStyle(color: p.textMuted)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE50914),
            foregroundColor: Colors.white,
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('ربط'),
        ),
      ],
    );
  }
}
