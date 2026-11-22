import 'package:flutter/material.dart';

/// M1 placeholder trailer.
/// Every mock title points at the same public sample video so the inline
/// trailer player + expand-to-full-player flow is testable end to end.
/// Milestone 2 replaces this with the real per-anime trailer resolver
/// (AniList trailer field / YouTube).
const String kPlaceholderTrailerUrl =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/'
    'BigBuckBunny.mp4';

class Anime {
  const Anime({
    required this.id,
    required this.title,
    required this.rating,
    required this.year,
    required this.episodeCount,
    required this.genres,
    required this.synopsis,
    required this.gradient,
    this.trailerUrl,
    this.currentEpisode,
    this.minutesLeft,
    this.isSaved = false,
  });

  final String id;
  final String title;
  final double rating;
  final int year;
  final int episodeCount;
  final List<String> genres;
  final String synopsis;
  final List<Color> gradient;
  final String? trailerUrl;

  /// Continue Watching state (null = not started).
  final int? currentEpisode;
  final int? minutesLeft;
  final bool isSaved;

  double get progress {
    if (currentEpisode == null || episodeCount == 0) return 0;
    return (currentEpisode! / episodeCount).clamp(0.0, 1.0);
  }

  Anime copyWith({bool? isSaved, int? currentEpisode, int? minutesLeft}) {
    return Anime(
      id: id,
      title: title,
      rating: rating,
      year: year,
      episodeCount: episodeCount,
      genres: genres,
      synopsis: synopsis,
      gradient: gradient,
      trailerUrl: trailerUrl,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      minutesLeft: minutesLeft ?? this.minutesLeft,
      isSaved: isSaved ?? this.isSaved,
    );
  }
}

class Episode {
  const Episode({
    required this.number,
    required this.title,
    required this.duration,
  });

  final int number;
  final String title;
  final String duration;
}

class ProviderSource {
  const ProviderSource({
    required this.name,
    required this.tagline,
    required this.enabled,
    this.preferred = false,
  });

  final String name;
  final String tagline;
  final bool enabled;
  final bool preferred;

  ProviderSource copyWith({bool? enabled, bool? preferred}) {
    return ProviderSource(
      name: name,
      tagline: tagline,
      enabled: enabled ?? this.enabled,
      preferred: preferred ?? this.preferred,
    );
  }
}

