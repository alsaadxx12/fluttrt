import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/settings/presentation/providers/settings_provider.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final p = AppPalette.of(context);
    // Read from the installed package, so the number always follows the
    // build the user actually has.
    final installed = ref.watch(installedVersionProvider);

    final versionText = installed.when(
      data: (v) => strings.versionLabel('${v.versionName} (${v.versionCode})'),
      loading: () => strings.versionLabel('…'),
      error: (_, __) => strings.versionLabel('—'),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: [
                const Align(alignment: AlignmentDirectional.centerStart, child: _BackButton()),
                const SizedBox(height: 8),
                _Hero(name: strings.appName, subtitle: strings.appSubtitle, version: versionText),
                const SizedBox(height: 14),
                const _UpdateStatusCard(),
                const SizedBox(height: 14),
                const _InfoCard(
                  rows: [
                    _InfoRow(icon: Icons.person_rounded, label: 'المطوّر', value: 'Ali Alsaady'),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.gavel_rounded, size: 17, color: p.textFaint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.legalNotice,
                          style: TextStyle(fontSize: 11.5, height: 1.6, color: p.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'صُنع بشغف لعشّاق السينما والكرة',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.textFaint),
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

/// The about page has no shared header, so it carries its own way back.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: p.card,
      shape: CircleBorder(side: BorderSide(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.canPop() ? context.pop() : context.go('/'),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(Icons.arrow_forward_rounded, size: 20, color: p.icon),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ hero

/// Logo on a brand gradient, with the app's name and the installed version.
class _Hero extends StatelessWidget {
  final String name;
  final String subtitle;
  final String version;
  const _Hero({required this.name, required this.subtitle, required this.version});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: p.isDark
              ? const [Color(0xFF2A0B10), Color(0xFF14111C), Color(0xFF0B0E16)]
              : const [Color(0xFFFFE3E6), Color(0xFFF6F1FA), Color(0xFFEFF3FB)],
        ),
        border: Border.all(color: p.isDark ? Colors.white10 : const Color(0xFFE3E8F1)),
        boxShadow: p.cardShadow,
      ),
      child: Column(
        children: [
          // The logo, lifted off the gradient by a ring of brand light.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFE50914), Color(0xFFFF6B6B)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFFE50914).withOpacity(0.38), blurRadius: 26, spreadRadius: 1),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: p.isDark ? const Color(0xFF0B0E16) : Colors.white),
              child: ClipOval(
                child: Image.asset('assets/images/app_logo.png', width: 76, height: 76, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3, color: p.text),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: p.textMuted),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: p.isDark ? Colors.white10 : Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: p.isDark ? Colors.white24 : const Color(0xFFE3E8F1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFE50914)),
                const SizedBox(width: 6),
                Text(version, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: p.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- update

/// Says whether a newer build exists, and offers the update when it does.
class _UpdateStatusCard extends ConsumerWidget {
  const _UpdateStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final state = ref.watch(updateControllerProvider);
    final p = AppPalette.of(context);

    final checking = state.status == UpdateStatus.loading;
    final hasUpdate = state.hasUpdate;
    final info = state.info;
    final accent = checking ? p.textFaint : (hasUpdate ? const Color(0xFFE50914) : const Color(0xFF19A974));
    final icon = checking ? Icons.sync_rounded : (hasUpdate ? Icons.system_update_rounded : Icons.verified_rounded);
    final title = checking ? strings.checkingUpdate : (hasUpdate ? strings.updateAvailableLabel : strings.upToDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hasUpdate ? accent.withOpacity(0.45) : p.border),
        boxShadow: p.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: accent.withOpacity(0.14), shape: BoxShape.circle),
                child: Icon(icon, size: 21, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: p.text)),
                    if (hasUpdate && info != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${info.versionName} (${info.versionCode})',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasUpdate && info != null && info.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(12)),
              child: Text(info.notes, style: TextStyle(fontSize: 12, height: 1.6, color: p.textMuted)),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: hasUpdate
                ? FilledButton.icon(
                    onPressed: ref.read(updateControllerProvider.notifier).showPrompt,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 19),
                    label: Text(strings.updateNow, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                  )
                : OutlinedButton.icon(
                    onPressed: checking ? null : ref.read(updateControllerProvider.notifier).checkNow,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: Text(strings.checkForUpdates,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- info

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        boxShadow: p.cardShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.border, indent: 52, endIndent: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(rows[i].icon, size: 19, color: p.textFaint),
                  const SizedBox(width: 12),
                  Text(rows[i].label,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.textMuted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
