#!/bin/bash
# Symbolicates image offsets from a crash report against the built Nami binary.
# Usage: symbolicate.sh 0x103a4c 0x103768 ...
source "$(dirname "$0")/../env.sh"
bin="$(dirname "$0")/../app/xtool/Nami.app/Nami"
sym=$(command -v llvm-symbolizer || ls ~/.local/share/swiftly/toolchains/*/usr/bin/llvm-symbolizer 2>/dev/null | head -1)
[ -n "$sym" ] || { echo "no llvm-symbolizer"; exit 1; }
for off in "$@"; do
  addr=$(printf "0x%x" $((0x100000000 + off)))
  name=$("$sym" --obj="$bin" --functions=linkage "$addr" | head -1)
  echo "$off $(echo "$name" | swift demangle --simplified)"
done
