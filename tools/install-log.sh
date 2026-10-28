#!/bin/bash
# Waits (up to $1 seconds) for the install in /tmp/nami-install.log to finish
# and prints its last meaningful lines.
limit=${1:-90}
for ((t = 0; t < limit; t += 5)); do
  grep -q "^exit" /tmp/nami-install.log && break
  sleep 5
done
tr '\r' '\n' < /tmp/nami-install.log | grep -vE '^\[[0-9]+ / [0-9]+\]|^$' | tail -6 | cut -c1-600
