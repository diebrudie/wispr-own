#!/usr/bin/env bash
# Creates a self-signed "WisprOwn Dev" code-signing certificate in the login
# keychain. Signing with a stable identity means macOS keeps the app's
# Accessibility/Microphone grants across rebuilds (ad-hoc signing resets
# them every build). Run this ONCE, before your first `make app`.
#
# macOS will ask for your login password when trusting the certificate.
# The key never leaves your machine and only signs your own local builds.
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

# Import key + cert separately: PKCS12 bundles from modern OpenSSL use
# algorithms macOS `security import` cannot read (MAC verification failure).
# -A: any app may use the key without a password prompt. Acceptable here —
# this key only signs your own local builds and never leaves the machine.
security import "$tmp/key.pem" -k "$KEYCHAIN" -A
security import "$tmp/cert.pem" -k "$KEYCHAIN" -A

# Trust the cert for code signing (user trust domain; may prompt once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

echo "Created and trusted '$NAME'. Verifying:"
security find-identity -v -p codesigning | grep "$NAME" || {
  echo "WARNING: identity not yet valid — you may need to approve a dialog."
  exit 1
}

cat <<'DONE'

Done. `make app` now signs with this identity automatically.
Grant Microphone + Accessibility once on the next launch; from then on
rebuilds keep their permissions.
DONE
