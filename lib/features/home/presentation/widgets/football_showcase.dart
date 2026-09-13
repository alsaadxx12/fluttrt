import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../sports/presentation/screens/league_screen.dart';
import '../../../../presentation/widgets/reveal.dart';

/// Decorative football rows for the home page: the big leagues and the
/// game's stars, as tall cards. Images and details come from 365Scores
/// (the source the app already uses for matches).

const _img = 'https://imagecache.365scores.com/image/upload';

// ------------------------------------------------------------------ leagues

class FootballLeague {
  final int id; // 365Scores competition id
  final String name;
  final String country;
  final List<Color> colors; // brand gradient

  /// 365Scores keeps two artworks per competition; "light" is right on the
  /// white badge for most, a few only have the default one.
  final bool lightArtwork;

  /// Logos drawn in white (the Iraqi Stars League's) vanish on the white
  /// badge; they sit on a dark badge instead.
  final bool darkBadge;

  const FootballLeague(
    this.id,
    this.name,
    this.country,
    this.colors, {
    this.lightArtwork = true,
    this.darkBadge = false,
  });

  String get logoUrl =>
      '$_img/f_png,w_300,h_300,c_limit,q_auto:best,dpr_2/Competitions/${lightArtwork ? 'light/' : ''}$id';

  static const world = [
    FootballLeague(572, 'دوري أبطال أوروبا', 'أوروبا', [Color(0xFF0B1D5B), Color(0xFF2A56D8)]),
    FootballLeague(7, 'الدوري الإنجليزي', 'إنجلترا', [Color(0xFF3D195B), Color(0xFFE90052)]),
    FootballLeague(11, 'الدوري الإسباني', 'إسبانيا', [Color(0xFFB3121A), Color(0xFFFF6A3D)]),
    FootballLeague(17, 'الدوري الإيطالي', 'إيطاليا', [Color(0xFF0B2A4A), Color(0xFF0095DA)]),
    FootballLeague(25, 'الدوري الألماني', 'ألمانيا', [Color(0xFF6B0008), Color(0xFFD20515)]),
    FootballLeague(35, 'الدوري الفرنسي', 'فرنسا', [Color(0xFF091C3E), Color(0xFF1F6BFF)]),
    FootballLeague(573, 'الدوري الأوروبي', 'أوروبا', [Color(0xFF1C1208), Color(0xFFF26A21)]),
    FootballLeague(7685, 'دوري المؤتمر الأوروبي', 'أوروبا', [Color(0xFF0B3D1E), Color(0xFF19B34A)]),
    FootballLeague(623, 'دوري أبطال آسيا للنخبة', 'آسيا', [Color(0xFF1B1464), Color(0xFF2E7CF6)]),
    FootballLeague(5930, 'كأس العالم', 'العالم', [Color(0xFF0B1E3F), Color(0xFFC8102E)]),
    FootballLeague(5096, 'كأس العالم للأندية', 'العالم', [Color(0xFF2B2412), Color(0xFFC9A227)]),
    FootballLeague(73, 'الدوري البرتغالي', 'البرتغال', [Color(0xFF0B1F4D), Color(0xFF2352C9)]),
    FootballLeague(57, 'الدوري الهولندي', 'هولندا', [Color(0xFF3A160A), Color(0xFFF25C19)]),
    FootballLeague(78, 'الدوري التركي', 'تركيا', [Color(0xFF4A0B0B), Color(0xFFE30A17)]),
    FootballLeague(104, 'الدوري الأمريكي', 'أمريكا', [Color(0xFF0B1E3F), Color(0xFF1D4ED8)]),
  ];

  static const arab = [
    FootballLeague(6822, 'دوري نجوم العراق', 'العراق', [Color(0xFF0F3D22), Color(0xFF0E8A4B)], darkBadge: true),
    FootballLeague(649, 'الدوري السعودي', 'السعودية', [Color(0xFF0B5B34), Color(0xFF1FA36B)]),
    FootballLeague(552, 'الدوري المصري', 'مصر', [Color(0xFF1D1638), Color(0xFF6B3FA0)]),
    FootballLeague(549, 'الدوري الإماراتي', 'الإمارات', [Color(0xFF0B2447), Color(0xFF2B5DA8)]),
    FootballLeague(408, 'الدوري القطري', 'قطر', [Color(0xFF4A0B26), Color(0xFFD6206E)]),
    FootballLeague(5473, 'الدوري الكويتي', 'الكويت', [Color(0xFF0B2A5B), Color(0xFF2F80ED)], lightArtwork: false),
    FootballLeague(565, 'الدوري الأردني', 'الأردن', [Color(0xFF0F2F1E), Color(0xFFCE1126)]),
    FootballLeague(557, 'الدوري المغربي', 'المغرب', [Color(0xFF3A0B30), Color(0xFF8E2A6B)]),
    FootballLeague(560, 'الدوري الجزائري', 'الجزائر', [Color(0xFF0B4D2C), Color(0xFF1B8E4E)]),
    FootballLeague(554, 'الدوري التونسي', 'تونس', [Color(0xFF5B0A0A), Color(0xFFC8102E)], lightArtwork: false),
    FootballLeague(6840, 'البطولة العربية للأندية', 'العرب', [Color(0xFF2B1A0E), Color(0xFFB8862B)]),
  ];
}

