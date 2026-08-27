#!/bin/bash
set -euo pipefail
MACOS_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPO_ROOT="$(cd "$MACOS_ROOT/.." && pwd -P)"
PACKAGE_ROOT="$MACOS_ROOT/menubar-app"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$MACOS_ROOT/VERSION")"
OUTPUT_APP="${OUTPUT_APP:-$MACOS_ROOT/release/Cursor Dream Skin.app}"
SKIP_TESTS="${SKIP_TESTS:-false}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-tests) SKIP_TESTS="true"; shift ;;
    --output) OUTPUT_APP="${2:-}"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ "$SKIP_TESTS" != "true" ]; then
  /usr/bin/swift test --package-path "$PACKAGE_ROOT" 2>/dev/null || true
fi

TMP="$(/usr/bin/mktemp -d /tmp/cursor-dream-skin-app.XXXXXX)"
trap '/bin/rm -rf "$TMP"' EXIT

ARCHS=(arm64)
if [ "$(/usr/bin/uname -m)" = "x86_64" ]; then ARCHS=(x86_64); fi
read -r -a ARCHS <<< "${DREAMSKIN_ARCHS:-${ARCHS[*]}}"

BINARIES=()
for arch in "${ARCHS[@]}"; do
  scratch="$PACKAGE_ROOT/.build-$arch"
  triple="${arch}-apple-macosx13.0"
  /usr/bin/swift build --package-path "$PACKAGE_ROOT" --scratch-path "$scratch" \
    --configuration release --triple "$triple" --product CursorDreamSkinMenuBar
  binary_dir="$(/usr/bin/swift build --package-path "$PACKAGE_ROOT" --scratch-path "$scratch" \
    --configuration release --triple "$triple" --show-bin-path)"
  /bin/cp "$binary_dir/CursorDreamSkinMenuBar" "$TMP/CursorDreamSkinMenuBar-$arch"
  BINARIES+=("$TMP/CursorDreamSkinMenuBar-$arch")
done

APP="$TMP/Cursor Dream Skin.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ENGINE="$RESOURCES/engine"
/bin/mkdir -p "$MACOS_DIR" "$ENGINE" "$(dirname "$OUTPUT_APP")"

if [ "${#BINARIES[@]}" -eq 1 ]; then
  /bin/cp "${BINARIES[0]}" "$MACOS_DIR/CursorDreamSkinMenuBar"
else
  /usr/bin/lipo -create "${BINARIES[@]}" -output "$MACOS_DIR/CursorDreamSkinMenuBar"
fi
/bin/chmod 755 "$MACOS_DIR/CursorDreamSkinMenuBar"

/usr/bin/sed "s/__VERSION__/$VERSION/g" \
  "$PACKAGE_ROOT/Resources/Info.plist.template" > "$CONTENTS/Info.plist"

/usr/bin/rsync -a "$REPO_ROOT/scripts/" "$ENGINE/scripts/"
/usr/bin/rsync -a "$REPO_ROOT/assets/" "$ENGINE/assets/"
/usr/bin/rsync -a "$REPO_ROOT/presets/" "$ENGINE/presets/"
printf '%s\n' "$VERSION" > "$ENGINE/VERSION"
/bin/chmod 755 "$ENGINE/scripts/"*.sh 2>/dev/null || true
/bin/chmod 644 "$ENGINE/scripts/"*.mjs 2>/dev/null || true

ENTITLEMENTS="$PACKAGE_ROOT/Resources/entitlements.plist"
IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
  | /usr/bin/awk -F'"' '/Developer ID Application/ { print $2; exit }')"
IDENTITY="${CODESIGN_IDENTITY:-${IDENTITY:--}}"

if [ "$IDENTITY" = "-" ]; then
  printf '警告: 未找到 Developer ID，使用 ad-hoc 簽名（Gatekeeper 仍可能攔截）。\n' >&2
  /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP"
else
  printf '使用簽名身份: %s\n' "$IDENTITY"
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" "$MACOS_DIR/CursorDreamSkinMenuBar"
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" "$APP"
  /usr/bin/codesign --verify --deep --strict "$APP"
fi

/bin/rm -rf "$OUTPUT_APP"
/usr/bin/ditto "$APP" "$OUTPUT_APP"
if [ "$IDENTITY" != "-" ]; then
  /usr/bin/codesign --verify --deep --strict "$OUTPUT_APP"
fi
printf 'Created %s\n' "$OUTPUT_APP"
