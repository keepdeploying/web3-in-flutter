#!/usr/bin/env bash
#
# Builds the Android app (APK) and publishes it as a GitHub Release, so
# anyone can download it and install it on their phone.
#
# Nothing runs this automatically. Run it by hand, from anywhere in the
# repository:
#
#   scripts/release-apk.sh
#
# It needs the GitHub CLI (https://cli.github.com), signed in with
# `gh auth login`. The release is tagged with the version in
# flutter/pubspec.yaml (`version: 0.1.0+1` becomes `v0.1.0`), so bump that
# version before each new release.

set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The platform folders aren't committed. Generate or update them every time:
# the script skips what is already done, and a half-finished earlier run
# (or a newer version of the script) would otherwise go unnoticed.
echo "Setting up the platform folders..."
dart run tool/setup_platforms.dart

cd flutter

# The version before the "+", like 0.1.0.
VERSION="$(sed -nE 's/^version: *([^+ ]+).*/\1/p' pubspec.yaml)"
TAG="v$VERSION"
APK="web3-in-flutter-$TAG.apk"

if git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists. Bump the version in flutter/pubspec.yaml first."
  exit 1
fi

echo "1/2 Building the APK..."
# One APK that runs on every Android phone. It is signed with the shared
# debug keystore in keys/ (tool/setup_platforms.dart wires it in), so a new
# release installs over an earlier one, whoever built it.
$FLUTTER build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "build/$APK"

echo "2/2 Creating the $TAG release on GitHub..."
gh release create "$TAG" "build/$APK" \
  --title "Flutter Counter $TAG" \
  --notes "Flutter Counter, the Web3 in Flutter example app, as an Android app. It reads, signs in and writes on EVM, Solana, Sui, Cosmos and NEAR testnets.

Download \`$APK\` on your Android phone and open it to install. Your phone may ask you to allow installing apps from your browser or files app first. Testnets only."

URL="$(gh release view "$TAG" --json url --jq .url)"
echo "Done. The release is at: $URL"
echo
echo "Add this row to DEPLOYS.md:"
echo "| $(date +%Y-%m-%d) | Android APK | GitHub Releases | $URL | \`$TAG\` |"
