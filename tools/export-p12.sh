#!/bin/bash
# Exports the xtool development certificate + key as a password-protected
# .p12 for LiveContainer. Prints only the output path and the password.
set -euo pipefail
umask 077
out=~/nami-secrets
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# xtool keeps the signing identity in a file named after the 10-character team ID.
team_file=$(ls ~/.config/xtool/data | grep -E '^[A-Z0-9]{10}$' | head -1)
python3 -I - "$work" "$HOME/.config/xtool/data/$team_file" <<'EOF'
import plistlib, sys
work = sys.argv[1]
d = plistlib.load(open(sys.argv[2], "rb"))
open(f"{work}/cert.der", "wb").write(d["certificate"])
open(f"{work}/key.bin", "wb").write(d["privateKey"]["data"])
EOF

if grep -q "BEGIN" "$work/key.bin"; then inform=PEM; else inform=DER; fi
openssl pkey -inform "$inform" -in "$work/key.bin" -out "$work/key.pem"
openssl x509 -inform DER -in "$work/cert.der" -out "$work/cert.pem"
pass=$(openssl rand -hex 4)
# Legacy algorithms: iOS rejects the OpenSSL 3 default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" \
  -name "Apple Development" -out "$out/xtool-dev.p12" -passout "pass:$pass"
echo "p12: $out/xtool-dev.p12"
echo "password: $pass"
