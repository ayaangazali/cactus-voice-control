#!/usr/bin/env bash
# Fetch cactus-ios.xcframework and Cactus.swift from the cactus-compute/cactus
# GitHub release. Pinned via PIN below; override with `--pin vX.Y.Z`.

set -euo pipefail

PIN="${PIN:-latest}"
REPO="cactus-compute/cactus"
DEST_FW="$(cd "$(dirname "$0")/.." && pwd)/CactusVoice/Cactus/cactus-ios.xcframework"
DEST_SWIFT="$(cd "$(dirname "$0")/.." && pwd)/CactusVoice/Cactus/Cactus.swift"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pin) PIN="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "need 'gh' CLI (brew install gh)" >&2
  exit 1
fi

if [[ "$PIN" == "latest" ]]; then
  TAG="$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName')"
else
  TAG="$PIN"
fi

if [[ -z "$TAG" ]]; then
  echo "could not resolve cactus release tag" >&2
  exit 1
fi

echo "→ fetching cactus $TAG"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

gh release download "$TAG" --repo "$REPO" --pattern 'cactus-ios.xcframework.zip' --dir "$WORK"
unzip -q "$WORK/cactus-ios.xcframework.zip" -d "$WORK"

mkdir -p "$(dirname "$DEST_FW")"
if [[ -d "$DEST_FW" ]]; then
  rm -rf "$DEST_FW"
fi
mv "$WORK/cactus-ios.xcframework" "$DEST_FW"

curl -fsSL "https://raw.githubusercontent.com/$REPO/$TAG/apple/Cactus.swift" -o "$DEST_SWIFT"

echo "✓ vendored to $DEST_FW"
echo "✓ vendored to $DEST_SWIFT"
echo "next: xcodegen generate"