/// Mock catalogue (M1). Real data comes from AniList + Miruro in M2.
List<Anime> mockCatalogue() {
  return <Anime>[
    const Anime(
      id: 'demon-crest',
      title: 'Demon Crest: Blood Moon',
      rating: 4.8,
      year: 2024,
      episodeCount: 12,
      genres: <String>['Action', 'Demons', 'Fantasy'],
      synopsis:
          'When the blood moon rises, a cursed swordsman must break the pact '
          'that binds his soul to the demon realm — before the last gate opens '
          'and the night swallows the human world whole.',
      gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      trailerUrl: kPlaceholderTrailerUrl,
      currentEpisode: 7,
      minutesLeft: 9,
    ),
    const Anime(
      id: 'spy-codex',
      title: 'SPY×CODEX: Phantom Protocol',
      rating: 4.7,
      year: 2024,
      episodeCount: 24,
      genres: <String>['Action', 'Thriller', 'Sci-Fi'],
      synopsis:
          'A covert operative known only as Codex is pulled back into the '
          'shadows after a classified file resurfaces, linking to a forgotten '
          'experiment that blurs the line between human and machine. As rival '
          'agents hunt him across neon-lit cities, he must navigate deception '
          'and trust to uncover the truth before the protocol reactivates.',
      gradient: <Color>[Color(0xFF0F3A4D), Color(0xFF0A1420)],
      trailerUrl: kPlaceholderTrailerUrl,
      currentEpisode: 5,
      minutesLeft: 12,
    ),
    const Anime(
      id: 'jujutsu-warden',
      title: 'Jujutsu Warden',
      rating: 4.6,
      year: 2023,
      episodeCount: 24,
      genres: <String>['Action', 'Supernatural'],
      synopsis:
          'A blindfolded warden guards the boundary between the living world '
          'and the cursed spirits that hunger beyond it.',
      gradient: <Color>[Color(0xFF2A2A3A), Color(0xFF101018)],
      trailerUrl: kPlaceholderTrailerUrl,
      currentEpisode: 5,
      minutesLeft: 12,
    ),
    const Anime(
      id: 'cyber-ninja',
      title: 'Cyber Ninja 2099',
      rating: 4.5,
      year: 2024,
      episodeCount: 12,
      genres: <String>['Sci-Fi', 'Action'],
      synopsis:
          'In Neo-Kyoto 2099, a rogue ninja-hacker takes on the megacorp that '
          'owns the city’s memories.',
      gradient: <Color>[Color(0xFF0B4D5C), Color(0xFF0A0A13)],
      trailerUrl: kPlaceholderTrailerUrl,
      currentEpisode: 2,
      minutesLeft: 18,
    ),
    const Anime(
      id: 'skybound-sailors',
      title: 'Skybound Sailors',
      rating: 4.7,
      year: 2023,
      episodeCount: 36,
      genres: <String>['Adventure', 'Fantasy'],
      synopsis:
          'A crew of sky-pirates sails the cloud seas in search of the last '
          'floating island.',
      gradient: <Color>[Color(0xFF3A6EA5), Color(0xFF12233D)],
      trailerUrl: kPlaceholderTrailerUrl,
      currentEpisode: 10,
      minutesLeft: 4,
    ),
    const Anime(
      id: 'mecha-rebellion',
      title: 'Mecha Rebellion',
      rating: 4.4,
      year: 2024,
      episodeCount: 12,
      genres: <String>['Mecha', 'Action'],
      synopsis:
          'The last free pilots rise against the machine empire that outlawed '
          'human-piloted mechs.',
      gradient: <Color>[Color(0xFF4D4D5C), Color(0xFF14141C)],
      trailerUrl: kPlaceholderTrailerUrl,
    ),
    const Anime(
      id: 'summer-phantom',
      title: 'Summer Phantom',
      rating: 4.3,
      year: 2024,
      episodeCount: 13,
      genres: <String>['Romance', 'Drama'],
      synopsis:
          'One summer, one ghost, and the girl who can see her — a story '
          'about letting go.',
      gradient: <Color>[Color(0xFF7A5A8C), Color(0xFF241A2E)],
      trailerUrl: kPlaceholderTrailerUrl,
    ),
    const Anime(
      id: 'necro-school',
      title: 'Necro School Days',
      rating: 4.2,
      year: 2023,
      episodeCount: 12,
      genres: <String>['Horror', 'School'],
      synopsis:
          'The new transfer student is dead. Nobody at school seems to mind — '
          'except her.',
      gradient: <Color>[Color(0xFF2E1A4D), Color(0xFF0E0A18)],
      trailerUrl: kPlaceholderTrailerUrl,
    ),
    const Anime(
      id: 'drifting-blade',
      title: 'Drifting Blade',
      rating: 4.6,
      year: 2024,
      episodeCount: 24,
      genres: <String>['Action', 'Samurai'],
      synopsis:
          'A wandering swordsman with no master cuts a path through a country '
          'at war with itself.',
      gradient: <Color>[Color(0xFF5C3A1A), Color(0xFF1C120A)],
      trailerUrl: kPlaceholderTrailerUrl,
    ),
  ];
}

List<Episode> mockEpisodes(Anime anime) {
  const List<String> titles = <String>[
    'Infiltration Protocol',
    'Ghost in the Network',
    'Neon Blackout',
    'The Codex Awakens',
    'Crimson Oath',
    'Silent Exchange',
    'Blood Moon Rising',
    'The Last Gate',
  ];
  const List<String> durations = <String>[
    '23:12',
    '24:05',
    '22:58',
    '24:31',
    '23:47',
    '24:02',
    '23:19',
    '24:44',
  ];
  final int count = anime.episodeCount < 8 ? anime.episodeCount : 8;
  return List<Episode>.generate(
    count,
    (int i) => Episode(
      number: i + 1,
      title: titles[i % titles.length],
      duration: durations[i % durations.length],
    ),
  );
}

List<ProviderSource> defaultSources() {
  return const <ProviderSource>[
    ProviderSource(
      name: 'Miruro',
      tagline: '1080p • Sub • Fast',
      enabled: true,
      preferred: true,
    ),
    ProviderSource(
      name: 'AniKoto',
      tagline: '1080p • Sub • Stable',
      enabled: true,
    ),
    ProviderSource(
      name: 'AllAnime',
      tagline: '720p • Sub/Dub • Standard',
      enabled: true,
    ),
    ProviderSource(
      name: 'AnimeKai',
      tagline: '1080p • Sub • Backup',
      enabled: true,
    ),
    ProviderSource(
      name: 'ReAnime',
      tagline: '720p • Sub',
      enabled: false,
    ),
    ProviderSource(
      name: 'AniZone',
      tagline: '1080p • Sub',
      enabled: false,
    ),
  ];
}
