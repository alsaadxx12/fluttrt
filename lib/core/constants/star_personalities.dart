/// Model representing a celebrity personality (Actor or Football Legend).
class StarPersonality {
  final String id;
  final String name;
  final String role;
  final String badge;
  final String imageUrl;
  final String searchQuery;
  final bool isPlayer; // true: sports player, false: cinema actor

  const StarPersonality({
    required this.id,
    required this.name,
    required this.role,
    required this.badge,
    required this.imageUrl,
    required this.searchQuery,
    required this.isPlayer,
  });
}

/// Curated high-profile actors and cinema superstars.
const List<StarPersonality> kCinemaStars = [
  StarPersonality(
    id: 'leo',
    name: 'ليوناردو دي كابريو',
    role: 'أيقونة هوليوود العالمية',
    badge: 'أوسكار 🏆',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/2d/LeoPTABFI191125-28_%28cropped%29.jpg/330px-LeoPTABFI191125-28_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'ليوناردو دي كابريو',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'keanu',
    name: 'كيانو ريفز',
    role: 'جون ويك • ماتريكس',
    badge: 'أسطورة 🔥',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b4/Keanu_Reeves_at_TIFF_2025_02_%28Cropped%29.jpg/330px-Keanu_Reeves_at_TIFF_2025_02_%28Cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'كيانو ريفز',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'tom',
    name: 'توم كروز',
    role: 'المهمة المستحيلة • توب غان',
    badge: 'نجم الشباك 🎬',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/23/Tom_Cruise_at_53rd_Saturn_Awards_2026-01.jpg/330px-Tom_Cruise_at_53rd_Saturn_Awards_2026-01.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'توم كروز',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'rdj',
    name: 'روبرت داوني جونيور',
    role: 'الرجل الحديدي (مارفل)',
    badge: 'Iron Man ⚡',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a9/RobertDowneyJr-byPhilipRomano7_%28cropped%29.jpg/330px-RobertDowneyJr-byPhilipRomano7_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'روبرت داوني',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'cillian',
    name: 'كيليان ميرفي',
    role: 'أوبنهايمر • بيكي بلايندرز',
    badge: 'أوسكار 🏆',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/ed/Cillian_Murphy_at_the_London_premier_of_Steve_in_September_2025_%28cropped%29.jpg/330px-Cillian_Murphy_at_the_London_premier_of_Steve_in_September_2025_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'كيليان ميرفي',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'scarlett',
    name: 'سكارليت جوهانسون',
    role: 'الأرملة السوداء • أفلام عالمية',
    badge: 'نجمة عالمية ⭐',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ad/Scarlett_Johansson-8588.jpg/330px-Scarlett_Johansson-8588.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'سكارليت جوهانسون',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'karim',
    name: 'كريم عبد العزيز',
    role: 'الفيل الأزرق • كيرة والجن',
    badge: 'نجم العرب 👑',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/4a/%D9%83%D8%B1%D9%8A%D9%85_%D8%B9%D8%A8%D8%AF_%D8%A7%D9%84%D8%B9%D8%B2%D9%8A%D8%B2.png/330px-%D9%83%D8%B1%D9%8A%D9%85_%D8%B9%D8%A8%D8%AF_%D8%A7%D9%84%D8%B9%D8%B2%D9%8A%D8%B2.png?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'كريم عبد العزيز',
    isPlayer: false,
  ),
  StarPersonality(
    id: 'adel',
    name: 'عادل إمام',
    role: 'زعيم الكوميديا والسينما المصرية',
    badge: 'الزعيم 👑',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e2/Adel_Imam_2009.jpg/330px-Adel_Imam_2009.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'عادل إمام',
    isPlayer: false,
  ),
];

/// Curated high-profile football superstars and sports legends.
const List<StarPersonality> kFootballStars = [
  StarPersonality(
    id: 'messi',
    name: 'ليونيل ميسي',
    role: 'إنتر ميامي • الأرجنتين',
    badge: '8 كرات ذهبية 🌟',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c8/Leo_Messi_Argentina_v_Egypt_7_July_2026-1.jpg/330px-Leo_Messi_Argentina_v_Egypt_7_July_2026-1.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'إنتر ميامي',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'cr7',
    name: 'كريستيانو رونالدو',
    role: 'النصر • البرتغال',
    badge: 'الدون CR7 ⚡',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/26/Cristiano_Ronaldo_Croatia_v_Portugal_2_July_2026-075_%28cropped%29.jpg/330px-Cristiano_Ronaldo_Croatia_v_Portugal_2_July_2026-075_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'النصر',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'mbappe',
    name: 'كيليان مبابي',
    role: 'ريال مدريد • فرنسا',
    badge: 'الصاروخ 🚀',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/95/Kylian_Mbappe_France_v_Senegal_16_June_2026-391_%28cropped%29.jpg/330px-Kylian_Mbappe_France_v_Senegal_16_June_2026-391_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'ريال مدريد',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'salah',
    name: 'محمد صلاح',
    role: 'ليفربول • مصر',
    badge: 'فخر العرب 👑',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a6/Mohamed_Salah_Argentina_v_Egypt_7_July_2026-163_%28cropped%29.jpg/330px-Mohamed_Salah_Argentina_v_Egypt_7_July_2026-163_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'ليفربول',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'haaland',
    name: 'إيرلينغ هالاند',
    role: 'مانشستر سيتي • النرويج',
    badge: 'الوحش 🦾',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/43/Erling_Haaland_Morocco_v_Norway_7_June_2026-51.jpg/330px-Erling_Haaland_Morocco_v_Norway_7_June_2026-51.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'مانشستر سيتي',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'vinicius',
    name: 'فينيسيوس جونيور',
    role: 'ريال مدريد • البرازيل',
    badge: 'سامبا السحر 🇧🇷',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/10/Vin%C3%ADcius_J%C3%BAnior_Brazil_V_Morocco_13_June_2026-207_%28cropped%29.jpg/330px-Vin%C3%ADcius_J%C3%BAnior_Brazil_V_Morocco_13_June_2026-207_%28cropped%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'ريال مدريد',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'neymar',
    name: 'نيمار جونيور',
    role: 'الهلال • البرازيل',
    badge: 'الساحر 🪄',
    imageUrl:
        'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c0/Neymar_Junior_Brazil_V_Morocco_13_June_2026-40.jpg/330px-Neymar_Junior_Brazil_V_Morocco_13_June_2026-40.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail',
    searchQuery: 'الهلال',
    isPlayer: true,
  ),
  StarPersonality(
    id: 'aymen',
    name: 'أيمن حسين',
    role: 'منتخب العراق • هداف آسيا',
    badge: 'أسود الرافدين 🇮🇶',
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/7/78/4822953_AE7I9053_%28cropped2%29.jpg?utm_source=en.wikipedia.org&utm_campaign=api&utm_content=thumbnail_unscaled',
    searchQuery: 'العراق',
    isPlayer: true,
  ),
];
