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
  <img alt="Go" src="https://img.shields.io/badge/engine-Go-00ADD8">
</p>

---

Nami is two apps around one torrent engine:

- **iPhone**: a native SwiftUI app with a VLC player, in [`app/`](app).
- **Android and Windows**: a Flutter app with an mpv player, in [`mobile/`](mobile).

Both talk to AniList and run the same Hayase-format extensions.

## Features

- **AniList**: log in, see what you are watching, browse the season and trending anime,
  search with genre filters. Episodes are marked as watched on AniList after 85 % of an episode.
- **Extensions**: sources come from extension repositories in the same format as
  [Hayase](https://hayase.watch) extensions. Nami ships with **no** sources; add the
  repositories you want in Settings.
- **Torrent engine on the device**: playback starts while the torrent downloads,
  with pieces fetched around the playback position. Nothing is kept after you close the player.
- **Player**: MKV, HEVC, ASS subtitles, audio and subtitle track selection,
  10 s seeking, an 85 s intro skip and a next-episode button.
- **French and English** interface, and a choice of romaji, English or Japanese titles.

Android and Windows only, for now:

- **Source picker**: release names are read (group, quality, codec, audio, full season) and
  one source is recommended, based on seeders, your preferred quality and original audio.
- **Player comfort**: resumes each episode where you stopped, skips openings and endings
  with [AniSkip](https://aniskip.com) timings, plays the next episode after a 10 s countdown
  (reusing the season pack when it holds it), picks subtitles in your language, with
  adjustable size and delay.
- **Keyboard shortcuts** in the player on Windows: Space/K play, ←/→ 10 s, S skip,
  Z/X subtitle delay, Esc close.

See [docs/ROADMAP.md](docs/ROADMAP.md) for what is coming next.

## Install

Take the file for your device from [Releases](../../releases). The iPhone app has its own
version number: the latest IPA is attached to the most recent release that has one.

| Device | File | Notes |
|---|---|---|
| iPhone | `Nami-<version>.ipa` | Unsigned, iOS 17 or later. Sideload it with LiveContainer, SideStore, AltStore or xtool. With a free Apple account, sideloaded apps must be re-signed every 7 days. |
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
┌──── iPhone app (SwiftUI) ────┐   ┌──── Android / Windows (Flutter) ────┐
│ AniList GraphQL, ani.zip     │   │ AniList GraphQL, ani.zip            │
│ WKWebView runs extensions    │   │ headless WebView runs extensions    │
│ MobileVLCKit plays the file  │   │ media_kit (mpv) plays the file      │
└──────────────┬───────────────┘   └──────────────────┬──────────────────┘
               │ C call + local HTTP                  │ dart:ffi + local HTTP
┌──────────────▼──────────────────────────────────────▼──────────────────┐
│ Go engine ── anacrolix/torrent                                         │
│ libnami.a (iOS) · libnami_engine.so (Android) · nami_engine.dll        │
│ POST /add   GET /stream/{hash}/{file} (HTTP ranges)                    │
│ GET /stats/{hash}   POST /drop/{hash}                                  │
└────────────────────────────────────────────────────────────────────────┘
```

| Path | What it is |
|---|---|
| [`app/`](app) | iPhone app (SwiftUI): `Sources/Nami/` for the app, `Sources/NamiEngine/` for the engine header |
| [`mobile/`](mobile) | Android and Windows app (Flutter): `lib/` for the app |
| [`engine/`](engine) | Go torrent engine, with an end-to-end test that streams Sintel (CC-BY) |
| [`tools/`](tools) | Build, device and maintenance scripts |

## Building

### iPhone app

The iOS app is built on Linux (or WSL) with [xtool](https://github.com/xtool-org/xtool),
which replaces Xcode for SwiftPM apps. A Mac with Xcode works too
(`xtool dev generate-xcode-project`).

**Requirements**
- xtool with the Darwin SDK (`xtool setup`), Swift 6
- Go 1.27+ (`env.sh` expects it in `~/.local/go-sdk`; adjust if needed)
- MobileVLCKit 3.7.4, which is not in the repository:

```bash
mkdir -p vendor && cd vendor
curl -LO https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.0-20260922-1512.tar.xz
echo "c649c4c47bd065b3a5511746361b5a9066a34033f2df9cbc9454409c0f363b52  MobileVLCKit-3.0-20260922-1512.tar.xz" | sha256sum -c
tar xf MobileVLCKit-3.0-20260922-1512.tar.xz
cp -r MobileVLCKit-binary/MobileVLCKit.xcframework ../app/Vendor/
cd .. && python3 tools/thin.py app/Vendor/MobileVLCKit.xcframework/ios-arm64_armv7_armv7s/MobileVLCKit.framework/MobileVLCKit
```

**Build**

```bash
tools/wsl-run.sh          # build engine + app, install and launch on a USB-connected iPhone
tools/wsl-run.sh build    # app/xtool/Nami.app
tools/wsl-run.sh ipa      # app/xtool/Nami.ipa
```

On WSL, the iPhone can be reached through the Windows Apple Mobile Device Service by setting
`USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015` (run scripts with `bash -li` so it is loaded).

### Android and Windows app

**Requirements**: Flutter 3.47, Go 1.27+, MSYS2 UCRT64 gcc (Windows engine) and the Android NDK.
From Git Bash on Windows:

```bash
engine/build-shared.sh all        # nami_engine.dll and libnami_engine.so
cd mobile
flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64
flutter build windows --release
```

Release APKs are signed with the key named in `mobile/android/key.properties`
(not in the repository); without it they use the debug key.

### Test the engine

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
[anacrolix/torrent](https://github.com/anacrolix/torrent) (MPL-2.0),
[MobileVLCKit](https://code.videolan.org/videolan/VLCKit) on iPhone and
[mpv](https://mpv.io) with FFmpeg through [media_kit](https://github.com/media-kit/media-kit)
on Android and Windows (both LGPL-2.1, dynamically linked).
Anime data comes from [AniList](https://anilist.co) and [ani.zip](https://api.ani.zip).
Nami is not affiliated with AniList, Hayase, mpv or VideoLAN.
