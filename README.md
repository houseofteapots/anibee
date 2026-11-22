# AniBee

Personal iOS-only anime app. Miruro-linked, AniList-powered. Not for
distribution — built for one user, sideloaded with ESign.

- **Home**: hero banner, Continue Watching, Trending, Top Airing.
- **Detail**: banner plays the **trailer preview inline via libmpv**
  (media_kit); a button on the side of the banner (or tapping the banner)
  opens the same player full-screen. Server picker sits **above** the
  synopsis. Episodes list with per-episode download buttons.
- **Collection**: My List (saved) + Continue Watching.
- **Search**: title search + genre chips.
- **Settings**: Accounts (AniList + MyAnimeList), Appearance (theme
  Dark/Light/System + accent color chooser), Player settings (subtitles:
  font/size/color/background/position/delay, double-tap seek, gestures,
  speed, hardware decoding), Skip Intro (AniSkip), Servers (preferred
  server, fallback providers, Sources list with reorder), Downloads
  (quality, Wi-Fi only), Debrid (TorBox + Real-Debrid API keys),
  App Lock (4-digit PIN + Face ID).

Design: Frost Glass style, dark mode default, **solid** dark cards in dark
mode (no glassy panels), liquid glass **only** on the bottom navigation
pill. Display name **AniBee**, bundle id `com.toji.anibee`. The in-app
logo loads from `https://raw.githubusercontent.com/sezkc16/anibee/main/assets/logo.jpg`
with the bundled `assets/logo.jpg` as fallback (home-screen icon stays
bundled — iOS rule).

## Milestone 1 (this build)

UI shell + navigation + settings state + inline trailer player, on mock
data. Services (Miruro on-device resolve, AniList GraphQL, AniSkip,
MyAnimeList) are stubbed in `lib/services/stubs.dart`. The trailer is the
public Big Buck Bunny sample (`kPlaceholderTrailerUrl`) so the inline /
full-player flow is testable; milestone 2 replaces it with the real
trailer resolver and episode streams.

## Build

Push to `main` → GitHub Actions builds the unsigned IPA
(`.github/workflows/ios.yml`, Flutter 3.47.7, Xcode latest-stable).
Sign the IPA with ESign and install.

## Remote fix system (M1)

Provider definitions (domains, endpoints, mirrors) live in ONE public JSON:
`https://raw.githubusercontent.com/sezkc16/anibee-config/main/providers.json`
(repo: `sezkc16/anibee-config`, public — the app repo is private, so its
raw URL would 404 without auth).

- The app fetches it on launch (5 s timeout), caches the last-good copy,
  and falls back to the bundled `assets/providers.json` when offline.
- `lib/services/provider_config.dart` — loader, mirror rotation
  (next Miruro mirror on failure), provider fallback (Miruro down → next
  enabled provider). Settings > About shows `Provider config vN • remote|cached|bundled`.
- **One JSON fix updates every install:** domain/endpoint change → edit
  `providers.json`, bump `version`, every AniBee install picks it up on
  next launch, no app update. Big changes (redesign, stricter Cloudflare)
  still need an app update.

## Episode list (M1)

- Long anime (> 24 episodes): 5-column NUMBER grid (AniWaves style) —
  Sub & Dub filter, range dropdown (001-100, 101-200...), "Find number"
  search, grid/list toggle. See `lib/widgets/episode_list.dart`.
- Short anime: Miruro-style CARDS — thumbnail with "EP n" badge, title,
  2-line synopsis, date, subtitle icon; sort, watched/eye toggle, grid
  toggle; next-episode countdown bar at the bottom when ongoing.
- Sources stay plain default order (Miruro, AniKoto, AllAnime...),
  user-reorderable — no episode-count ranking.
