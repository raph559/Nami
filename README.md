# Nami

iOS app for watching anime from torrents, Hayase-style: AniList list and sync,
Hayase-format source extensions, an embedded torrent engine and a VLC player.
Everything runs on the phone (Wi-Fi or 4G), no PC needed once installed.

## Layout

- `engine/` — Go torrent engine ([anacrolix/torrent](https://github.com/anacrolix/torrent)),
  built as a C archive (`libnami.a`). It serves a small HTTP API on 127.0.0.1:
  `POST /add`, `GET /stream/{hash}/{file}` (range requests), `GET /stats/{hash}`, `POST /drop/{hash}`.
- `app/` — SwiftUI app, an [xtool](https://github.com/xtool-org/xtool) SwiftPM project.
  - `AniList.swift` — GraphQL client, login (client ID 55284, redirect `nami://auth`), list updates.
  - `Extensions.swift` — extension repositories and a hidden WKWebView that runs them,
    with `fetch` routed through URLSession (no CORS).
  - `Mappings.swift` — AniDB/TVDB/TMDB ids and episode metadata from api.ani.zip.
  - `Engine.swift`, `Player.swift` — engine client and MobileVLCKit player.
- `app/Vendor/MobileVLCKit.xcframework` — VLCKit 3.7.4 (LGPL), device slice thinned to arm64
  with `tools/thin.py`. Not in git: download it from the CocoaPods spec URL and thin it.
- `tools/` — build and device helpers.

## Build (WSL Ubuntu-24.04)

Needs xtool with the Darwin SDK, Go (`~/.local/go-sdk`, see `env.sh`), and the iPhone
reachable through the Windows Apple Mobile Device Service (`USBMUXD_SOCKET_ADDRESS` in `~/.bashrc`).

```bash
bash -li tools/wsl-run.sh          # build engine + app, install on the USB iPhone
bash -li tools/wsl-run.sh ipa      # app/xtool/Nami.ipa, to install inside LiveContainer
cd engine && go test ./...         # streams Sintel (CC) through the engine on Linux
```

## License

GPL-3.0, see [LICENSE](LICENSE). Third-party components keep their own licenses:
anacrolix/torrent (MPL-2.0), MobileVLCKit (LGPL-2.1, linked dynamically, not in the repository).

## Notes

- Free Apple account: 3 sideloaded apps, 7-day profiles. Nami runs inside LiveContainer.
- Do not use Swift task groups (`withTaskGroup`): with this toolchain they abort in the
  iOS 27.2 concurrency runtime (`__cxa_pure_virtual` in `AsyncTask::completeFuture`).
- Crash reports: `idevicecrashreport -k <dir>`, then `tools/symbolicate.sh <offsets>`.
