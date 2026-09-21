import 'models/cinemana_models.dart';

/// Big franchises (film series, TV-series universes, anime), each listed
/// title by title.
///
/// A Cinemana title only joins a franchise when it is of the entry's kind
/// (film or series), its title is one of that entry's titles *and* its year
/// matches. Search results are loose ("Harry Potter" also finds "Dirty
/// Harry", "Batman" finds dozens of unrelated animated films), so nothing is
/// taken on a keyword alone.
enum FranchiseKind { movie, series }

/// Which home row a franchise belongs to.
enum FranchiseSection { films, series, anime }

class FranchiseEntry {
  /// Accepted titles (the official one first, then how Cinemana spells it).
  final List<String> titles;
  final int year;
  final FranchiseKind kind;
  const FranchiseEntry(this.year, this.titles, {this.kind = FranchiseKind.movie});
}

class FilmFranchise {
  final String id;
  final String name; // Arabic
  final FranchiseSection section;

  /// Cinemana searches that between them surface every title of the franchise.
  final List<String> queries;

  /// Two result pages per search (wide keywords) or one (exact titles).
  final bool deepSearch;
  final List<FranchiseEntry> entries; // release order

  const FilmFranchise({
    required this.id,
    required this.name,
    required this.queries,
    required this.entries,
    this.section = FranchiseSection.films,
    this.deepSearch = true,
  });

  static List<FilmFranchise> inSection(FranchiseSection section) =>
      all.where((f) => f.section == section).toList();

