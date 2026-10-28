<p align="center">
  <img src="app/Icon.png" width="128" height="128" alt="Nami icon">
</p>

<h1 align="center">Nami</h1>

<p align="center">
  Stream anime from torrents on iPhone, with AniList sync.<br>
  Everything runs on the phone: no server, no PC, works on Wi-Fi and cellular.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue"></a>
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-black">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-orange">
  <img alt="Go" src="https://img.shields.io/badge/engine-Go-00ADD8">
</p>

---

## Features

- **AniList**: log in, see what you are watching, browse the season and trending anime,
  search with genre filters. Episodes are marked as watched on AniList automatically.
- **Extensions**: sources come from extension repositories in the same format as
  [Hayase](https://hayase.watch) extensions. Nami ships with **no** sources; add the
  repositories you want in Settings.
- **Torrent engine on the device**: playback starts while the torrent downloads,
  with pieces fetched around the playback position. Nothing is kept after you close the player.
- **VLC player**: MKV, HEVC, ASS subtitles, audio and subtitle track selection,
  10 s seeking, an 85 s intro skip and a next-episode button.
- **French and English** interface, and a choice of romaji, English or Japanese titles.

See [docs/ROADMAP.md](docs/ROADMAP.md) for what is coming next.

## Install

Nami is not on the App Store. Build it yourself (below) or take the IPA from
[Releases](../../releases) and sideload it with the tool of your choice
(LiveContainer, SideStore, AltStore, xtool…).

With a free Apple account, sideloaded apps expire after 7 days and must be re-signed.

### First launch

1. **Settings → AniList**: log in.
2. **Settings → Extensions**: paste the URL of an extension repository (`…/index.json`)
   and enable the sources you want.
3. Open an anime, pick an episode, choose a source.

## How it works

```
┌──────────────────────── Nami (SwiftUI) ────────────────────────┐
│ AniList GraphQL ── browse, list, progress sync                 │
│ api.ani.zip ────── AniDB / TVDB / TMDB ids, episode metadata   │
│ WKWebView ──────── runs extension modules, fetch() via native  │
│ MobileVLCKit ───── plays http://127.0.0.1:<port>/stream/...    │
└───────────────────────────────┬────────────────────────────────┘
                                │ C call + local HTTP
┌───────────────────────────────▼────────────────────────────────┐
│ Go engine (libnami.a) ── anacrolix/torrent                     │
│ POST /add   GET /stream/{hash}/{file} (HTTP ranges)            │
│ GET /stats/{hash}   POST /drop/{hash}                          │
└────────────────────────────────────────────────────────────────┘
```

| Path | What it is |
|---|---|
| [`engine/`](engine) | Go torrent engine built as a C archive, with an end-to-end test that streams Sintel (CC-BY) |
| [`app/Sources/Nami/`](app/Sources/Nami) | SwiftUI app: `AniList.swift`, `Extensions.swift`, `Engine.swift`, `Player.swift`, views |
| [`app/Sources/NamiEngine/`](app/Sources/NamiEngine) | C header for the engine |
| [`tools/`](tools) | Build, device and maintenance scripts |

## Building

Nami is built on Linux (or WSL) with [xtool](https://github.com/xtool-org/xtool),
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

**Test the engine**

```bash
cd engine && go test -tags nosqlite ./...
```

On WSL, the iPhone can be reached through the Windows Apple Mobile Device Service by setting
`USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015` (run scripts with `bash -li` so it is loaded).

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
[MobileVLCKit](https://code.videolan.org/videolan/VLCKit) (LGPL-2.1, dynamically linked).
Anime data comes from [AniList](https://anilist.co) and [ani.zip](https://api.ani.zip).
Nami is not affiliated with AniList, Hayase or VideoLAN.
