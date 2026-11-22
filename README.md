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
