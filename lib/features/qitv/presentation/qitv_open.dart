import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/features/shahid/data/shahid_models.dart';
import 'package:youtube_downloader/features/shahid/presentation/shahid_player_screen.dart';
import 'package:youtube_downloader/presentation/widgets/glass.dart';

import '../data/qitv_models.dart';
import 'qitv_details_screen.dart';

/// Qi TV's own app on the Play Store: where its encrypted channels and its
/// series are watched.
const String qiTvPackage = 'iq.qicard.tv.prod';

/// Opens Qi TV's app page on the store (the store opens the app itself
/// when it is installed).
Future<void> openQiApp(BuildContext context) async {
  final uris = [
    Uri.parse('market://details?id=$qiTvPackage'),
    Uri.parse('https://play.google.com/store/apps/details?id=$qiTvPackage'),
  ];
  for (final uri in uris) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح متجر التطبيقات')));
  }
}

/// A title's profile: the same page every catalogue's title gets.
void openQiTitle(
  BuildContext context, {
  required String title,
  required String kind,
  String? poster,
  String description = '',
}) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => QiTvDetailsScreen(title: title, kind: kind, poster: poster, description: description),
    ),
  );
}

/// The live player's own channel record for [c].
ShahidItem asQiShahidItem(QiChannel c) => ShahidItem(
      id: c.id,
      title: c.title,
      productType: 'LIVESTREAM',
      pageUrl: 'https://qi.tv/#our-channels',
      logoTemplate: c.logoUrl,
      isFree: true,
      streamUrl: c.streamM3u8.isNotEmpty ? c.streamM3u8 : c.streamMpd,
    );

/// Plays a channel the way a sports channel is played - full screen, with
/// the cast button - or, for one Qi TV encrypts, says so and offers its app.
void openQiChannel(BuildContext context, QiChannel channel, List<QiChannel> all) {
  if (!channel.playable) {
    _explainEncrypted(context, channel);
    return;
  }
  final siblings = all.where((c) => c.playable).map(asQiShahidItem).toList();
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => ShahidPlayerScreen(channel: asQiShahidItem(channel), channels: siblings, startFullscreen: true),
    ),
  );
}

void _explainEncrypted(BuildContext context, QiChannel channel) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final p = AppPalette.of(ctx);
      return GlassSheet(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: p.textFaint, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.amber.shade600, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        channel.title,
                        style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'هذه القناة يبثها Qi TV مشفّرة (DRM)، فلا تُشاهَد إلا داخل تطبيق Qi TV نفسه، مجاناً بحساب هناك.',
                  style: TextStyle(color: p.textMuted, fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      openQiApp(context);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('فتح تطبيق Qi TV', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
