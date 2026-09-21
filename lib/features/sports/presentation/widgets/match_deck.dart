import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_downloader/core/network/image_cache.dart';

import '../../../../core/constants/app_palette.dart';
import '../../data/models/sports_models.dart';
import '../important_match.dart';
import '../screens/sports_player_screen.dart';

/// Live matches offered from the edge of the screen instead of across it.
///
/// Collapsed, it is a small tab clinging to the side rail at mid-height, as
/// though a deck of cards were tucked just off-screen. Pulling it out fans
/// the matches like a hand of cards that can be dealt through one at a time.
/// Nothing is ever thrown in front of the viewer on start-up.
class MatchDeck extends StatefulWidget {
  final List<SportMatchItem> matches;
  const MatchDeck({super.key, required this.matches});

  @override
  State<MatchDeck> createState() => _MatchDeckState();
}

class _MatchDeckState extends State<MatchDeck> with SingleTickerProviderStateMixin {
  bool _open = false;
  late final PageController _pages = PageController(viewportFraction: 0.82);
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.matches.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        // The tab itself, half tucked off the edge.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          top: MediaQuery.of(context).size.height * 0.36,
          right: _open ? -46 : 0,
          child: _Handle(count: widget.matches.length, onTap: () => setState(() => _open = true)),
        ),
        if (_open) ...[
          // A soft veil, so a tap anywhere puts the cards away again.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _open = false),
              child: ColoredBox(color: Colors.black.withOpacity(0.55)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).size.height * 0.22,
            child: _Deck(
              matches: widget.matches,
              controller: _pages,
              index: _index,
              onIndex: (i) => setState(() => _index = i),
              onClose: () => setState(() => _open = false),
            ),
          ),
        ],
      ],
    );
  }
}

/// The little tab on the rail: a live dot and how many matches are waiting.
class _Handle extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _Handle({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 96,
        decoration: const BoxDecoration(
          color: Color(0xFFE50914),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(13),
            bottomLeft: Radius.circular(13),
          ),
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(-3, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(height: 7),
            Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The hand of cards, dealt one at a time.
class _Deck extends StatelessWidget {
  final List<SportMatchItem> matches;
  final PageController controller;
  final int index;
  final ValueChanged<int> onIndex;
  final VoidCallback onClose;

  const _Deck({
    required this.matches,
    required this.controller,
    required this.index,
    required this.onIndex,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 234,
          child: PageView.builder(
            controller: controller,
            onPageChanged: onIndex,
            itemCount: matches.length,
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                // How far this card is from the one being held.
                var delta = 0.0;
                if (controller.position.haveDimensions) {
                  delta = (controller.page ?? index.toDouble()) - i;
                } else {
                  delta = (index - i).toDouble();
                }
                final d = delta.clamp(-1.5, 1.5);
                // Cards either side lie back and tilt, the way a hand fans.
                return Transform.rotate(
                  angle: d * 0.06,
                  child: Transform.scale(
                    scale: 1 - d.abs() * 0.10,
                    child: Opacity(opacity: (1 - d.abs() * 0.35).clamp(0.0, 1.0), child: child),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _MatchCard(match: matches[i], onClose: onClose),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Which card of the hand is showing.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < matches.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? const Color(0xFFE50914) : Colors.white38,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  final SportMatchItem match;
  final VoidCallback onClose;
  const _MatchCard({required this.match, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: Color(0xFFE50914), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    match.league ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textFaint, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 17, color: p.textFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _team(match.home, p, dpr)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    ImportantMatch.scoreLabel(match),
                    style: const TextStyle(
                        color: Color(0xFFE50914), fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                  ),
                ),
                Expanded(child: _team(match.away, p, dpr)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ImportantMatch.minuteLabel(match),
              style: const TextStyle(color: Color(0xFFE50914), fontSize: 11.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: FilledButton(
                onPressed: () {
                  onClose();
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => SportsPlayerScreen(match: match)),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _team(TeamInfo t, AppPalette p, double dpr) => Column(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: (t.logo ?? '').isEmpty
                ? Icon(Icons.shield_rounded, color: p.textFaint, size: 34)
                : CachedNetworkImage(
                    imageUrl: t.logo!,
                    cacheManager: appImageCache,
                    fit: BoxFit.contain,
                    // The logo is 44 lp; decode at its own pixel width.
                    memCacheWidth: (44 * dpr).round(),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: p.textFaint, size: 34),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            t.name,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
      );
}
