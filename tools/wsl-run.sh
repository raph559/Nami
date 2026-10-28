#!/bin/bash
# Builds the torrent engine and the iOS app in WSL.
#   tools/wsl-run.sh          build engine + app, install and launch on the USB iPhone
#   tools/wsl-run.sh build    build only (app/xtool/Nami.app)
#   tools/wsl-run.sh ipa      build app/xtool/Nami.ipa (for LiveContainer)
# Run with `bash -li` so USBMUXD_SOCKET_ADDRESS from ~/.bashrc is set.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/env.sh"

"$root/engine/build-ios.sh" >/dev/null
cd "$root/app"
case "${1:-run}" in
  build) xtool dev build -c release ;;
  ipa) xtool dev build -c release --ipa ;;
  run) xtool dev run -c release ;;
  *) echo "usage: $0 [run|build|ipa]" >&2; exit 2 ;;
esac