class LeaguesShowcase extends StatelessWidget {
  final String title;
  final List<FootballLeague> leagues;

  const LeaguesShowcase({
    super.key,
    this.title = 'البطولات والدوريات العالمية',
    this.leagues = FootballLeague.world,
  });

  @override
  Widget build(BuildContext context) {
    return _ShowcaseRow(
      title: title,
      icon: Icons.emoji_events_rounded,
      height: 250,
      itemCount: leagues.length,
      itemBuilder: (context, i) => _LeagueCard(league: leagues[i]),
    );
  }
}

class _LeagueCard extends StatelessWidget {
  final FootballLeague league;
  const _LeagueCard({required this.league});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return _Pressable(
      // Straight to this competition: its fixtures and table.
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => LeagueScreen(league: league)),
      ),
      child: Container(
        width: 172,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: league.colors,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // soft light rings for depth
            Positioned(
              top: -40,
              left: -30,
              child: _ring(150, Colors.white.withOpacity(0.08)),
            ),
            Positioned(
              bottom: -50,
              right: -40,
              child: _ring(170, Colors.white.withOpacity(0.06)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
              child: Column(
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: league.darkBadge ? const Color(0xFF0C1410) : Colors.white,
                      border: league.darkBadge ? Border.all(color: Colors.white24) : null,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: CachedNetworkImage(
                      imageUrl: league.logoUrl,
                      fit: BoxFit.contain,
                      memCacheWidth: (96 * dpr).round(),
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) =>
                          Icon(Icons.emoji_events_rounded, color: league.colors.first, size: 44),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    league.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      league.country,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 18)),
      );
}

// ------------------------------------------------------------------ players

class FootballStar {
  final int id; // 365Scores athlete id
  final String name;
  final String club;
  final int? clubId;
  final String nationality;
  final String position;

  /// A better picture than 365Scores' where theirs is soft or out of date.
  final String? photo;

  const FootballStar(
    this.id,
    this.name, {
    this.club = '',
    this.clubId,
    this.nationality = '',
    this.position = '',
    this.photo,
  });

  String get photoUrl => photo ?? '$_img/f_png,w_400,h_400,c_limit,q_auto:good,dpr_2/Athletes/$id';
  String? get crestUrl => clubId == null ? null : '$_img/f_png,w_64,h_64,c_limit,q_auto:eco,dpr_2/Competitors/$clubId';

  FootballStar withDetails({String? name, String? club, int? clubId, String? nationality, String? position}) {
    // "بدون نادي" / no club: leave the club line out.
    final hasClub = clubId != null && clubId > 0 && club != null && club.isNotEmpty && club != 'بدون نادي';
    return FootballStar(
      id,
      (name == null || name.trim().isEmpty) ? this.name : name.trim(),
      club: hasClub ? club : '',
      clubId: hasClub ? clubId : null,
      nationality: nationality ?? this.nationality,
      position: position ?? this.position,
      photo: photo,
    );
  }

  /// The game's best-known players. Shown straight away; the current club
  /// and details are filled in from 365Scores when they arrive.
  static const featured = [
    FootballStar(874, 'ليونيل ميسي'),
    FootballStar(817, 'كريستيانو رونالدو'),
    FootballStar(39820, 'كيليان مبابي'),
    FootballStar(65760, 'إيرلينج هالاند'),
    FootballStar(131182, 'لامين يامال'),
    FootballStar(48298, 'فينيسيوس جونيور'),
    FootballStar(73000, 'جود بيلينجهام'),
    FootballStar(1439, 'محمد صلاح'),
    FootballStar(
      45,
      'نيمار',
      photo:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c0/Neymar_Junior_Brazil_V_Morocco_13_June_2026-40.jpg/500px-Neymar_Junior_Brazil_V_Morocco_13_June_2026-40.jpg',
    ),
    FootballStar(1669, 'هاري كين'),
    FootballStar(843, 'كيفين دي بروين'),
    FootballStar(1857, 'روبرت ليفاندوفسكي'),
    FootballStar(543, 'كريم بنزيما'),
    FootballStar(62, 'لوكا مودريتش'),
    FootballStar(69251, 'بيدري'),
    FootballStar(62088, 'بوكايو ساكا'),
    FootballStar(78535, 'كول بالمر'),
    FootballStar(76962, 'فلوريان فيرتز'),
    FootballStar(78061, 'جمال موسيالا'),
    FootballStar(39779, 'عثمان ديمبيلي'),
    FootballStar(47349, 'أشرف حكيمي'),
    FootballStar(65803, 'خفيتشا كفاراتسخيليا'),
    FootballStar(38667, 'لاوتارو مارتينيز'),
    FootballStar(61973, 'جوليان ألفاريز'),
    FootballStar(39789, 'رافينيا'),
    FootballStar(41053, 'فيديريكو فالفيردي'),
    FootballStar(53912, 'رودريجو'),
    FootballStar(46494, 'فيل فودين'),
    FootballStar(11583, 'مارتن أوديجارد'),
    FootballStar(46718, 'ديكلان رايس'),
    FootballStar(6262, 'برونو فيرنانديز'),
    FootballStar(46509, 'ألكسندر إيزاك'),
    FootballStar(9104, 'فيرجيل فان دايك'),
    FootballStar(10896, 'أليسون'),
    FootballStar(826, 'تيبو كورتوا'),
    FootballStar(14478, 'جيانلويجي دوناروما'),
    FootballStar(39293, 'فرينكي دي يونج'),
    FootballStar(540, 'أنطوان جريزمان'),
    FootballStar(792, 'سون هيونج مين'),
    FootballStar(48529, 'فيكتور أوسيمين'),
    FootballStar(53910, 'رافائيل لياو'),
    FootballStar(7914, 'ساديو ماني'),
    FootballStar(764, 'رياض محرز'),
    FootballStar(6455, 'باولو ديبالا'),
  ];
}

