#!/bin/bash
# Waits until xtool can talk to the iPhone (up to ~3 minutes).
for i in $(seq 1 36); do
  out=$(timeout 10 xtool devices 2>&1)
  if echo "$out" | grep -q "00008140"; then echo "$out"; exit 0; fi
  sleep 5
done
echo "$out"
exit 1
