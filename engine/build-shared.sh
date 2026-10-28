#!/bin/bash
# Builds the engine as shared libraries for the Flutter app (run from Git Bash on Windows).
#   windows: mobile/windows/engine/nami_engine.dll
#   android: mobile/android/app/src/main/jniLibs/<abi>/libnami_engine.so
# Usage: engine/build-shared.sh [windows|android|all]
# Needs Go for Windows (GO), MSYS2 UCRT64 gcc (WINCC) and the Android NDK (NDK).
set -euo pipefail
cd "$(dirname "$0")"
root="$(cd .. && pwd)"

GO="${GO:-/c/Dev/go/bin/go.exe}"
WINCC="${WINCC:-/c/msys64/ucrt64/bin/gcc.exe}"
NDK="${NDK:-$(ls -d "$LOCALAPPDATA"/Android/Sdk/ndk/* 2>/dev/null | sort -V | tail -1)}"
NDK_BIN="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin"
API=24
# Pure-Go uTP (no C++ libutp) and no SQLite: only the C export glue needs a C compiler.
TAGS="nosqlite disable_libutp"

build_windows() {
  mkdir -p "$root/mobile/windows/engine"
  PATH="$(dirname "$WINCC"):$PATH" CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC="$WINCC" \
    "$GO" build -tags "$TAGS" -trimpath -ldflags="-s -w" -buildmode=c-shared \
    -o "$root/mobile/windows/engine/nami_engine.dll" .
  rm -f "$root/mobile/windows/engine/nami_engine.h"
  echo "windows: mobile/windows/engine/nami_engine.dll"
}

build_android_abi() {
  local abi=$1 goarch=$2 triple=$3
  local out="$root/mobile/android/app/src/main/jniLibs/$abi"
  mkdir -p "$out"
  CGO_ENABLED=1 GOOS=android GOARCH="$goarch" CC="$NDK_BIN/${triple}${API}-clang.cmd" \
    "$GO" build -tags "$TAGS" -trimpath -buildmode=c-shared \
    -ldflags="-s -w -checklinkname=0 -extldflags=-Wl,-soname,libnami_engine.so,-z,max-page-size=16384" \
    -o "$out/libnami_engine.so" .
  rm -f "$out/libnami_engine.h"
  echo "android: $abi"
}
# -checklinkname=0: github.com/wlynxg/anet (Android interface listing, pulled in by the
# engine's networking deps) links to net.zoneCache, which Go rejects by default.

case "${1:-all}" in
  windows) build_windows ;;
  android) build_android_abi arm64-v8a arm64 aarch64-linux-android; build_android_abi x86_64 amd64 x86_64-linux-android ;;
  all) build_windows; build_android_abi arm64-v8a arm64 aarch64-linux-android; build_android_abi x86_64 amd64 x86_64-linux-android ;;
  *) echo "usage: $0 [windows|android|all]" >&2; exit 2 ;;
esac
