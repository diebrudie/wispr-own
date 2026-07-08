#!/usr/bin/env bash
# Downloads the prebuilt whisper.cpp XCFramework into Vendor/.
# Pinned to an exact release; the zip's SHA-256 is verified before unpacking.
set -euo pipefail

VERSION="v1.9.1"
SHA256="8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"
URL="https://github.com/ggml-org/whisper.cpp/releases/download/${VERSION}/whisper-${VERSION}-xcframework.zip"

cd "$(dirname "$0")/.."

if [ -d Vendor/whisper.xcframework ]; then
  echo "Vendor/whisper.xcframework already present — skipping download."
  exit 0
fi

echo "Downloading whisper.cpp ${VERSION} XCFramework (~48 MB)..."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar -o "$tmp/whisper.zip" "$URL"

echo "${SHA256}  ${tmp}/whisper.zip" | shasum -a 256 -c -

unzip -q "$tmp/whisper.zip" -d "$tmp"
mkdir -p Vendor
mv "$tmp/build-apple/whisper.xcframework" Vendor/
echo "Installed Vendor/whisper.xcframework"
