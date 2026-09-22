import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_downloader/core/constants/app_palette.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';
import '../controllers/cast_controller.dart';
import '../models/cast_models.dart';

/// The phone as a remote control for whatever is playing elsewhere.
class CastRemotePage extends ConsumerWidget {
  const CastRemotePage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const CastRemotePage()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final cast = ref.watch(castControllerProvider);
    final media = cast.media;

    if (!cast.isConnected || media == null) {
      // The device went away while this page was open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return Scaffold(backgroundColor: p.bg, body: const SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        foregroundColor: p.text,
        title: Column(
          children: [
            Text('يُعرض على', style: TextStyle(color: p.textFaint, fontSize: 11.5)),
            Text(
              cast.device!.name,
              style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: media.posterUrl.isEmpty
                        ? Container(
                            width: 200,
                            height: 300,
                            color: p.card,
                            child: Icon(Icons.movie_rounded, color: p.textFaint, size: 48),
                          )
                        : CachedNetworkImage(
                            imageUrl: media.posterUrl,
                            cacheManager: appImageCache,
                            width: 200,
                            height: 300,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(width: 200, height: 300, color: p.card),
                            errorWidget: (_, __, ___) =>
                                Container(width: 200, height: 300, color: p.card),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                media.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              _Progress(cast: cast),
              const SizedBox(height: 18),
              _Transport(cast: cast),
              const SizedBox(height: 20),
              _Volume(cast: cast),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () async {
                  await ref.read(castControllerProvider.notifier).stopMedia();
                  if (context.mounted) Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text('إيقاف البث'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE50914),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String castClock(Duration d) {
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60);
  final h = d.inHours;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return h > 0 ? '$h:$mm:$s' : '$mm:$s';
}

class _Progress extends ConsumerWidget {
  const _Progress({required this.cast});
  final CastState cast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final live = cast.media?.isLive ?? false;

    if (live) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
    }

    final total = cast.duration ?? Duration.zero;
    final max = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    final value = cast.position.inMilliseconds.clamp(0, max.toInt()).toDouble();

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: const Color(0xFFE50914),
            inactiveTrackColor: p.border,
            thumbColor: const Color(0xFFE50914),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: total.inMilliseconds <= 0
                ? null
                : (v) => ref
                    .read(castControllerProvider.notifier)
                    .seek(Duration(milliseconds: v.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            textDirection: TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(castClock(cast.position),
                  style: TextStyle(color: p.textMuted, fontSize: 12)),
              Text(castClock(total), style: TextStyle(color: p.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({required this.cast});
  final CastState cast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final notifier = ref.read(castControllerProvider.notifier);
    final live = cast.media?.isLive ?? false;

    Widget round(IconData icon, VoidCallback? onTap, {double size = 52, Color? fill}) => Material(
          color: fill ?? p.card,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon,
                  color: onTap == null ? p.textFaint : Colors.white, size: size * 0.46),
            ),
          ),
        );

    return Row(
      textDirection: TextDirection.ltr,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        round(Icons.replay_10_rounded,
            live ? null : () => notifier.skip(const Duration(seconds: -10))),
        const SizedBox(width: 22),
        round(
          cast.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          notifier.togglePlay,
          size: 70,
          fill: const Color(0xFFE50914),
        ),
        const SizedBox(width: 22),
        round(Icons.forward_10_rounded,
            live ? null : () => notifier.skip(const Duration(seconds: 10))),
      ],
    );
  }
}

class _Volume extends ConsumerWidget {
  const _Volume({required this.cast});
  final CastState cast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final notifier = ref.read(castControllerProvider.notifier);
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        IconButton(
          onPressed: notifier.toggleMute,
          icon: Icon(
            cast.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: p.textMuted,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: p.text,
              inactiveTrackColor: p.border,
              thumbColor: p.text,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: cast.isMuted ? 0 : cast.volume.clamp(0.0, 1.0),
              onChanged: notifier.setVolume,
            ),
          ),
        ),
      ],
    );
  }
}
