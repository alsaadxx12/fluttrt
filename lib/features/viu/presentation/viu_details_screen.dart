import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_downloader/core/constants/app_colors.dart';
import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/presentation/widgets/episode_row.dart';
import 'package:youtube_downloader/presentation/widgets/house_notice.dart';
import 'package:youtube_downloader/presentation/widgets/title_profile.dart';

import '../data/viu_models.dart';
import 'viu_providers.dart';
import 'viu_watch_screen.dart';

/// A Viu title's profile: the same page every other catalogue's title
/// gets - the poster, the round play button, badges, the story, and the
/// episodes in one row - with Viu's own switch between the original and
/// the dubbed version. Playing opens the player on the chosen episode.
class ViuDetailsScreen extends ConsumerStatefulWidget {
  const ViuDetailsScreen({super.key, required this.show});

  final ViuShow show;

  @override
  ConsumerState<ViuDetailsScreen> createState() => _ViuDetailsScreenState();
}

class _ViuDetailsScreenState extends ConsumerState<ViuDetailsScreen> {
  /// The player remembers which kind was chosen last time under this key.
  static const _prefDubbed = 'viu_prefer_dubbed';

  /// The version on show (original or dubbed).
  late ViuShow _show;
  List<ViuEpisode>? _episodes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _show = widget.show;
    _pickVersionThenLoad();
  }

  /// Several versions: start with the kind (dubbed or not) chosen last time.
  Future<void> _pickVersionThenLoad() async {
    final versions = widget.show.versions;
    if (versions.length > 1) {
      var preferDubbed = true;
      try {
        preferDubbed = (await SharedPreferences.getInstance()).getBool(_prefDubbed) ?? true;
      } catch (_) {}
      final pick = versions.firstWhere((v) => v.isDubbed == preferDubbed, orElse: () => versions.first);
      if (mounted) setState(() => _show = pick);
    }
    await _load();
  }

  Future<void> _load() async {
    final seriesId = _show.seriesId;
    setState(() {
      _failed = false;
      _episodes = null;
    });
    try {
      final eps = await ref.read(viuServiceProvider).fetchFreeEpisodes(seriesId);
      if (mounted && seriesId == _show.seriesId) setState(() => _episodes = eps);
    } catch (_) {
      if (mounted && seriesId == _show.seriesId) setState(() => _failed = true);
    }
  }

  void _switchVersion(ViuShow version) {
    if (version.seriesId == _show.seriesId) return;
    setState(() => _show = version);
    if (widget.show.hasDubbedVersion && widget.show.hasOriginalVersion) {
      SharedPreferences.getInstance().then((p) => p.setBool(_prefDubbed, version.isDubbed)).catchError((_) => false);
    }
    _load();
  }

  void _play([ViuEpisode? episode]) {
    final eps = _episodes;
    final start = episode ?? ((eps == null || eps.isEmpty) ? null : eps.first);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ViuWatchScreen(
          show: widget.show,
          versionId: _show.seriesId,
          startEpisode: start?.number,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final show = _show;
    final versions = widget.show.versions;
    final eps = _episodes;
    final poster = show.portraitUrl ?? widget.show.portraitUrl ?? show.landscapeUrl ?? '';

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              ProfileHeader(
                posterUrl: poster,
                onPlay: _play,
                tooltip: show.isMovie ? 'شاهد الآن' : 'مشاهدة المسلسل',
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProfileTitle(show.displayName),
                      const SizedBox(height: 12),
                      ProfileMeta(
                        kind: show.isMovie ? 'فيلم' : 'مسلسل',
                        extras: [
                          if (show.isDubbed && versions.length == 1) 'مدبلج',
                          if (eps != null && eps.length > 1) '${eps.length} حلقة مجانية',
                        ],
                      ),
                      const SizedBox(height: 14),
                      ProfileTags([show.categoryName]),
                      if (versions.length > 1) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              'النسخة: ',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: p.text),
                            ),
                            const SizedBox(width: 4),
                            for (final v in versions) ...[
                              ChoiceChip(
                                label: Text(v.versionLabel, style: const TextStyle(fontSize: 12)),
                                selected: v.seriesId == show.seriesId,
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(
                                  color: v.seriesId == show.seriesId ? Colors.white : p.text,
                                  fontWeight: FontWeight.w700,
                                ),
                                onSelected: (_) => _switchVersion(v),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      ProfileStory(show.description),
                      const SizedBox(height: 24),
                      if (_failed)
                        Row(
                          children: [
                            Expanded(
                              child: Text('تعذّر جلب الحلقات', style: TextStyle(color: p.textMuted, fontSize: 13)),
                            ),
                            TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                          ],
                        )
                      else if (eps == null)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                          ),
                        )
                      else if (eps.length > 1 || (!show.isMovie && eps.isNotEmpty)) ...[
                        ProfileSectionTitle(Icons.video_library_rounded, 'حلقات العمل (${eps.length})'),
                        const SizedBox(height: 12),
                        EpisodeRow(
                          tiles: [
                            for (final ep in eps)
                              EpisodeTile(label: 'الحلقة ${ep.number}', image: ep.coverUrl, note: ep.durationLabel),
                          ],
                          fallbackImage: show.landscapeUrl ?? poster,
                          onTap: (i) => _play(eps[i]),
                        ),
                      ],
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