/// The featured stars with their current club, position and nationality.
final footballStarsProvider = FutureProvider<List<FootballStar>>((ref) async {
  final ids = FootballStar.featured.map((s) => s.id).join(',');
  try {
    final res = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    )).get('https://webws.365scores.com/web/athletes/', queryParameters: {
      'appTypeId': 5,
      'langId': 27,
      'athletes': ids,
    });
    final data = res.data;
    if (data is! Map) return FootballStar.featured;
    final clubs = <int, String>{
      for (final c in (data['competitors'] as List? ?? const []).whereType<Map>())
        if (c['id'] is int) c['id'] as int: '${c['name'] ?? ''}',
    };
    final byId = <int, Map>{
      for (final a in (data['athletes'] as List? ?? const []).whereType<Map>())
        if (a['id'] is int) a['id'] as int: a,
    };
    return [
      for (final s in FootballStar.featured)
        if (byId[s.id] case final a?)
          s.withDetails(
            name: '${a['name'] ?? ''}',
            clubId: a['clubId'] is int ? a['clubId'] as int : null,
            club: clubs[a['clubId']] ?? '',
            nationality: '${a['nationalityName'] ?? ''}',
            position: '${(a['position'] is Map ? a['position']['name'] : null) ?? ''}',
          )
        else
          s,
    ];
  } catch (_) {
    return FootballStar.featured;
  }
});

class StarsShowcase extends ConsumerWidget {
  const StarsShowcase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stars = ref.watch(footballStarsProvider).valueOrNull ?? FootballStar.featured;
    return _ShowcaseRow(
      title: 'نجوم الكرة',
      icon: Icons.star_rounded,
      height: 268,
      itemCount: stars.length,
      itemBuilder: (context, i) => _StarCard(star: stars[i]),
    );
  }
}

class _StarCard extends StatelessWidget {
  final FootballStar star;
  const _StarCard({required this.star});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const width = 170.0;
    const shadow = [Shadow(color: Colors.black54, blurRadius: 4)];
    return _Pressable(
      onTap: () => context.push('/sports'),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFF131826),
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The portrait fills the whole card, drawn a step closer so the
            // player rather than the studio backdrop fills it, and anchored
            // near the top so the head is never cut. Decoded at the size it is
            // drawn, so it stays sharp.
            Transform.scale(
              scale: 1.18,
              alignment: const Alignment(0, -0.75),
              child: CachedNetworkImage(
                imageUrl: star.photoUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                memCacheWidth: (316 * dpr).round(), // card height x 1.18
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) =>
                    const Center(child: Icon(Icons.person_rounded, color: Colors.white24, size: 60)),
              ),
            ),
            // Name and club on a small label, so they read on the photos'
            // white studio background.
            PositionedDirectional(
              start: 8,
              end: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F19).withOpacity(0.78),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      star.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        shadows: shadow,
                      ),
                    ),
                    if (star.club.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (star.crestUrl != null) ...[
                            CachedNetworkImage(
                              imageUrl: star.crestUrl!,
                              width: 16,
                              height: 16,
                              memCacheWidth: (16 * dpr).round(),
                              errorWidget: (_, __, ___) => const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              star.club,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ shared

class _ShowcaseRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _ShowcaseRow({
    required this.title,
    required this.icon,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFFFB800), size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          // room for the cards' shadows
          height: height + 16,
          child: WheelScroll(
            builder: (controller) => ListView.separated(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: itemBuilder,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shrinks a little under the finger.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}
