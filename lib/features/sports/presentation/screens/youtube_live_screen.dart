import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/constants/app_palette.dart';

/// A channel that broadcasts on YouTube (e.g. Karbala TV), in YouTube's
/// official embedded player - the same one the channel's own site uses.
class YoutubeLiveScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String logoUrl;

  const YoutubeLiveScreen({super.key, required this.videoId, required this.title, this.logoUrl = ''});

  @override
  State<YoutubeLiveScreen> createState() => _YoutubeLiveScreenState();
}

class _YoutubeLiveScreenState extends State<YoutubeLiveScreen> {
  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(
      showFullscreenButton: true,
      strictRelatedVideos: true,
      interfaceLanguage: 'ar',
      captionLanguage: 'ar',
      enableCaption: false,
    ),
  );

  @override
  void dispose() {
    _controller.close();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The page around the player follows the theme (white in light mode);
    // the player surface itself is YouTube's own and stays as it is.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    return YoutubePlayerScaffold(
      controller: _controller,
      aspectRatio: 16 / 9,
      builder: (context, player) => Scaffold(
        backgroundColor: isDark ? const Color(0xFF07090E) : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : palette.icon),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    if (widget.logoUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: Image.network(widget.logoUrl, height: 30, cacheHeight: 90,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDark ? Colors.white : palette.text, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsetsDirectional.only(end: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(4)),
                      child: const Text('LIVE',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
              player,
            ],
          ),
        ),
      ),
    );
  }
}
