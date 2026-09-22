import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../controllers/cast_controller.dart';
import '../controllers/cast_quality.dart';
import '../models/cast_models.dart';
import '../services/cast_service.dart';
import 'cast_scan_page.dart';

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
      // Named so a test can measure it: how tall this stands is the kind of
      // thing that looks right in the code and wrong on a phone.
      key: const ValueKey('cast-sheet'),
      // Half the screen: enough for the animation and a list of screens
      // under it, and no more.
      //
      // A minimum height was the wrong tool. The column inside fills what
      // it is given, and a modal sheet is given the whole screen to fill —
      // so «at least half» became «all of it», and the sheet climbed to the
      // top. A height says what it means.
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
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
            const SizedBox(height: 12),
            const _CastMark(),
            const SizedBox(height: 10),
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
              const Flexible(child: _TelevisionList()),
            const Spacer(),
            Divider(color: p.border, height: 20),
            _FootRow(connected: cast.isConnected),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// The televisions the Cast SDK can see, as they answer.
///
/// Discovery is live for as long as this is on screen, so the list fills in
/// rather than appearing all at once — a Chromecast can take a few seconds
/// to reply, and an empty box in the meantime reads as «none», which would
/// be a lie.
class _TelevisionList extends ConsumerWidget {
  const _TelevisionList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(castTelevisionsProvider).valueOrNull ?? const <CastDevice>[];
    if (found.isEmpty) {
      return _EmptyState(status: ref.watch(castControllerProvider).status);
    }

    return ConstrainedBox(
      // Enough for four, and scrollable past that, so a house full of
      // speakers cannot push the pairing button off the bottom.
      constraints: const BoxConstraints(maxHeight: 264),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: found.length,
        itemBuilder: (_, i) => _DeviceRow(device: found[i]),
      ),
    );
  }
}

class _DeviceRow extends ConsumerStatefulWidget {
  const _DeviceRow({required this.device});
  final CastDevice device;

  @override
  ConsumerState<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends ConsumerState<_DeviceRow> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await ref.read(castControllerProvider.notifier).connectTo(widget.device);
      if (mounted) Navigator.of(context).pop();
    } on CastException {
      // The sheet prints state.error at the top; leaving it open is what
      // lets the viewer read it and pick another device.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListTile(
      onTap: _busy ? null : _connect,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: p.cardAlt, shape: BoxShape.circle),
        child: Icon(
          // A television found over UPnP and a Chromecast are different
          // things behind the scenes, and the picture is the only hint the
          // viewer gets that the list holds both.
          widget.device.transport == CastTransport.dlna
              ? Icons.tv_rounded
              : Icons.cast_rounded,
          color: p.text,
          size: 21,
        ),
      ),
      title: Text(
        widget.device.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        widget.device.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: p.textFaint, fontSize: 11.5),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2),
            )
          : Icon(Icons.cast_rounded, color: p.textMuted, size: 20),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});
  final CastStatus status;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final connecting = status == CastStatus.connecting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connecting
                  ? 'جارٍ الاتصال…'
                  : 'جارٍ البحث عن شاشات على الشبكة…',
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

/// The animation at the head of the sheet.
///
/// It replaces an icon and the words «البث إلى جهاز». A sheet that has just
/// slid up from the cast button does not need to announce what it is, and
/// the animation says it better than a line of text — a screen with
/// something arriving at it.
class _CastMark extends StatelessWidget {
  const _CastMark();

  static const double _size = 185;

  @override
  Widget build(BuildContext context) {
    // Whoever has asked the system for less motion gets the still icon.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return const SizedBox(
        height: _size,
        child: Center(
          child: Icon(Icons.tv_rounded, color: Color(0xFFE50914), size: 72),
        ),
      );
    }

    return SizedBox(
      height: _size,
      child: Center(
        // On a light plate rather than straight onto the sheet.
        //
        // The Apple TV animation's shapes and strokes are dark / black, and on
        // a pitch-dark sheet they would be nearly invisible. A clean, subtle
        // light background plate brings out every line, wifi wave, and detail.
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF3F8),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE50914).withOpacity(0.16),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Lottie.asset(
            'assets/animations/apple_tv.json',
            repeat: true,
            fit: BoxFit.contain,
            // One asset failing is no reason for the sheet to arrive empty.
            errorBuilder: (_, __, ___) => const Icon(
              Icons.tv_rounded,
              color: Color(0xFFE50914),
              size: 68,
            ),
          ),
        ),
      ),
    );
  }
}

/// How sharp a picture to send.
///
/// It sits here rather than buried in settings because this is where the
/// decision is made — and because the honest default is not the highest
/// one, so anyone who wants 4K has to be able to find the switch.
class _QualityRow extends ConsumerWidget {
  const _QualityRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final quality = ref.watch(castQualityProvider);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 0),
      child: Row(
        children: [
          Icon(Icons.high_quality_rounded, color: p.textMuted, size: 19),
          const SizedBox(width: 10),
          Text('الجودة', style: TextStyle(color: p.textMuted, fontSize: 13.5)),
          const Spacer(),
          PopupMenuButton<CastQuality>(
            initialValue: quality,
            color: p.card,
            onSelected: (choice) =>
                ref.read(castQualityProvider.notifier).set(choice),
            itemBuilder: (context) => [
              for (final option in CastQuality.values)
                PopupMenuItem(
                  value: option,
                  child: Text(
                    '${option.label} · ${option.short}',
                    style: TextStyle(
                      color: option == quality ? const Color(0xFFE50914) : p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    quality.short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, color: p.textMuted, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The line at the foot: the quality on one side, pairing on the other.
///
/// Pairing used to be a full-width bar of its own, as heavy on the eye as
/// the list of screens above it — and it is the rarer of the two things
/// somebody opens this sheet to do. It is an icon now, at the end of a line
/// it shares.
class _FootRow extends StatelessWidget {
  const _FootRow({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      children: [
        const Expanded(child: _QualityRow()),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: Material(
            color: p.cardAlt,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showCastPairingDialog(context),
              child: Tooltip(
                message: connected ? 'ربط جهاز آخر' : 'ربط كمبيوتر أو تلفاز',
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Icons.add_rounded, color: p.text, size: 22),
                ),
              ),
            ),
          ),
        ),
      ],
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

  /// The camera route into the same pairing the keypad performs.
  ///
  /// The scanned digits are put in the field before they are used, so a code
  /// that turns out to be stale leaves the viewer looking at it, one tap from
  /// correcting it, rather than at an empty box and an error.
  Future<void> _scan() async {
    final code = await CastScanPage.open(context);
    if (code == null || !mounted) return;
    _controller.text = code;
    await _submit();
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
            'افتح cineball.netlify.app/cast على التلفاز أو الكمبيوتر، ثم امسح رمز QR الظاهر عليه.',
            style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text('مسح رمز QR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Divider(color: p.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'أو أدخل الرمز',
                  style: TextStyle(color: p.textFaint, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: p.border)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
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