  static const all = [
    FilmFranchise(
      id: 'harry-potter',
      name: 'هاري بوتر',
      queries: ['Harry Potter'],
      entries: [
        FranchiseEntry(2001, ["Harry Potter and the Sorcerer's Stone", "Harry Potter and the Philosopher's Stone"]),
        FranchiseEntry(2002, ['Harry Potter and the Chamber of Secrets']),
        FranchiseEntry(2004, ['Harry Potter and the Prisoner of Azkaban']),
        FranchiseEntry(2005, ['Harry Potter and the Goblet of Fire']),
        FranchiseEntry(2007, ['Harry Potter and the Order of the Phoenix']),
        FranchiseEntry(2009, ['Harry Potter and the Half-Blood Prince']),
        FranchiseEntry(2010, ['Harry Potter and the Deathly Hallows: Part 1']),
        FranchiseEntry(2011, ['Harry Potter and the Deathly Hallows: Part 2']),
      ],
    ),
    FilmFranchise(
      id: 'spider-man',
      name: 'سبايدر مان',
      queries: ['Spider-Man'],
      entries: [
        FranchiseEntry(2002, ['Spider-Man']),
        FranchiseEntry(2004, ['Spider-Man 2']),
        FranchiseEntry(2007, ['Spider-Man 3']),
        FranchiseEntry(2012, ['The Amazing Spider-Man']),
        FranchiseEntry(2014, ['The Amazing Spider-Man 2']),
        FranchiseEntry(2017, ['Spider-Man: Homecoming']),
        FranchiseEntry(2018, ['Spider-Man: Into the Spider-Verse']),
        FranchiseEntry(2019, ['Spider-Man: Far from Home']),
        FranchiseEntry(2021, ['Spider-Man: No Way Home']),
        FranchiseEntry(2023, ['Spider-Man: Across the Spider-Verse']),
      ],
    ),
    FilmFranchise(
      id: 'batman',
      name: 'باتمان',
      queries: ['Batman', 'Dark Knight'],
      entries: [
        FranchiseEntry(1989, ['Batman']),
        FranchiseEntry(1992, ['Batman Returns']),
        FranchiseEntry(1995, ['Batman Forever']),
        FranchiseEntry(1997, ['Batman & Robin']),
        FranchiseEntry(2005, ['Batman Begins']),
        FranchiseEntry(2008, ['The Dark Knight']),
        FranchiseEntry(2012, ['The Dark Knight Rises']),
        FranchiseEntry(2022, ['The Batman']),
      ],
    ),
    FilmFranchise(
      id: 'fast-furious',
      name: 'السرعة والغضب',
      queries: ['Fast', 'Furious', 'F9'],
      entries: [
        FranchiseEntry(2001, ['The Fast and the Furious']),
        FranchiseEntry(2003, ['2 Fast 2 Furious']),
        FranchiseEntry(2006, ['The Fast and the Furious: Tokyo Drift']),
        FranchiseEntry(2009, ['Fast & Furious']),
        FranchiseEntry(2011, ['Fast Five']),
        FranchiseEntry(2013, ['Fast & Furious 6']),
        FranchiseEntry(2015, ['Furious 7']),
        FranchiseEntry(2017, ['The Fate of the Furious']),
        FranchiseEntry(2019, ['Fast & Furious Presents: Hobbs & Shaw']),
        FranchiseEntry(2021, ['F9: The Fast Saga', 'F9']),
        FranchiseEntry(2023, ['Fast X']),
      ],
    ),
    FilmFranchise(
      id: 'mission-impossible',
      name: 'المهمة المستحيلة',
      queries: ['Mission Impossible'],
      entries: [
        FranchiseEntry(1996, ['Mission: Impossible']),
        FranchiseEntry(2000, ['Mission: Impossible II', 'Mission: Impossible 2']),
        FranchiseEntry(2006, ['Mission: Impossible III', 'Mission: Impossible 3']),
        FranchiseEntry(2011, ['Mission: Impossible - Ghost Protocol']),
        FranchiseEntry(2015, ['Mission: Impossible - Rogue Nation']),
        FranchiseEntry(2018, ['Mission: Impossible - Fallout']),
        FranchiseEntry(2023, ['Mission: Impossible - Dead Reckoning Part One']),
        FranchiseEntry(2025, ['Mission: Impossible - The Final Reckoning']),
      ],
    ),
    FilmFranchise(
      id: 'star-wars',
      name: 'حرب النجوم',
      queries: ['Star Wars'],
      entries: [
        FranchiseEntry(1977, ['Star Wars: Episode IV - A New Hope', 'Star Wars']),
        FranchiseEntry(1980, ['Star Wars: Episode V - The Empire Strikes Back', 'The Empire Strikes Back']),
        FranchiseEntry(1983, ['Star Wars: Episode VI - Return of the Jedi', 'Return of the Jedi']),
        FranchiseEntry(1999, ['Star Wars: Episode I - The Phantom Menace']),
        FranchiseEntry(2002, ['Star Wars: Episode II - Attack of the Clones']),
        FranchiseEntry(2005, ['Star Wars: Episode III - Revenge of the Sith']),
        FranchiseEntry(2015, ['Star Wars: The Force Awakens', 'Star Wars: Episode VII - The Force Awakens']),
        FranchiseEntry(2016, ['Rogue One: A Star Wars Story', 'Rogue One']),
        FranchiseEntry(2017, ['Star Wars: The Last Jedi', 'Star Wars: Episode VIII - The Last Jedi']),
        FranchiseEntry(2018, ['Solo: A Star Wars Story']),
        FranchiseEntry(2019, ['Star Wars: The Rise of Skywalker', 'Star Wars: Episode IX - The Rise of Skywalker']),
      ],
    ),
    FilmFranchise(
      id: 'transformers',
      name: 'المتحولون',
      queries: ['Transformers', 'Bumblebee'],
      entries: [
        FranchiseEntry(2007, ['Transformers']),
        FranchiseEntry(2009, ['Transformers: Revenge of the Fallen']),
        FranchiseEntry(2011, ['Transformers: Dark of the Moon']),
        FranchiseEntry(2014, ['Transformers: Age of Extinction']),
        FranchiseEntry(2017, ['Transformers: The Last Knight']),
        FranchiseEntry(2018, ['Bumblebee']),
        FranchiseEntry(2023, ['Transformers: Rise of the Beasts']),
      ],
    ),
    FilmFranchise(
      id: 'jurassic',
      name: 'الحديقة الجوراسية',
      queries: ['Jurassic'],
      entries: [
        FranchiseEntry(1993, ['Jurassic Park']),
        FranchiseEntry(1997, ['The Lost World: Jurassic Park']),
        FranchiseEntry(2001, ['Jurassic Park III', 'Jurassic Park 3']),
        FranchiseEntry(2015, ['Jurassic World']),
        FranchiseEntry(2018, ['Jurassic World: Fallen Kingdom']),
        FranchiseEntry(2022, ['Jurassic World Dominion', 'Jurassic World: Dominion']),
        FranchiseEntry(2025, ['Jurassic World: Rebirth', 'Jurassic World Rebirth']),
      ],
    ),
    FilmFranchise(
      id: 'alien',
      name: 'أليين',
      queries: ['Alien', 'Prometheus', 'Romulus'],
      entries: [
        FranchiseEntry(1979, ['Alien']),
        FranchiseEntry(1986, ['Aliens', 'Alien 2', 'Aliens 2']),
        FranchiseEntry(1992, ['Alien 3', 'Alien³']),
        FranchiseEntry(1997, ['Alien: Resurrection']),
        FranchiseEntry(2012, ['Prometheus']),
        FranchiseEntry(2017, ['Alien: Covenant']),
        FranchiseEntry(2024, ['Alien: Romulus']),
      ],
    ),
    FilmFranchise(
      id: 'james-bond',
      name: 'جيمس بوند',
      // Bond titles don't say "Bond": each film is looked up by its title.
      deepSearch: false,
      queries: [
        'Dr. No', 'From Russia with Love', 'Goldfinger', 'Thunderball', 'You Only Live Twice',
        "On Her Majesty's Secret Service", 'Diamonds Are Forever', 'Live and Let Die',
        'The Man with the Golden Gun', 'The Spy Who Loved Me', 'Moonraker', 'For Your Eyes Only',
        'Octopussy', 'A View to a Kill', 'The Living Daylights', 'Licence to Kill', 'GoldenEye',
        'Tomorrow Never Dies', 'The World Is Not Enough', 'Die Another Day', 'Casino Royale',
        'Quantum of Solace', 'Skyfall', 'Spectre', 'No Time to Die',
      ],
      entries: [
        FranchiseEntry(1962, ['Dr. No']),
        FranchiseEntry(1963, ['From Russia with Love']),
        FranchiseEntry(1964, ['Goldfinger']),
        FranchiseEntry(1965, ['Thunderball']),
        FranchiseEntry(1967, ['You Only Live Twice']),
        FranchiseEntry(1969, ["On Her Majesty's Secret Service"]),
        FranchiseEntry(1971, ['Diamonds Are Forever']),
        FranchiseEntry(1973, ['Live and Let Die']),
        FranchiseEntry(1974, ['The Man with the Golden Gun']),
        FranchiseEntry(1977, ['The Spy Who Loved Me']),
        FranchiseEntry(1979, ['Moonraker']),
        FranchiseEntry(1981, ['For Your Eyes Only']),
        FranchiseEntry(1983, ['Octopussy']),
        FranchiseEntry(1985, ['A View to a Kill']),
        FranchiseEntry(1987, ['The Living Daylights']),
        FranchiseEntry(1989, ['Licence to Kill', 'License to Kill']),
        FranchiseEntry(1995, ['GoldenEye']),
        FranchiseEntry(1997, ['Tomorrow Never Dies']),
        FranchiseEntry(1999, ['The World Is Not Enough']),
        FranchiseEntry(2002, ['Die Another Day']),
        FranchiseEntry(2006, ['Casino Royale']),
        FranchiseEntry(2008, ['Quantum of Solace']),
        FranchiseEntry(2012, ['Skyfall']),
        FranchiseEntry(2015, ['Spectre']),
        FranchiseEntry(2021, ['No Time to Die']),
      ],
    ),

    FilmFranchise(
      id: 'lotr',
      name: 'سيد الخواتم',
      queries: ['Lord of the Rings'],
      entries: [
        FranchiseEntry(2001, ['The Lord of the Rings: The Fellowship of the Ring']),
        FranchiseEntry(2002, ['The Lord of the Rings: The Two Towers']),
        FranchiseEntry(2003, ['The Lord of the Rings: The Return of the King']),
      ],
    ),
    FilmFranchise(
      id: 'hobbit',
      name: 'الهوبيت',
      queries: ['Hobbit'],
      entries: [
        FranchiseEntry(2012, ['The Hobbit: An Unexpected Journey']),
        FranchiseEntry(2013, ['The Hobbit: The Desolation of Smaug']),
        FranchiseEntry(2014, ['The Hobbit: The Battle of the Five Armies']),
      ],
    ),
    FilmFranchise(
      id: 'pirates',
      name: 'قراصنة الكاريبي',
      queries: ['Pirates of the Caribbean'],
      entries: [
        FranchiseEntry(2003, ['Pirates of the Caribbean: The Curse of the Black Pearl']),
        FranchiseEntry(2006, ["Pirates of the Caribbean: Dead Man's Chest"]),
        FranchiseEntry(2007, ["Pirates of the Caribbean: At World's End"]),
        FranchiseEntry(2011, ['Pirates of the Caribbean: On Stranger Tides']),
        FranchiseEntry(2017, ['Pirates of the Caribbean: Dead Men Tell No Tales']),
      ],
    ),
    FilmFranchise(
      id: 'matrix',
      name: 'ماتريكس',
      queries: ['Matrix'],
      entries: [
        FranchiseEntry(1999, ['The Matrix']),
        FranchiseEntry(2003, ['The Matrix Reloaded']),
        FranchiseEntry(2003, ['The Matrix Revolutions']),
        FranchiseEntry(2021, ['The Matrix Resurrections']),
      ],
    ),
    FilmFranchise(
      id: 'john-wick',
      name: 'جون ويك',
      queries: ['John Wick'],
      entries: [
        FranchiseEntry(2014, ['John Wick']),
        FranchiseEntry(2017, ['John Wick: Chapter 2']),
        FranchiseEntry(2019, ['John Wick: Chapter 3 - Parabellum']),
        FranchiseEntry(2023, ['John Wick: Chapter 4']),
      ],
    ),
    FilmFranchise(
      id: 'the-godfather',
      name: 'العراب',
      queries: ['Godfather'],
      entries: [
        FranchiseEntry(1972, ['The Godfather']),
        FranchiseEntry(1974, ['The Godfather Part II']),
        FranchiseEntry(1990, ['The Godfather Part III']),
      ],
    ),
    FilmFranchise(
      id: 'indiana-jones',
      name: 'إنديانا جونز',
      queries: ['Indiana Jones'],
      entries: [
        FranchiseEntry(1981, ['Raiders of the Lost Ark', 'Indiana Jones and the Raiders of the Lost Ark']),
        FranchiseEntry(1984, ['Indiana Jones and the Temple of Doom']),
        FranchiseEntry(1989, ['Indiana Jones and the Last Crusade']),
        FranchiseEntry(2008, ['Indiana Jones and the Kingdom of the Crystal Skull']),
        FranchiseEntry(2023, ['Indiana Jones and the Dial of Destiny']),
      ],
    ),
    FilmFranchise(
      id: 'rocky',
      name: 'روكي',
      queries: ['Rocky', 'Creed'],
      entries: [
        FranchiseEntry(1976, ['Rocky']),
        FranchiseEntry(1979, ['Rocky II']),
        FranchiseEntry(1982, ['Rocky III']),
        FranchiseEntry(1985, ['Rocky IV']),
        FranchiseEntry(1990, ['Rocky V']),
        FranchiseEntry(2006, ['Rocky Balboa']),
        FranchiseEntry(2015, ['Creed']),
        FranchiseEntry(2018, ['Creed II']),
        FranchiseEntry(2023, ['Creed III']),
      ],
    ),
    FilmFranchise(
      id: 'rambo',
      name: 'رامبو',
      queries: ['Rambo', 'First Blood'],
      entries: [
        FranchiseEntry(1982, ['First Blood']),
        FranchiseEntry(1985, ['Rambo: First Blood Part II']),
        FranchiseEntry(1988, ['Rambo III']),
        FranchiseEntry(2008, ['Rambo']),
        FranchiseEntry(2019, ['Rambo: Last Blood']),
      ],
    ),
    FilmFranchise(
      id: 'terminator',
      name: 'المدمر',
      queries: ['Terminator'],
      entries: [
        FranchiseEntry(1984, ['The Terminator']),
        FranchiseEntry(1991, ['Terminator 2: Judgment Day']),
        FranchiseEntry(2003, ['Terminator 3: Rise of the Machines']),
        FranchiseEntry(2009, ['Terminator Salvation']),
        FranchiseEntry(2015, ['Terminator Genisys']),
        FranchiseEntry(2019, ['Terminator: Dark Fate']),
      ],
    ),
    FilmFranchise(
      id: 'die-hard',
      name: 'داي هارد',
      queries: ['Die Hard'],
      entries: [
        FranchiseEntry(1988, ['Die Hard']),
        FranchiseEntry(1990, ['Die Hard 2']),
        FranchiseEntry(1995, ['Die Hard with a Vengeance']),
        FranchiseEntry(2007, ['Live Free or Die Hard']),
        FranchiseEntry(2013, ['A Good Day to Die Hard']),
      ],
    ),
    FilmFranchise(
      id: 'the-hunger-games',
      name: 'مباريات الجوع',
      queries: ['Hunger Games'],
      entries: [
        FranchiseEntry(2012, ['The Hunger Games']),
        FranchiseEntry(2013, ['The Hunger Games: Catching Fire']),
        FranchiseEntry(2014, ['The Hunger Games: Mockingjay - Part 1']),
        FranchiseEntry(2015, ['The Hunger Games: Mockingjay - Part 2']),
        FranchiseEntry(2023, ['The Hunger Games: The Ballad of Songbirds & Snakes']),
      ],
    ),
    FilmFranchise(
      id: 'twilight',
      name: 'الشفق',
      queries: ['Twilight'],
      entries: [
        FranchiseEntry(2008, ['Twilight']),
        FranchiseEntry(2009, ['The Twilight Saga: New Moon']),
        FranchiseEntry(2010, ['The Twilight Saga: Eclipse']),
        FranchiseEntry(2011, ['The Twilight Saga: Breaking Dawn - Part 1']),
        FranchiseEntry(2012, ['The Twilight Saga: Breaking Dawn - Part 2']),
      ],
    ),
    FilmFranchise(
      id: 'maze-runner',
      name: 'الطريق المسدود',
      queries: ['Maze Runner'],
      entries: [
        FranchiseEntry(2014, ['The Maze Runner']),
        FranchiseEntry(2015, ['Maze Runner: The Scorch Trials']),
        FranchiseEntry(2018, ['Maze Runner: The Death Cure']),
      ],
    ),
    FilmFranchise(
      id: 'bourne',
      name: 'بورن',
      queries: ['Bourne'],
      entries: [
        FranchiseEntry(2002, ['The Bourne Identity']),
        FranchiseEntry(2004, ['The Bourne Supremacy']),
        FranchiseEntry(2007, ['The Bourne Ultimatum']),
        FranchiseEntry(2012, ['The Bourne Legacy']),
        FranchiseEntry(2016, ['Jason Bourne']),
      ],
    ),
    FilmFranchise(
      id: 'mad-max',
      name: 'ماد ماكس',
      queries: ['Mad Max'],
      entries: [
        FranchiseEntry(1979, ['Mad Max']),
        FranchiseEntry(1981, ['Mad Max 2', 'The Road Warrior']),
        FranchiseEntry(1985, ['Mad Max Beyond Thunderdome']),
        FranchiseEntry(2015, ['Mad Max: Fury Road']),
        FranchiseEntry(2024, ['Furiosa: A Mad Max Saga']),
      ],
    ),
    FilmFranchise(
      id: 'planet-apes',
      name: 'كوكب القردة',
      queries: ['Planet of the Apes'],
      entries: [
        FranchiseEntry(2011, ['Rise of the Planet of the Apes']),
        FranchiseEntry(2014, ['Dawn of the Planet of the Apes']),
        FranchiseEntry(2017, ['War for the Planet of the Apes']),
        FranchiseEntry(2024, ['Kingdom of the Planet of the Apes']),
      ],
    ),
    FilmFranchise(
      id: 'alien',
      name: 'المخلوق الفضائي',
      queries: ['Alien'],
      entries: [
        FranchiseEntry(1979, ['Alien']),
        FranchiseEntry(1986, ['Aliens']),
        FranchiseEntry(1992, ['Alien 3']),
        FranchiseEntry(1997, ['Alien Resurrection']),
        FranchiseEntry(2012, ['Prometheus']),
        FranchiseEntry(2017, ['Alien: Covenant']),
        FranchiseEntry(2024, ['Alien: Romulus']),
      ],
    ),
    FilmFranchise(
      id: 'predator',
      name: 'المفترس',
      queries: ['Predator'],
      entries: [
        FranchiseEntry(1987, ['Predator']),
        FranchiseEntry(1990, ['Predator 2']),
        FranchiseEntry(2010, ['Predators']),
        FranchiseEntry(2018, ['The Predator']),
        FranchiseEntry(2022, ['Prey']),
      ],
    ),
    FilmFranchise(
      id: 'conjuring',
      name: 'الشعوذة',
      queries: ['Conjuring'],
      entries: [
        FranchiseEntry(2013, ['The Conjuring']),
        FranchiseEntry(2016, ['The Conjuring 2']),
        FranchiseEntry(2021, ['The Conjuring: The Devil Made Me Do It']),
      ],
    ),
    FilmFranchise(
      id: 'insidious',
      name: 'إنسيديوس',
      queries: ['Insidious'],
      entries: [
        FranchiseEntry(2010, ['Insidious']),
        FranchiseEntry(2013, ['Insidious: Chapter 2']),
        FranchiseEntry(2015, ['Insidious: Chapter 3']),
        FranchiseEntry(2018, ['Insidious: The Last Key']),
        FranchiseEntry(2023, ['Insidious: The Red Door']),
      ],
    ),
    FilmFranchise(
      id: 'saw',
      name: 'المنشار',
      queries: ['Saw'],
      entries: [
        FranchiseEntry(2004, ['Saw']),
        FranchiseEntry(2005, ['Saw II']),
        FranchiseEntry(2006, ['Saw III']),
        FranchiseEntry(2007, ['Saw IV']),
        FranchiseEntry(2017, ['Jigsaw']),
        FranchiseEntry(2023, ['Saw X']),
      ],
    ),
    FilmFranchise(
      id: 'scream',
      name: 'صرخة',
      queries: ['Scream'],
      entries: [
        FranchiseEntry(1996, ['Scream']),
        FranchiseEntry(1997, ['Scream 2']),
        FranchiseEntry(2000, ['Scream 3']),
        FranchiseEntry(2011, ['Scream 4']),
        FranchiseEntry(2022, ['Scream']),
        FranchiseEntry(2023, ['Scream VI']),
      ],
    ),
    FilmFranchise(
      id: 'resident-evil',
      name: 'ريزدنت إيفل',
      queries: ['Resident Evil'],
      entries: [
        FranchiseEntry(2002, ['Resident Evil']),
        FranchiseEntry(2004, ['Resident Evil: Apocalypse']),
        FranchiseEntry(2007, ['Resident Evil: Extinction']),
        FranchiseEntry(2010, ['Resident Evil: Afterlife']),
        FranchiseEntry(2012, ['Resident Evil: Retribution']),
        FranchiseEntry(2016, ['Resident Evil: The Final Chapter']),
      ],
    ),
    FilmFranchise(
      id: 'final-destination',
      name: 'الوجهة النهائية',
      queries: ['Final Destination'],
      entries: [
        FranchiseEntry(2000, ['Final Destination']),
        FranchiseEntry(2003, ['Final Destination 2']),
        FranchiseEntry(2006, ['Final Destination 3']),
        FranchiseEntry(2009, ['The Final Destination']),
        FranchiseEntry(2011, ['Final Destination 5']),
        FranchiseEntry(2025, ['Final Destination Bloodlines']),
      ],
    ),
    FilmFranchise(
      id: 'toy-story',
      name: 'حكاية لعبة',
      queries: ['Toy Story'],
      entries: [
        FranchiseEntry(1995, ['Toy Story']),
        FranchiseEntry(1999, ['Toy Story 2']),
        FranchiseEntry(2010, ['Toy Story 3']),
        FranchiseEntry(2019, ['Toy Story 4']),
      ],
    ),
    FilmFranchise(
      id: 'shrek',
      name: 'شريك',
      queries: ['Shrek'],
      entries: [
        FranchiseEntry(2001, ['Shrek']),
        FranchiseEntry(2004, ['Shrek 2']),
        FranchiseEntry(2007, ['Shrek the Third']),
        FranchiseEntry(2010, ['Shrek Forever After']),
      ],
    ),
    FilmFranchise(
      id: 'ice-age',
      name: 'العصر الجليدي',
      queries: ['Ice Age'],
      entries: [
        FranchiseEntry(2002, ['Ice Age']),
        FranchiseEntry(2006, ['Ice Age: The Meltdown']),
        FranchiseEntry(2009, ['Ice Age: Dawn of the Dinosaurs']),
        FranchiseEntry(2012, ['Ice Age: Continental Drift']),
        FranchiseEntry(2016, ['Ice Age: Collision Course']),
      ],
    ),
    FilmFranchise(
      id: 'kung-fu-panda',
      name: 'كونغ فو باندا',
      queries: ['Kung Fu Panda'],
      entries: [
        FranchiseEntry(2008, ['Kung Fu Panda']),
        FranchiseEntry(2011, ['Kung Fu Panda 2']),
        FranchiseEntry(2016, ['Kung Fu Panda 3']),
        FranchiseEntry(2024, ['Kung Fu Panda 4']),
      ],
    ),
    FilmFranchise(
      id: 'despicable-me',
      name: 'أنا الحقير',
      queries: ['Despicable Me', 'Minions'],
      entries: [
        FranchiseEntry(2010, ['Despicable Me']),
        FranchiseEntry(2013, ['Despicable Me 2']),
        FranchiseEntry(2015, ['Minions']),
        FranchiseEntry(2017, ['Despicable Me 3']),
        FranchiseEntry(2022, ['Minions: The Rise of Gru']),
        FranchiseEntry(2024, ['Despicable Me 4']),
      ],
    ),
    FilmFranchise(
      id: 'how-to-train-dragon',
      name: 'كيف تروض تنينك',
      queries: ['How to Train Your Dragon'],
      entries: [
        FranchiseEntry(2010, ['How to Train Your Dragon']),
        FranchiseEntry(2014, ['How to Train Your Dragon 2']),
        FranchiseEntry(2019, ['How to Train Your Dragon: The Hidden World']),
      ],
    ),
    FilmFranchise(
      id: 'madagascar',
      name: 'مدغشقر',
      queries: ['Madagascar'],
      entries: [
        FranchiseEntry(2005, ['Madagascar']),
        FranchiseEntry(2008, ['Madagascar: Escape 2 Africa']),
        FranchiseEntry(2012, ["Madagascar 3: Europe's Most Wanted"]),
      ],
    ),
    FilmFranchise(
      id: 'jumanji',
      name: 'جومانجي',
      queries: ['Jumanji'],
      entries: [
        FranchiseEntry(1995, ['Jumanji']),
        FranchiseEntry(2017, ['Jumanji: Welcome to the Jungle']),
        FranchiseEntry(2019, ['Jumanji: The Next Level']),
      ],
    ),
    FilmFranchise(
      id: 'sonic',
      name: 'سونيك',
      queries: ['Sonic the Hedgehog', 'Sonic'],
      entries: [
        FranchiseEntry(2020, ['Sonic the Hedgehog']),
        FranchiseEntry(2022, ['Sonic the Hedgehog 2']),
        FranchiseEntry(2024, ['Sonic the Hedgehog 3']),
      ],
    ),
    FilmFranchise(
      id: 'kingsman',
      name: 'كينجزمان',
      queries: ['Kingsman'],
      entries: [
        FranchiseEntry(2014, ['Kingsman: The Secret Service']),
        FranchiseEntry(2017, ['Kingsman: The Golden Circle']),
        FranchiseEntry(2021, ['The Kings Man', "The King's Man"]),
      ],
    ),
    FilmFranchise(
      id: 'bad-boys',
      name: 'الأولاد الأشقياء',
      queries: ['Bad Boys'],
      entries: [
        FranchiseEntry(1995, ['Bad Boys']),
        FranchiseEntry(2003, ['Bad Boys II']),
        FranchiseEntry(2020, ['Bad Boys for Life']),
        FranchiseEntry(2024, ['Bad Boys: Ride or Die']),
      ],
    ),
    FilmFranchise(
      id: 'men-in-black',
      name: 'الرجال ذوو البدلات السوداء',
      queries: ['Men in Black'],
      entries: [
        FranchiseEntry(1997, ['Men in Black']),
        FranchiseEntry(2002, ['Men in Black II']),
        FranchiseEntry(2012, ['Men in Black 3']),
        FranchiseEntry(2019, ['Men in Black: International']),
      ],
    ),
    FilmFranchise(
      id: 'deadpool',
      name: 'ديدبول',
      queries: ['Deadpool'],
      entries: [
        FranchiseEntry(2016, ['Deadpool']),
        FranchiseEntry(2018, ['Deadpool 2']),
        FranchiseEntry(2024, ['Deadpool & Wolverine']),
      ],
    ),
    // ---------------------------------------------------------- TV series
  // Bozdag Film saga: Ertugrul -> Osman -> Orhan (Cinemana also keeps Arabic-dubbed copies; the Latin-titled ones win).
  FilmFranchise(
    id: 'kurulus',
    name: 'أرطغرل والمؤسس عثمان',
    section: FranchiseSection.series,
    queries: ['Dirilis', 'Kurulus'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2014, ['Diriliş: Ertuğrul', 'Diriliş Ertuğrul', 'Dirilis: Ertugrul', 'Resurrection: Ertugrul'], kind: FranchiseKind.series),
      FranchiseEntry(2019, ['Kuruluş: Osman', 'Kurulus: Osman', 'Establishment: Osman'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['Kuruluş: Orhan', 'Kurulus: Orhan'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'walking-dead',
    name: 'الموتى السائرون',
    section: FranchiseSection.series,
    queries: ['Walking Dead'],
    entries: [
      FranchiseEntry(2010, ['The Walking Dead'], kind: FranchiseKind.series),
      FranchiseEntry(2015, ['Fear the Walking Dead'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['The Walking Dead: World Beyond'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Tales of the Walking Dead'], kind: FranchiseKind.series),
      FranchiseEntry(2023, ['The Walking Dead: Dead City'], kind: FranchiseKind.series),
      FranchiseEntry(2023, ['The Walking Dead: Daryl Dixon'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['The Walking Dead: The Ones Who Live'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'game-of-thrones',
    name: 'صراع العروش',
    section: FranchiseSection.series,
    queries: ['Game of Thrones', 'House of the Dragon', 'Knight of the Seven Kingdoms'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2011, ['Game of Thrones'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['House of the Dragon'], kind: FranchiseKind.series),
      FranchiseEntry(2026, ['A Knight of the Seven Kingdoms'], kind: FranchiseKind.series),
    ],
  ),
  // Live-action Marvel Studios (MCU) Disney+ series. Each show is looked up by its own title.
  FilmFranchise(
    id: 'marvel-series',
    name: 'مسلسلات مارفل',
    section: FranchiseSection.series,
    queries: [
      'WandaVision', 'Falcon and the Winter Soldier', 'Loki', 'Hawkeye', 'Moon Knight', 'Ms. Marvel',
      'She-Hulk', 'Secret Invasion', 'Echo', 'Agatha All Along', 'Daredevil', 'Ironheart', 'Wonder Man',
    ],
    deepSearch: false,
    entries: [
      FranchiseEntry(2021, ['WandaVision'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['The Falcon and the Winter Soldier'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['Loki'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['Hawkeye'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Moon Knight'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Ms. Marvel'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['She-Hulk: Attorney at Law'], kind: FranchiseKind.series),
      FranchiseEntry(2023, ['Secret Invasion'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['Echo'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['Agatha All Along'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['Daredevil: Born Again'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['Ironheart'], kind: FranchiseKind.series),
      FranchiseEntry(2026, ['Wonder Man'], kind: FranchiseKind.series),
    ],
  ),
  // Live-action Star Wars series. Each show is looked up by its own title.
  FilmFranchise(
    id: 'star-wars-series',
    name: 'مسلسلات حرب النجوم',
    section: FranchiseSection.series,
    queries: ['Mandalorian', 'Boba Fett', 'Obi-Wan Kenobi', 'Andor', 'Ahsoka', 'Acolyte', 'Skeleton Crew'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2019, ['The Mandalorian'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['The Book of Boba Fett'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Obi-Wan Kenobi'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Andor'], kind: FranchiseKind.series),
      FranchiseEntry(2023, ['Ahsoka'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['The Acolyte'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['Star Wars: Skeleton Crew', 'Skeleton Crew'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'dexter',
    name: 'دكستر',
    section: FranchiseSection.series,
    queries: ['Dexter'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2006, ['Dexter'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['Dexter: New Blood'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['Dexter: Original Sin'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['Dexter: Resurrection'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'one-chicago',
    name: 'عالم شيكاغو',
    section: FranchiseSection.series,
    queries: ['Chicago Fire', 'Chicago Med'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2012, ['Chicago Fire'], kind: FranchiseKind.series),
      FranchiseEntry(2014, ['Chicago P.D.', 'Chicago PD'], kind: FranchiseKind.series),
      FranchiseEntry(2015, ['Chicago Med'], kind: FranchiseKind.series),
      FranchiseEntry(2017, ['Chicago Justice'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'ncis',
    name: 'إن سي آي إس',
    section: FranchiseSection.series,
    queries: ['NCIS'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2003, ['NCIS', 'NCIS: Naval Criminal Investigative Service'], kind: FranchiseKind.series),
      FranchiseEntry(2009, ['NCIS: Los Angeles'], kind: FranchiseKind.series),
      FranchiseEntry(2014, ['NCIS: New Orleans'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ["NCIS: Hawai'i", 'NCIS: Hawaii'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['NCIS: Tony & Ziva'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'fbi',
    name: 'إف بي آي',
    section: FranchiseSection.series,
    queries: ['FBI'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2018, ['FBI'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['FBI: Most Wanted'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['FBI: International'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'nine-one-one',
    name: 'الطوارئ 9-1-1',
    section: FranchiseSection.series,
    queries: ['9-1-1'],
    deepSearch: false,
    entries: [
      FranchiseEntry(2018, ['9-1-1'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['9-1-1: Lone Star'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['9-1-1: Nashville'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'law-and-order',
    name: 'القانون والنظام',
    section: FranchiseSection.series,
    queries: ['Law & Order'],
    deepSearch: false,
    entries: [
      FranchiseEntry(1990, ['Law & Order'], kind: FranchiseKind.series),
      FranchiseEntry(1999, ['Law & Order: Special Victims Unit', 'Law & Order: SVU'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['Law & Order: Organized Crime'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'star-trek',
    name: 'ستار تريك',
    section: FranchiseSection.series,
    queries: ['Star Trek'],
    deepSearch: false,
    entries: [
      FranchiseEntry(1966, ['Star Trek', 'Star Trek: The Original Series'], kind: FranchiseKind.series),
      FranchiseEntry(1987, ['Star Trek: The Next Generation'], kind: FranchiseKind.series),
      FranchiseEntry(1993, ['Star Trek: Deep Space Nine'], kind: FranchiseKind.series),
      FranchiseEntry(1995, ['Star Trek: Voyager'], kind: FranchiseKind.series),
      FranchiseEntry(2001, ['Star Trek: Enterprise', 'Enterprise'], kind: FranchiseKind.series),
      FranchiseEntry(2017, ['Star Trek: Discovery'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['Star Trek: Picard'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['Star Trek: Lower Decks'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Star Trek: Strange New Worlds'], kind: FranchiseKind.series),
      FranchiseEntry(2026, ['Star Trek: Starfleet Academy'], kind: FranchiseKind.series),
    ],
  ),

    // ---------------------------------------------------------------- anime
  FilmFranchise(
    id: 'demon-slayer',
    name: 'قاتل الشياطين',
    section: FranchiseSection.anime,
    queries: ['Demon Slayer', 'Kimetsu no Yaiba', 'قاتل الشياطيين'],
    entries: [
      FranchiseEntry(2019, ['Kimetsu no Yaiba', 'Demon Slayer: Kimetsu no Yaiba', 'قاتل الشياطيين'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['Kimetsu no Yaiba Movie: Mugen Ressha-hen', 'Demon Slayer: Kimetsu no Yaiba - The Movie: Mugen Train', 'Demon Slayer: Mugen Train']),
      FranchiseEntry(2021, ['The Demon Slayer: Kimetsu no Yaiba Mugen Train Arc TV', 'Demon Slayer: Kimetsu no Yaiba Mugen Train Arc', 'Kimetsu no Yaiba: Mugen Ressha-hen'], kind: FranchiseKind.series),
      FranchiseEntry(2021, ['Demon Slayer: Kimetsu no Yaiba Entertainment District Arc', 'Kimetsu no Yaiba: Yuukaku-hen', 'Demon Slayer Season 2'], kind: FranchiseKind.series),
      FranchiseEntry(2023, ['Demon Slayer: Kimetsu no Yaiba - To the Swordsmith Village', 'Kimetsu no Yaiba: Katanakaji no Sato-hen']),
      FranchiseEntry(2023, ['Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc', 'Kimetsu no Yaiba Season 3'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ['Demon Slayer: Kimetsu no Yaiba - To the Hashira Training', 'Kimetsu no Yaiba: Hashira Geiko-hen']),
      FranchiseEntry(2024, ['Demon Slayer: Kimetsu no Yaiba Hashira Training Arc', 'Kimetsu no Yaiba Season 4'], kind: FranchiseKind.series),
      FranchiseEntry(2025, ['Demon Slayer: Kimetsu no Yaiba - The Movie: Infinity Castle - Part 1: Akaza Returns', 'Demon Slayer: Kimetsu no Yaiba - The Movie: Infinity Castle']),
    ],
  ),
  FilmFranchise(
    id: 'naruto',
    name: 'ناروتو',
    section: FranchiseSection.anime,
    queries: ['Naruto', 'Boruto'],
    entries: [
      FranchiseEntry(2002, ['Naruto'], kind: FranchiseKind.series),
      FranchiseEntry(2004, ['Naruto the Movie: Ninja Clash in the Land of Snow']),
      FranchiseEntry(2005, ['Naruto the Movie 2: Legend of the Stone of Gelel']),
      FranchiseEntry(2006, ['Naruto the Movie 3: Guardians of the Crescent Moon Kingdom']),
      FranchiseEntry(2007, ['Naruto: Shippuden', 'Naruto: Shippûden'], kind: FranchiseKind.series),
      FranchiseEntry(2007, ['Naruto Shippuden the Movie', 'Naruto Shippûden: The Movie']),
      FranchiseEntry(2008, ['Naruto Shippuden the Movie: Bonds', 'Naruto Shippûden The Movie: Bonds']),
      FranchiseEntry(2009, ['Naruto Shippuden the Movie: The Will of Fire', 'Naruto Shippûden: The Movie 3: Inheritors of the Will of Fire']),
      FranchiseEntry(2010, ['Naruto Shippuden the Movie: The Lost Tower', 'Naruto Shippûden: The Lost Tower']),
      FranchiseEntry(2011, ['Naruto Shippuden the Movie: Blood Prison']),
      FranchiseEntry(2012, ['Road to Ninja: Naruto the Movie']),
      FranchiseEntry(2014, ['The Last: Naruto the Movie']),
      FranchiseEntry(2015, ['Boruto: Naruto the Movie']),
      FranchiseEntry(2017, ['Boruto: Naruto Next Generations'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'dragon-ball',
    name: 'دراغون بول',
    section: FranchiseSection.anime,
    queries: ['Dragon Ball', 'Dragon Ball Z', 'Dragonball'],
    entries: [
      FranchiseEntry(1986, ['Dragon Ball'], kind: FranchiseKind.series),
      FranchiseEntry(1986, ['Dragon Ball: Curse of the Blood Rubies', 'Dragon Ball Movie 1: Shen Long no Densetsu']),
      FranchiseEntry(1987, ["Dragon Ball: Sleeping Princess in Devil's Castle", 'Dragon Ball Movie 2: Majinjou no Nemuri Hime']),
      FranchiseEntry(1988, ['Dragon Ball: Mystical Adventure', 'Dragon Ball Movie 3: Makafushigi Daibouken']),
      FranchiseEntry(1996, ['Dragon Ball Z'], kind: FranchiseKind.series),  // aired 1989; Cinemana stores 1996
      FranchiseEntry(1989, ['Dragon Ball Z: Dead Zone']),
      FranchiseEntry(1990, ["Dragon Ball Z: The World's Strongest"]),
      FranchiseEntry(1990, ['Dragon Ball Z: The Tree of Might', 'Dragon Ball Z: Tree of Might']),
      FranchiseEntry(1990, ['Dragon Ball Z: Bardock - The Father of Goku', 'Dragon Ball Z Special 1: Tatta Hitori no Saishuu Kessen']),
      FranchiseEntry(1991, ['Dragon Ball Z: Lord Slug']),
      FranchiseEntry(1991, ["Dragon Ball Z: Cooler's Revenge"]),
      FranchiseEntry(1992, ['Dragon Ball Z: The Return of Cooler']),
      FranchiseEntry(1992, ['Dragon Ball Z: Super Android 13!', 'Dragon Ball Z: Super Android 13']),
      FranchiseEntry(1993, ['Dragon Ball Z: Broly - The Legendary Super Saiyan']),
      FranchiseEntry(1993, ['Dragon Ball Z: The History of Trunks']),
      FranchiseEntry(1993, ['Dragon Ball Z: Bojack Unbound']),
      FranchiseEntry(1994, ['Dragon Ball Z: Broly - Second Coming']),
      FranchiseEntry(1994, ['Dragon Ball Z: Bio-Broly']),
      FranchiseEntry(1995, ['Dragon Ball Z: Fusion Reborn']),
      FranchiseEntry(1995, ['Dragon Ball Z: Wrath of the Dragon']),
      FranchiseEntry(1996, ['Dragon Ball GT'], kind: FranchiseKind.series),
      FranchiseEntry(2009, ['Dragon Ball Z Kai', 'Dragon Ball Kai'], kind: FranchiseKind.series),
      FranchiseEntry(2013, ['Dragon Ball Z: Battle of Gods']),
      FranchiseEntry(2015, ["Dragon Ball Z: Resurrection 'F'"]),
      FranchiseEntry(2015, ['Dragon Ball Super'], kind: FranchiseKind.series),
      FranchiseEntry(2018, ['Super Dragon Ball Heroes', 'Dragon Ball Heroes'], kind: FranchiseKind.series),
      FranchiseEntry(2018, ['Dragon Ball Super: Broly', 'Dragon Ball Super Movie: Broly']),
      FranchiseEntry(2022, ['Dragon Ball Super: Super Hero']),
      FranchiseEntry(2024, ['Dragon Ball Daima'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'one-piece',
    name: 'ون بيس',
    section: FranchiseSection.anime,
    queries: ['One Piece'],
    entries: [
      FranchiseEntry(1999, ['One Piece'], kind: FranchiseKind.series),
      FranchiseEntry(2000, ['One Piece: The Movie', 'One Piece Movie 1']),
      FranchiseEntry(2001, ['One Piece: Clockwork Island Adventure', 'One Piece: Adventure on Nejimaki Island', 'One Piece Movie 2: Nejimaki-jima no Daibouken']),
      FranchiseEntry(2002, ["One Piece: Chopper's Kingdom on the Island of Strange Animals", 'One piece: Chinjou shima no chopper oukoku', 'One Piece Movie 3: Chinjuu-jima no Chopper Oukoku']),
      FranchiseEntry(2003, ['One Piece: Dead End Adventure', 'One piece: Dead end no bôken', 'One Piece Movie 4: Dead End no Bouken']),
      FranchiseEntry(2004, ['One Piece: The Curse of the Sacred Sword', 'One piece: Norowareta seiken', 'One Piece Movie 5: Norowareta Seiken']),
      FranchiseEntry(2005, ['One Piece: Baron Omatsuri and the Secret Island', 'One Piece Movie 6: Omatsuri Danshaku to Himitsu no Shima']),
      FranchiseEntry(2006, ['One Piece: Giant Mecha Soldier of Karakuri Castle', "One Piece: Karakuri Castle's Mecha Giant Soldier", 'One Piece Movie 7: Karakuri-jou no Mecha Kyohei']),
      FranchiseEntry(2006, ['One Piece: The Desert Princess and the Pirates: Adventures in Alabasta', 'One Piece: Episode of Alabaster - Sabaku no Ojou to Kaizoku Tachi', 'One Piece Movie 8: Episode of Alabasta - Sabaku no Oujo to Kaizoku-tachi']),  // released 2007; Cinemana stores 2006
      FranchiseEntry(2008, ['One Piece: Episode of Chopper Plus: Bloom in Winter, Miracle Sakura', 'One Piece: Episode of Chopper: Bloom in the Winter, Miracle Sakura', 'One Piece Movie 9: Episode of Chopper Plus - Fuyu ni Saku, Kiseki no Sakura']),
      FranchiseEntry(2009, ['One Piece Film: Strong World', 'One Piece: Strong World']),
      FranchiseEntry(2012, ['One Piece: Episode of Luffy - Adventure on Hand Island', 'One Piece: Episode of Luffy - Hand Island No Bouken']),
      FranchiseEntry(2012, ['One Piece: Episode of Nami - Tears of a Navigator and the Bonds of Friends', 'One Piece: Episode of Nami - Koukaishi no Namida to Nakama no Kizuna']),
      FranchiseEntry(2012, ['One Piece Film: Z', 'One Piece Film Z']),
      FranchiseEntry(2013, ['One Piece: Episode of Merry - The Tale of One More Friend', 'One Piece: Episode of Merry - Mou Hitori no Nakama no Monogatari']),
      FranchiseEntry(2014, ["One Piece 3D2Y: Overcome Ace's Death! Luffy's Vow to His Friends", 'One Piece 3D2Y: Ace no shi wo Koete! Luffy Nakama Tono Chikai']),
      FranchiseEntry(2015, ['One Piece: Episode of Sabo'], kind: FranchiseKind.series),  // TV special, filed as a series
      FranchiseEntry(2015, ['One Piece: Adventure of Nebulandia']),
      FranchiseEntry(2016, ['One Piece: Heart of Gold'], kind: FranchiseKind.series),  // TV special, filed as a series
      FranchiseEntry(2016, ['One Piece Film: Gold', 'One Piece Film Gold']),
      FranchiseEntry(2017, ['One Piece: Episode of East Blue']),
      FranchiseEntry(2018, ['One Piece: Episode of Skypiea', 'One Piece: Episode of Sorajima'], kind: FranchiseKind.series),  // TV special, filed as a series
      FranchiseEntry(2020, ['One Piece: Stampede', 'One Piece Movie 14: Stampede']),  // released 2019; Cinemana stores 2020
      FranchiseEntry(2022, ['One Piece Film: Red']),
      FranchiseEntry(2024, ['One Piece Log: Fish-Man Island Saga', 'One Piece: Gyojin Tou-hen'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'detective-conan',
    name: 'المحقق كونان',
    section: FranchiseSection.anime,
    queries: ['Detective Conan', 'Meitantei Conan', 'Detective Conan Movie'],
    entries: [
      FranchiseEntry(1996, ['Detective Conan', 'Case Closed', 'Meitantei Conan'], kind: FranchiseKind.series),
      FranchiseEntry(1997, ['Detective Conan: The Time Bombed Skyscraper']),
      FranchiseEntry(1998, ['Detective Conan: The Fourteenth Target', 'Meitantei Conan: 14 banme no target']),
      FranchiseEntry(1999, ['Detective Conan: The Last Wizard of the Century', 'Meitantei Conan: Seiki matsu no majutsushi']),
      FranchiseEntry(2000, ['Detective Conan: Captured in Her Eyes']),
      FranchiseEntry(2001, ['Detective Conan: Countdown to Heaven', 'Meitantei Conan: Tengoku no countdown']),
      FranchiseEntry(2002, ['Detective Conan: The Phantom of Baker Street']),
      FranchiseEntry(2003, ['Detective Conan: Crossroad in the Ancient Capital', 'Meitantei Conan: Meikyuu no crossroad']),
      FranchiseEntry(2004, ['Detective Conan: Magician of the Silver Sky', 'Meitantei Conan: Ginyoku no kijutsushi']),
      FranchiseEntry(2005, ['Detective Conan: Strategy Above the Depths']),
      FranchiseEntry(2006, ["Detective Conan: The Private Eyes' Requiem"]),
      FranchiseEntry(2007, ['Detective Conan: Jolly Roger in the Deep Azure']),
      FranchiseEntry(2008, ['Detective Conan: Full Score of Fear', 'Detective Conan movie 12: Full Score of Fear']),
      FranchiseEntry(2009, ['Detective Conan: The Raven Chaser']),
      FranchiseEntry(2009, ['Lupin III vs. Detective Conan']),  // TV special
      FranchiseEntry(2010, ['Detective Conan: The Lost Ship in the Sky']),
      FranchiseEntry(2011, ['Detective Conan: Quarter of Silence']),
      FranchiseEntry(2012, ['Detective Conan: The Eleventh Striker']),
      FranchiseEntry(2013, ['Detective Conan: Private Eye in the Distant Sea']),
      FranchiseEntry(2013, ['Lupin the 3rd vs. Detective Conan: The Movie', 'Lupin III vs. Conan']),
      FranchiseEntry(2014, ['Detective Conan: Dimensional Sniper', 'Detective Conan: The Sniper from Another Dimension']),
      FranchiseEntry(2014, ['The Disappearance of Conan Edogawa: The Worst Two Days in History', 'Edogawa Conan Shissou Jiken: Shijou Saiaku no Futsukakan']),  // TV special
      FranchiseEntry(2015, ['Detective Conan: Sunflowers of Inferno']),
      FranchiseEntry(2016, ['Detective Conan: Episode One - The Great Detective Turned Small', 'Meitantei Conan: Episode One - Chiisaku Natta Meitantei']),  // TV special
      FranchiseEntry(2016, ['Detective Conan: The Darkest Nightmare', 'Detective Conan Movie 20: The Darkest Nightmare']),
      FranchiseEntry(2017, ['Detective Conan: The Crimson Love Letter', 'Detective Conan: Crimson Love Letter', 'Detective Conan Movie 21: The Crimson Love Letter']),
      FranchiseEntry(2018, ['Detective Conan: Zero the Enforcer', 'Detective Conan Movie 22: Zero The Enforcer', "Detective Conan Movie 22: Zero's Executioner"]),
      FranchiseEntry(2019, ['Detective Conan: The Fist of Blue Sapphire', 'Detective Conan Movie 23: The Fist of Blue Sapphire']),
      FranchiseEntry(2021, ['Detective Conan: The Scarlet Bullet', 'Detective Conan Movie 24: The Scarlet Bullet']),
      FranchiseEntry(2021, ['Detective Conan: The Scarlet Alibi']),
      FranchiseEntry(2022, ["Detective Conan: Zero's Tea Time", 'Detective Conan: Zero no Tea Time'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Detective Conan: The Culprit Hanazawa'], kind: FranchiseKind.series),
      FranchiseEntry(2022, ['Detective Conan: The Bride of Halloween', 'Detective Conan Movie 25: Halloween no Hanayome']),
      FranchiseEntry(2023, ['Detective Conan: Black Iron Submarine', 'Meitantei Conan Movie 26: Kurogane no Submarine']),
      FranchiseEntry(2024, ['Detective Conan: The Million-Dollar Pentagram']),
      FranchiseEntry(2025, ['Detective Conan: One-Eyed Flashback', 'Detective Conan Movie 28: One-Eyed Flashback']),
    ],
  ),
  FilmFranchise(
    id: 'pokemon',
    name: 'بوكيمون',
    section: FranchiseSection.anime,
    queries: ['Pokemon', 'Pokémon'],
    entries: [
      FranchiseEntry(1997, ['Pokémon', 'Pokemon'], kind: FranchiseKind.series),
      FranchiseEntry(2019, ['Pokémon: Mewtwo Strikes Back - Evolution']),
      FranchiseEntry(2019, ['Pokémon Journeys: The Series', 'Pokemon (2019)'], kind: FranchiseKind.series),
      FranchiseEntry(2020, ['Pokémon the Movie: Secrets of the Jungle', 'Pokemon Movie 23: Koko']),
      FranchiseEntry(2022, ['Pokémon: The Arceus Chronicles', 'Pokemon (2019): Kami to Yobareshi Arceus']),
      FranchiseEntry(2023, ['Pokémon Ultimate Journeys: The Series', 'To Be a Pokémon Master: Ultimate Journeys: The Series'], kind: FranchiseKind.series),
      FranchiseEntry(2023, ['Pokémon Concierge', 'Pokemon Concierge'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'attack-on-titan',
    name: 'هجوم العمالقة',
    section: FranchiseSection.anime,
    queries: ['Shingeki no Kyojin', 'Attack on Titan'],
    entries: [
      FranchiseEntry(2013, ['Attack on Titan', 'Shingeki no Kyojin'], kind: FranchiseKind.series),
      FranchiseEntry(2014, ['Attack on Titan Part 1: Crimson Bow and Arrow', 'Shingeki no Kyojin Movie 1: Guren no Yumiya']),
      FranchiseEntry(2015, ['Attack on Titan Part 2: Wings of Freedom', 'Shingeki no Kyojin Movie 2: Jiyuu no Tsubasa']),
      FranchiseEntry(2015, ['Attack on Titan: Junior High'], kind: FranchiseKind.series),
      FranchiseEntry(2018, ['Attack on Titan Season 2 Movie: The Roar of Awakening', 'Shingeki no Kyojin Season 2 Movie: Kakusei no Houkou']),
      FranchiseEntry(2020, ['Attack on Titan: Chronicle', 'Shingeki no Kyojin: Chronicle']),
      FranchiseEntry(2024, ['Attack on Titan: The Last Attack']),
    ],
  ),
  FilmFranchise(
    id: 'my-hero-academia',
    name: 'أكاديمية بطلي',
    section: FranchiseSection.anime,
    queries: ['Boku no Hero Academia', 'My Hero Academia'],
    entries: [
      FranchiseEntry(2016, ['My Hero Academia', 'Boku no Hero Academia'], kind: FranchiseKind.series),
      FranchiseEntry(2018, ['My Hero Academia: Two Heroes', 'Boku no Hero Academia the Movie', 'Boku no Hero Academia the Movie: Futari no Hero']),
      FranchiseEntry(2020, ['My Hero Academia: Heroes Rising', 'Boku no Hero Academia the Movie 2: Heroes:Rising', 'My Hero Academia the Movie 2: Heroes:Rising']),  // released 2019; Cinemana stores 2020
      FranchiseEntry(2021, ["My Hero Academia: World Heroes' Mission", "Boku no Hero Academia the Movie 3: World Heroes' Mission"]),
      FranchiseEntry(2024, ['My Hero Academia: Memories', 'Boku no Hero Academia: Memories'], kind: FranchiseKind.series),
      FranchiseEntry(2024, ["My Hero Academia: You're Next", "Boku no Hero Academia the Movie 4: You're Next"]),
      FranchiseEntry(2025, ['My Hero Academia: Vigilantes', 'Vigilante: Boku no Hero Academia Illegals'], kind: FranchiseKind.series),
    ],
  ),
  FilmFranchise(
    id: 'bleach',
    name: 'بليتش',
    section: FranchiseSection.anime,
    queries: ['Bleach'],
    entries: [
      FranchiseEntry(2004, ['Bleach'], kind: FranchiseKind.series),
      FranchiseEntry(2006, ['Bleach: Memories of Nobody']),
      FranchiseEntry(2007, ['Bleach: The DiamondDust Rebellion', 'Bleach the Movie 2: The Diamond Dust Rebellion', 'Bleach Movie 2: The DiamondDust Rebellion']),
      FranchiseEntry(2008, ['Bleach: Fade to Black', 'Bleach Movie 3: Fade to Black', 'Bleach: Fade to Black, I Call Your Name']),
      FranchiseEntry(2010, ['Bleach: Hell Verse', 'Bleach the Movie 4: Hell Verse', 'Bleach Movie 4: Jigoku-hen']),
    ],
  ),
  FilmFranchise(
    id: 'sword-art-online',
    name: 'سورد آرت أونلاين',
    section: FranchiseSection.anime,
    queries: ['Sword Art Online'],
    entries: [
      FranchiseEntry(2012, ['Sword Art Online'], kind: FranchiseKind.series),
      FranchiseEntry(2013, ['Sword Art Online: Extra Edition']),
      FranchiseEntry(2017, ['Sword Art Online the Movie: Ordinal Scale', 'Sword Art Online: Ordinal Scale', 'Gekijo-ban Sword Art Online Movie: Ordinal Scale']),
      FranchiseEntry(2021, ['Sword Art Online Progressive: Aria of a Starless Night', 'Sword Art Online: Progressive Movie - Hoshi Naki Yoru no Aria']),
      FranchiseEntry(2022, ['Sword Art Online Progressive: Scherzo of Deep Night', 'Sword Art Online: Progressive Movie - Kuraki Yuuyami no Scherzo']),
    ],
  ),
  FilmFranchise(
    id: 'evangelion',
    name: 'إيفانجليون',
    section: FranchiseSection.anime,
    queries: ['Evangelion'],
    entries: [
      FranchiseEntry(1995, ['Neon Genesis Evangelion'], kind: FranchiseKind.series),
      FranchiseEntry(1997, ['The End of Evangelion', 'Neon Genesis Evangelion: The End of Evangelion']),
      FranchiseEntry(2007, ['Evangelion: 1.0 You Are (Not) Alone', 'Evangelion: 1.0: You Are (Not) Alone']),
      FranchiseEntry(2009, ['Evangelion: 2.0 You Can (Not) Advance']),
      FranchiseEntry(2012, ['Evangelion: 3.0 You Can (Not) Redo', 'Evangelion Shin']),
      FranchiseEntry(2021, ['Evangelion: 3.0+1.0 Thrice Upon a Time', 'Evangelion: 3.0+1.01 Thrice Upon a Time']),
    ],
  ),
  ];

  /// Normalised for comparison: lower case, "&" as "and", punctuation and
  /// extra spaces removed ("Tokyo Drift" with or without its colon).
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll('³', ' 3')
      .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// This franchise's titles found in [results], in release order, one per
  /// entry. Anything that is not one of the listed titles is left out.
  List<CinemanaItem> pick(Iterable<CinemanaItem> results) {
    final wanted = [
      for (final e in entries) {for (final t in e.titles) normalize(t)},
    ];
    final chosen = List<CinemanaItem?>.filled(entries.length, null);
    for (final item in results) {
      final year = int.tryParse(item.year.trim());
      if (year == null) continue;
      final kind = item.isSeries ? FranchiseKind.series : FranchiseKind.movie;
      // Cinemana sometimes swaps the English and Arabic title fields.
      final names = {normalize(item.enTitle), normalize(item.arTitle)}..remove('');
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        if (e.kind != kind || (e.year - year).abs() > 1) continue;
        if (!names.any(wanted[i].contains)) continue;
        final current = chosen[i];
        // Prefer the entry with its original (Latin) English title over a
        // dubbed copy filed under an Arabic one.
        if (current == null || (!_latin(current.enTitle) && _latin(item.enTitle))) chosen[i] = item;
        break;
      }
    }
    return chosen.whereType<CinemanaItem>().toList();
  }

  /// "8 أفلام", "4 مسلسلات", or for a mix "3 مسلسلات • 12 فيلماً".
  static String countLabel(List<CinemanaItem> items) {
    final series = items.where((i) => i.isSeries).length;
    final films = items.length - series;
    final parts = [
      if (series > 0) _arabicCount(series, 'مسلسل واحد', 'مسلسلان', 'مسلسلات', 'مسلسلاً'),
      if (films > 0) _arabicCount(films, 'فيلم واحد', 'فيلمان', 'أفلام', 'فيلماً'),
    ];
    return parts.join(' • ');
  }

  static String _arabicCount(int n, String one, String two, String few, String many) {
    if (n == 1) return one;
    if (n == 2) return two;
    if (n <= 10) return '$n $few';
    return '$n $many';
  }

  static bool _latin(String s) => RegExp('[A-Za-z]').hasMatch(s);
}
