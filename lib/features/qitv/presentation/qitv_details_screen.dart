import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/presentation/widgets/glass.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';
import 'package:youtube_downloader/presentation/widgets/title_profile.dart';

import 'qitv_open.dart';

/// A Qi TV title's profile: the same page every other catalogue's title
/// gets - the poster, the round play button, badges, the story.
///
/// Qi TV's public pages carry a title's poster and story, not its
/// episodes: those are inside its own app, behind an account. So the play
/// button and the note under the story both lead there.
class QiTvDetailsScreen extends StatelessWidget {
  const QiTvDetailsScreen({
    super.key,
    required this.title,
    required this.kind,
    this.poster,
    this.description = '',
  });

  final String title;

  /// «فيلم» or «مسلسل».
  final String kind;
  final String? poster;
  final String description;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              ProfileHeader(
                posterUrl: poster ?? '',
                onPlay: () => openQiApp(context),
                tooltip: 'شاهد في تطبيق Qi TV',
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProfileTitle(title),
                      const SizedBox(height: 12),
                      ProfileMeta(kind: kind, extras: const ['Qi TV', 'إنتاج عراقي']),
                      const SizedBox(height: 14),
                      const ProfileTags(['حصري', 'عربي']),
                      const SizedBox(height: 4),
                      ProfileStory(description),
                      const SizedBox(height: 20),
                      GlassPanel(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          children: [
                            const Icon(Icons.live_tv_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'هذا العمل من إنتاج Qi TV ويُشاهد داخل تطبيقها.',
                                style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => openQiApp(context),
                              child: const Text('فتح', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const HouseNotice.snacks(),
        ],
      ),
    );
  }
}
