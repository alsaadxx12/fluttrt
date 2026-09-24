import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import '../controllers/cast_controller.dart';
import '../controllers/cast_quality.dart';
import '../models/cast_models.dart';
import '../services/cast_prefs.dart';
import '../services/cast_service.dart';
import '../services/local_network.dart';
import 'cast_diagnostics_page.dart';
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

class _CastSheet extends ConsumerStatefulWidget {
  const _CastSheet();

  @override
  ConsumerState<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends ConsumerState<_CastSheet> {
  // No connecting on its own: the sheet used to reach for last time's
  // screen the moment it opened, which got in the way of choosing another
  // and kept knocking at a set that was off. Last time's screen still sits
  // at the top of the list; a tap connects.

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final cast = ref.watch(castControllerProvider);
    final network = ref.watch(localNetworkProvider).valueOrNull;
    final networkAdvice = network == null ? null : LocalNetwork.advice(network);
    // A line of words under the animation costs height; the animation
    // gives some of its own up, so the list is never pushed off the foot.
    final hasLine =
        cast.error != null || cast.note != null || networkAdvice != null;

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
      // Half the screen: the animation strip, a line of words, and two or
      // three screens under it.
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: BoxDecoration(
        // The same colour as the bar under it, exactly: the two read as
        // one surface.
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            _CastMark(compact: hasLine),
            const SizedBox(height: 10),
            if (cast.error != null)
              _Line(
                icon: const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFFF6B75), size: 17),
                text: cast.error!,
                color: const Color(0xFFFF6B75),
              )
            // What is being done about a set that did not answer: «trying
            // again, 2 of 4». Not red — the attempt is still on.
            else if (cast.note != null)
              // Words only: the row of the screen being tried already turns
              // a spinner, and a second one here made two.
              _Line(
                icon: Icon(Icons.info_outline_rounded, color: p.textMuted, size: 16),
                text: cast.note!,
                color: p.textMuted,
              )
            // The network, checked before the search: a phone on mobile
            // data will never find a television, and a spinner that never
            // stops is not an explanation.
            else if (networkAdvice != null)
              _Line(
                icon: const Icon(Icons.wifi_off_rounded,
                    color: Color(0xFFFFB020), size: 17),
                text: networkAdvice,
                color: const Color(0xFFFFB020),
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

/// One line of words under the animation: an error, a note, a warning.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.color});
  final Widget icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// The televisions the Cast SDK can see, as they answer — with last time's
/// screen at the top whether or not it has answered yet.
///
/// Discovery is live for as long as this is on screen, so the list fills in
/// rather than appearing all at once — a Chromecast can take a few seconds
/// to reply, and an empty box in the meantime reads as «none», which would
/// be a lie.
class _TelevisionList extends ConsumerWidget {
  const _TelevisionList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found =
        ref.watch(castTelevisionsProvider).valueOrNull ?? const <CastDevice>[];
    final last = ref.watch(lastCastDeviceProvider).valueOrNull;
    final names = ref.watch(castDeviceNamesProvider).valueOrNull ??
        const <String, String>{};

    // Last time's screen first, then the rest as they were found. When it
    // has not answered yet it is listed anyway: a tap on it starts the
    // search-and-connect, the same as the automatic one.
    final rows = <CastDevice>[
      if (last != null)
        found.firstWhere((d) => d.id == last.id, orElse: () => last),
      for (final d in found)
        if (last == null || d.id != last.id) d,
    ];

    if (rows.isEmpty) {
      // Scrollable so that, on a short screen with a line of words under
      // the animation, the words never push this off the foot of the sheet.
      return SingleChildScrollView(
        child: _EmptyState(status: ref.watch(castControllerProvider).status),
      );
    }

    return ConstrainedBox(
      // Enough for four, and scrollable past that, so a house full of
      // speakers cannot push the pairing button off the bottom.
      constraints: const BoxConstraints(maxHeight: 264),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        itemBuilder: (_, i) => _DeviceRow(
          device: rows[i],
          isLast: last != null && rows[i].id == last.id,
          customName: names[rows[i].id],
          seen: found.any((d) => d.id == rows[i].id),
        ),
      ),
    );
  }
}

