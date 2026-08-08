#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: package-macos-dmg.sh --app PATH --version VERSION --arch ARCH [options]

Options:
  --app PATH                    Flutter-built .app bundle.
  --version VERSION             Release version.
  --arch ARCH                   Artifact architecture label (arm64 or x86_64).
  --output-dir PATH             Destination directory (default: dist).
  --signing-identity ID         Developer ID Application identity. Optional for CI smoke artifacts.
  --entitlements PATH           Release entitlements (default: macos/Runner/Release.entitlements).
  --notarize                    Submit the DMG to Apple's notary service and staple the ticket.
  --notary-key PATH              App Store Connect API private key (.p8).
  --notary-key-id ID             App Store Connect API key ID.
  --notary-issuer ID             App Store Connect issuer ID.
  --require-signed               Fail when --signing-identity is omitted.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path=""
app_version=""
artifact_arch=""
output_dir="$repo_root/dist"
signing_identity="${TABAME_MACOS_SIGNING_IDENTITY:-}"
entitlements="$repo_root/macos/Runner/Release.entitlements"
notarize=0
notary_key="${TABAME_NOTARY_KEY_PATH:-}"
notary_key_id="${TABAME_NOTARY_KEY_ID:-}"
notary_issuer="${TABAME_NOTARY_ISSUER_ID:-}"
require_signed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      app_path="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      app_version="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      artifact_arch="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    --signing-identity)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      signing_identity="$2"
      shift 2
      ;;
    --entitlements)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      entitlements="$2"
      shift 2
      ;;
    --notarize)
      notarize=1
      shift
      ;;
    --notary-key)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      notary_key="$2"
      shift 2
      ;;
    --notary-key-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      notary_key_id="$2"
      shift 2
      ;;
    --notary-issuer)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      notary_issuer="$2"
      shift 2
      ;;
    --require-signed)
      require_signed=1
      shift
      ;;
    -h|--help)
      usage >&1
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$app_path" || -z "$app_version" || -z "$artifact_arch" ]]; then
  usage
  exit 2
fi
if [[ ! -d "$app_path" || "${app_path##*.}" != "app" ]]; then
  echo "--app must point to a .app bundle: $app_path" >&2
  exit 1
fi
if [[ ! -x "$app_path/Contents/MacOS/tabame" ]]; then
  echo "The app bundle does not contain Contents/MacOS/tabame: $app_path" >&2
  exit 1
fi
if [[ ! -f "$entitlements" ]]; then
  echo "Release entitlements are missing: $entitlements" >&2
  exit 1
fi
if (( require_signed )) && [[ -z "$signing_identity" ]]; then
  echo "A signing identity is required for this packaging mode." >&2
  exit 2
fi
if (( notarize )); then
  command -v xcrun >/dev/null || { echo "xcrun is required for notarization." >&2; exit 1; }
  [[ -n "$notary_key" && -f "$notary_key" ]] || { echo "--notary-key must point to an App Store Connect .p8 key." >&2; exit 2; }
  [[ -n "$notary_key_id" && -n "$notary_issuer" ]] || { echo "--notary-key-id and --notary-issuer are required with --notarize." >&2; exit 2; }
  [[ -n "$signing_identity" ]] || { echo "Notarization requires --signing-identity." >&2; exit 2; }
fi

command -v ditto >/dev/null || { echo "ditto is required." >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "hdiutil is required." >&2; exit 1; }
command -v shasum >/dev/null || { echo "shasum is required." >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign is required." >&2; exit 1; }

if command -v lipo >/dev/null; then
  actual_arches="$(lipo -archs "$app_path/Contents/MacOS/tabame")"
  if [[ "$actual_arches" != *"$artifact_arch"* ]]; then
    echo "App executable architectures ($actual_arches) do not include $artifact_arch." >&2
    exit 1
  fi
fi

if [[ -n "$signing_identity" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$entitlements" --sign "$signing_identity" "$app_path"
else
  echo "Packaging an unsigned macOS smoke artifact; use --require-signed for release output." >&2
fi

codesign --verify --deep --strict "$app_path" 2>/dev/null || {
  if [[ -n "$signing_identity" ]]; then
    echo "The signed macOS app failed codesign verification." >&2
    exit 1
  fi
  echo "The app is not signed; this is allowed only for a smoke artifact." >&2
}

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
base_name="tabame-${app_version}-macos-${artifact_arch}"
zip_path="$output_dir/$base_name.zip"
dmg_path="$output_dir/$base_name.dmg"
checksum_path="$output_dir/$base_name.sha256"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/tabame-macos.XXXXXX")"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$staging_dir/zip" "$staging_dir/dmg"
rm -f "$dmg_path" "$zip_path" "$checksum_path"
ditto --norsrc -c -k --sequesterRsrc --keepParent "$app_path" "$staging_dir/zip/$base_name.zip"
ditto "$app_path" "$staging_dir/dmg/tabame.app"
hdiutil create -quiet -volname "Tabame $app_version" -srcfolder "$staging_dir/dmg" \
  -format UDZO -imagekey zlib-level=9 "$dmg_path"
cp "$staging_dir/zip/$base_name.zip" "$zip_path"

if (( notarize )); then
  xcrun notarytool submit "$dmg_path" --key "$notary_key" --key-id "$notary_key_id" \
    --issuer "$notary_issuer" --wait
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
fi

{
  shasum -a 256 "$dmg_path" | awk '{print $1 "  " $2}'
  shasum -a 256 "$zip_path" | awk '{print $1 "  " $2}'
} | sed "s#${output_dir}/##" > "$checksum_path"

echo "Created $dmg_path"
echo "Created $zip_path"
echo "Created $checksum_path"
