import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_palette.dart';
import '../../../home/presentation/widgets/football_showcase.dart';
import 'league_screen.dart';

/// All competitions, in two clear groups, each a tile opening its page.
class LeaguesScreen extends StatelessWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.isDark ? const Color(0xFF0B0F19) : Colors.white,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('الدوريات والبطولات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _group(context, 'الدوريات العربية', FootballLeague.arab),
          const SizedBox(height: 18),
          _group(context, 'البطولات والدوريات العالمية', FootballLeague.world),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<FootballLeague> leagues) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text(title, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w900)),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
          ),
          itemCount: leagues.length,
          itemBuilder: (context, i) => _LeagueTile(league: leagues[i]),
        ),
      ],
    );
  }
}

class _LeagueTile extends StatelessWidget {
  final FootballLeague league;
  const _LeagueTile({required this.league});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeagueScreen(league: league))),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: league.darkBadge ? const Color(0xFF0C1410) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
              ),
              child: CachedNetworkImage(
                imageUrl: league.logoUrl,
                fit: BoxFit.contain,
                memCacheWidth: (56 * dpr).round(),
                errorWidget: (_, __, ___) => Icon(Icons.emoji_events_rounded, color: league.colors.last, size: 28),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                league.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.2),
              ),
            ),
            Text(league.country, style: TextStyle(color: p.textFaint, fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
