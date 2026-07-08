#!/usr/bin/env bash
# Creates a self-signed "WisprOwn Dev" code-signing certificate in the login
# keychain. Signing with a stable identity means macOS keeps the app's
# Accessibility/Microphone grants across rebuilds (ad-hoc signing resets
# them every build). One-time setup; macOS may show 1-2 confirmation dialogs.
set -euo pipefail

NAME="WisprOwn Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "'$NAME' identity already exists — nothing to do."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/ext.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = WisprOwn Dev
[v3]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/ext.cnf" 2>/dev/null

openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -out "$tmp/identity.p12" -passout pass:wisprown

security import "$tmp/identity.p12" -k "$KEYCHAIN" -P wisprown \
  -T /usr/bin/codesign -T /usr/bin/security

# Trust the cert for code signing (user trust domain; may prompt once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

echo "Created and trusted '$NAME'. Verifying:"
security find-identity -v -p codesigning | grep "$NAME" || {
  echo "WARNING: identity not yet valid — you may need to approve a dialog."
  exit 1
}