class _DeviceRow extends ConsumerStatefulWidget {
  const _DeviceRow({
    required this.device,
    this.isLast = false,
    this.customName,
    this.seen = true,
  });

  final CastDevice device;

  /// True for the screen used last time: it wears a badge and sits first.
  final bool isLast;

  /// What the viewer calls this screen, when they renamed it.
  final String? customName;

  /// Whether the search has heard from it this time.
  final bool seen;

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

  /// A long press renames the screen — «تلفاز الصالة» reads better than
  /// «[TV] Samsung 7 Series (55)» every evening.
  Future<void> _rename() async {
    final controller =
        TextEditingController(text: widget.customName ?? widget.device.name);
    final p = AppPalette.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('اسم الشاشة',
            style: TextStyle(
                color: p.text, fontSize: 16, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
              color: p.text, fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: widget.device.name,
            hintStyle: TextStyle(color: p.textFaint),
            filled: true,
            fillColor: p.cardAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text('الاسم الأصلي', style: TextStyle(color: p.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await CastPrefs.rename(widget.device.id, name);
    ref.invalidate(castDeviceNamesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final brand = CastBrand.of(widget.device);
    final title = widget.customName ?? widget.device.name;
    final connecting = _busy ||
        (widget.isLast &&
            ref.watch(castControllerProvider).status == CastStatus.connecting);

    return ListTile(
      onTap: connecting ? null : _connect,
      onLongPress: _rename,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: _BrandBadge(brand: brand, transport: widget.device.transport),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.text, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (widget.isLast) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x22E50914),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'آخر مرة',
                style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        widget.seen
            ? (widget.customName != null
                ? widget.device.name
                : widget.device.subtitle)
            : 'لم يظهر بعد — اضغط للبحث عنه والاتصال',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: p.textFaint, fontSize: 11.5),
      ),
      trailing: connecting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Color(0xFFE50914), strokeWidth: 2),
            )
          : Icon(Icons.cast_rounded, color: p.textMuted, size: 20),
    );
  }
}

