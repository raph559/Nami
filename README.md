<p align="center">
  <img src="app/Icon.png" width="128" height="128" alt="Nami icon">
</p>

<h1 align="center">Nami</h1>

<p align="center">
  Stream anime from torrents on iPhone, Android and Windows, with AniList sync.<br>
  Everything runs on the device: no server, no PC, works on Wi-Fi and cellular.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue"></a>
  <img alt="iOS, Android, Windows" src="https://img.shields.io/badge/iOS%20%C2%B7%20Android%20%C2%B7%20Windows-black">
  <img alt="Flutter" src="https://img.shields.io/badge/app-Flutter-02569B">
  <img alt="Go" src="https://img.shields.io/badge/engine-Go-00ADD8">
</p>

---

## Features

- **AniList**: log in, see what you are watching, browse the season and trending anime,
  search with genre filters. Episodes are marked as watched on AniList after 85 % of an episode.
- **Extensions**: sources come from extension repositories in the same format as
  [Hayase](https://hayase.watch) extensions. Nami ships with **no** sources; add the
  repositories you want in Settings.
- **Source picker**: release names are read (group, quality, codec, audio, full season) and
  one source is recommended, based on seeders, your preferred quality and original audio.
- **Torrent engine on the device**: playback starts while the torrent downloads,
  with pieces fetched around the playback position. Nothing is kept after you close the player.
- **mpv player**: MKV, HEVC, ASS subtitles, audio and subtitle track selection,
  10 s seeking, an 85 s intro skip and a next-episode button. Keyboard shortcuts on desktop.
- **French and English** interface, and a choice of romaji, English or Japanese titles.

See [docs/ROADMAP.md](docs/ROADMAP.md) for what is coming next.

## Install

Take the file for your device from [Releases](../../releases):

| Device | File | Notes |
|---|---|---|
| iPhone, iPad | `Nami-<version>.ipa` | Unsigned. Sideload it with LiveContainer, SideStore, AltStore or xtool. With a free Apple account, sideloaded apps must be re-signed every 7 days. |
| Android phone | `Nami-<version>-arm64.apk` | Allow installs from your browser or file manager when asked. |
| Android emulator, x86_64 | `Nami-<version>-x86_64.apk` | |
| Windows 10/11, x64 | `Nami-<version>-windows.zip` | Unzip and run `nami.exe`. Windows may ask to allow network access for the torrent engine. |

### First launch

1. **Settings → AniList**: log in.
2. **Settings → Extensions**: paste the URL of an extension repository (`…/index.json`)
   and enable the sources you want.
3. Open an anime, pick an episode, choose a source.

## How it works

```
┌────────────────────────── Nami (Flutter) ──────────────────────────┐
│ AniList GraphQL ──────── browse, list, progress sync               │
│ api.ani.zip ──────────── AniDB / TVDB / TMDB ids, episode metadata │
│ headless WebView ─────── runs extension modules, fetch() via Dart  │
│ media_kit (mpv) ──────── plays http://127.0.0.1:<port>/stream/...  │
└─────────────────────────────────┬──────────────────────────────────┘
                                  │ dart:ffi + local HTTP
┌─────────────────────────────────▼──────────────────────────────────┐
│ Go engine ── anacrolix/torrent                                     │
│ libnami.a (iOS) · libnami_engine.so (Android) · nami_engine.dll    │
│ POST /add   GET /stream/{hash}/{file} (HTTP ranges)                │
│ GET /stats/{hash}   POST /drop/{hash}                              │
└────────────────────────────────────────────────────────────────────┘
```

| Path | What it is |
|---|---|
| [`mobile/`](mobile) | The Flutter app (`lib/`), with its Android, iOS and Windows projects |
| [`engine/`](engine) | Go torrent engine, with an end-to-end test that streams Sintel (CC-BY) |
| [`app/`](app) | The first SwiftUI version for iOS, kept for reference |
| [`tools/`](tools) | Build, device and maintenance scripts |

## Building

**Requirements**: Flutter 3.47, Go 1.27+, and a C compiler for the engine's export glue
(MSYS2 UCRT64 gcc on Windows, the Android NDK for Android, Xcode for iOS).

**Android and Windows** (from Git Bash on Windows):

```bash
engine/build-shared.sh all        # nami_engine.dll and libnami_engine.so
cd mobile
flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64
flutter build windows --release
```

Release APKs are signed with the key named in `mobile/android/key.properties`
(not in the repository); without it they use the debug key.

**iOS** needs a Mac. The [Release workflow](.github/workflows/release.yml) builds the engine as a
static archive in `mobile/ios/engine/libnami.a`, then runs
`flutter build ios --release --no-codesign` and packages an unsigned IPA.
It runs on every `v*` tag and can be started by hand from the Actions tab.

**Test the engine**

```bash
cd engine && go test -tags nosqlite ./...
```

## Writing extensions

Nami runs the same extension format as Hayase. A repository is a JSON array of manifests:

```json
[{
  "manifestVersion": 2,
  "id": "example",
  "name": "Example",
  "version": "1.0.0",
  "type": "torrent",
  "code": "https://example.com/example.js",
  "options": { "useTorrent": { "type": "boolean", "default": false, "description": "…" } }
}]
```

`code` is an ES module whose default export implements `single(query, options)`,
`batch(query, options)` and `movie(query, options)`, each returning
`[{ title, link, hash, size, seeders, leechers, downloads, date, type, accuracy }]`.
`link` can be a magnet, an info hash or a `.torrent` URL. `query` contains `anilistId`,
`anidbAid`, `anidbEid`, `tvdbId`, `tvdbEId`, `tmdbId`, `imdbId`, `titles`, `episode`,
`episodeCount`, `resolution`, `exclusions`, `media` and `fetch`.
`fetch` is not limited by CORS.

## Disclaimer

Nami is a media player and BitTorrent client. It does not host, index or link to any
content and ships with no sources. You are responsible for the extensions you add and for
complying with the laws of your country.

## License

Nami is free software under the [GNU General Public License v3.0](LICENSE).

Third-party components keep their own licenses, listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): notably
[anacrolix/torrent](https://github.com/anacrolix/torrent) (MPL-2.0) and
[mpv](https://mpv.io) with FFmpeg through [media_kit](https://github.com/media-kit/media-kit)
(LGPL-2.1, dynamically linked).
Anime data comes from [AniList](https://anilist.co) and [ani.zip](https://api.ani.zip).
Nami is not affiliated with AniList, Hayase, mpv or VideoLAN.
