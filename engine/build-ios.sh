#!/bin/bash
# Builds the engine as a static C archive for iOS arm64 (libnami.a + header).
set -euo pipefail
cd "$(dirname "$0")"
source ../env.sh

CLANG="clang -target arm64-apple-ios$IOS_MIN -isysroot $IOS_SDK"
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1
export CC="$CLANG" CXX="${CLANG/clang/clang++}"
export CGO_CFLAGS="-fembed-bitcode=off -O2"
export CGO_LDFLAGS="-target arm64-apple-ios$IOS_MIN -isysroot $IOS_SDK"

go mod tidy >/dev/null
mkdir -p out
go build -tags nosqlite -trimpath -ldflags="-s -w" -buildmode=c-archive -o out/libnami.a .
ls -la out