/// The maker's mark beside a screen, so a room with a Samsung and an LG
/// can tell them apart at a glance.
///
/// A monogram in the brand's colour rather than its logo: the logos are
/// theirs, the colours are only colours. A screen whose maker is not
/// known gets the plain television icon.
class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.brand, required this.transport});
  final CastBrand brand;
  final CastTransport transport;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (brand == CastBrand.unknown) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: p.cardAlt, shape: BoxShape.circle),
        child: Icon(
          // A television found over UPnP and a Chromecast are different
          // things behind the scenes, and the picture is the only hint the
          // viewer gets that the list holds both.
          transport == CastTransport.dlna
              ? Icons.tv_rounded
              : Icons.cast_rounded,
          color: p.text,
          size: 21,
        ),
      );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Color(brand.color),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        brand.mark,
        style: TextStyle(
          color: Colors.white,
          fontSize: brand.mark.length > 3 ? 8.5 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// «Searching…» — and, when the search has gone on long enough on a wifi
/// that is up, the reason it usually finds nothing.
class _EmptyState extends ConsumerStatefulWidget {
  const _EmptyState({required this.status});
  final CastStatus status;

  @override
  ConsumerState<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends ConsumerState<_EmptyState> {
  /// After this long with nothing found, the router is the usual suspect.
  static const Duration _patience = Duration(seconds: 15);

  bool _longEnough = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _longEnough = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final connecting = widget.status == CastStatus.connecting;
    final onWifi =
        ref.watch(localNetworkProvider).valueOrNull == LocalNetworkStatus.wifi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Color(0xFFE50914), strokeWidth: 2),
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
          if (_longEnough && onWifi && !connecting)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                LocalNetwork.isolationAdvice,
                style: TextStyle(
                    color: Color(0xFFFFB020), fontSize: 12, height: 1.4),
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
    final names = ref.watch(castDeviceNamesProvider).valueOrNull ??
        const <String, String>{};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _BrandBadge(brand: CastBrand.of(device), transport: device.transport),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('متصل بـ',
                    style: TextStyle(color: p.textFaint, fontSize: 11.5)),
                Text(
                  names[device.id] ?? device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.text, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          // Disconnect: one mark, no words. It is the only thing on this row
          // besides the name, and a red pill of text read louder than the
          // set it belonged to.
          Material(
            color: const Color(0x22E50914),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                await ref.read(castControllerProvider.notifier).disconnect();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Tooltip(
                message: 'قطع الاتصال',
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Icons.link_off_rounded,
                      color: Color(0xFFE50914), size: 22),
                ),
              ),
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
/// something arriving at it. A long press on it opens the diagnostics.
class _CastMark extends StatelessWidget {
  const _CastMark({this.compact = false});

  /// Smaller, when there are words to make room for under it.
  final bool compact;

  /// The strip the animation is shown in.
  static const double _full = 150;
  static const double _small = 112;

  /// The Lottie draws its mark in the middle third of a square canvas and
  /// leaves the rest empty, so shown whole it is small. The canvas is
  /// scaled to this many times the strip and clipped to it: the mark
  /// itself is then what fills the width.
  static const double _zoom = 3.7;

  @override
  Widget build(BuildContext context) {
    final size = compact ? _small : _full;
    // Whoever has asked the system for less motion gets the still icon.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return SizedBox(
        height: size,
        child: const Center(
          child: Icon(Icons.tv_rounded, color: Color(0xFFE50914), size: 72),
        ),
      );
    }

    final canvas = size * _zoom;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: SizedBox(
        height: size,
        width: double.infinity,
        child: GestureDetector(
          onLongPress: () => CastDiagnosticsPage.open(context),
          child: ClipRect(
            child: OverflowBox(
              minWidth: canvas,
              maxWidth: canvas,
              minHeight: canvas,
              maxHeight: canvas,
              alignment: Alignment.center,
              child: Lottie.asset(
                'assets/animations/live_tv.json',
                repeat: true,
                width: canvas,
                height: canvas,
                fit: BoxFit.contain,
                // One asset failing is no reason for the sheet to arrive empty.
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.tv_rounded, color: Color(0xFFE50914), size: 96),
                ),
              ),
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

    final auto = quality.adaptive;
    final manual = [
      for (final q in CastQuality.values)
        if (!q.adaptive) q
    ];

    // Two controls, one decision: «تلقائي» on or off, and - when it is off -
    // which picture to send. Auto measures the link before each film; the
    // menu is for whoever knows their network better than a measurement.
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 0),
      child: Row(
        children: [
          Icon(Icons.high_quality_rounded, color: p.textMuted, size: 19),
          const SizedBox(width: 8),
          // The label gives way first: on a narrow phone the two controls
          // beside it matter more than the word they are labelled with.
          Expanded(
            child: Text(
              'الجودة',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textMuted, fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: auto ? const Color(0x22E50914) : p.cardAlt,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => ref
                  .read(castQualityProvider.notifier)
                  .set(auto ? CastQuality.balanced : CastQuality.auto),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      auto ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: auto ? const Color(0xFFE50914) : p.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تلقائي',
                      style: TextStyle(
                        color: auto ? const Color(0xFFE50914) : p.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<CastQuality>(
            initialValue: auto ? null : quality,
            color: p.card,
            tooltip: 'اختيار يدوي',
            onSelected: (choice) =>
                ref.read(castQualityProvider.notifier).set(choice),
            itemBuilder: (context) => [
              for (final option in manual)
                PopupMenuItem(
                  value: option,
                  child: Text(
                    '${option.label} · ${option.short}',
                    style: TextStyle(
                      color:
                          option == quality ? const Color(0xFFE50914) : p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    auto ? 'يدوي' : quality.short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: auto ? p.textMuted : p.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, color: p.textMuted, size: 18),
                ],
              ),
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
      await ref
          .read(castControllerProvider.notifier)
          .pairWithCode(_controller.text);
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
        style:
            TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w900),
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
                textStyle: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800),
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
            Text(_error!,
                style:
                    const TextStyle(color: Color(0xFFFF6B75), fontSize: 12.5)),
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
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('ربط'),
        ),
      ],
    );
  }
}
