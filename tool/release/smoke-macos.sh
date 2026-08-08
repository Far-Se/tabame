#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: smoke-macos.sh --dmg PATH [options]

Options:
  --dmg PATH          Tabame DMG artifact.
  --arch ARCH         Require this architecture in the app executable.
  --launch            Start the app for the liveness interval.
  --duration SEC      Liveness interval (default: 6).
  --require-signed    Require a valid code signature.
EOF
}

dmg_path=""
expected_arch=""
launch=0
duration=6
require_signed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      dmg_path="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      expected_arch="$2"
      shift 2
      ;;
    --launch)
      launch=1
      shift
      ;;
    --duration)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      duration="$2"
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

[[ -n "$dmg_path" ]] || { usage; exit 2; }
[[ -f "$dmg_path" ]] || { echo "DMG does not exist: $dmg_path" >&2; exit 1; }
if [[ ! "$duration" =~ ^[1-9][0-9]*$ ]]; then
  echo "--duration must be a positive integer." >&2
  exit 2
fi

command -v hdiutil >/dev/null || { echo "hdiutil is required." >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign is required." >&2; exit 1; }
command -v plutil >/dev/null || { echo "plutil is required." >&2; exit 1; }

mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/tabame-macos-smoke.XXXXXX")"
log_path="$mount_dir/tabame.log"
pid=""
mounted=0
cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if (( mounted )); then
    hdiutil detach "$mount_dir" -quiet || true
  fi
  rm -rf "$mount_dir"
}
trap cleanup EXIT

hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg_path" >/dev/null
mounted=1
app_path="$mount_dir/tabame.app"
[[ -d "$app_path" ]] || { echo "DMG does not contain tabame.app." >&2; exit 1; }
[[ -x "$app_path/Contents/MacOS/tabame" ]] || { echo "App executable is missing." >&2; exit 1; }
plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" | grep -Fxq 'com.farse.tabame'
plutil -extract LSMinimumSystemVersion raw "$app_path/Contents/Info.plist" | grep -Fxq '13.0'

if command -v lipo >/dev/null && [[ -n "$expected_arch" ]]; then
  actual_arches="$(lipo -archs "$app_path/Contents/MacOS/tabame")"
  [[ "$actual_arches" == *"$expected_arch"* ]] || {
    echo "DMG executable architectures ($actual_arches) do not include $expected_arch." >&2
    exit 1
  }
fi

if codesign --verify --deep --strict "$app_path" 2>/dev/null; then
  echo "macOS code signature verified."
  if (( require_signed )); then
    command -v spctl >/dev/null || { echo "spctl is required for signed release smoke." >&2; exit 1; }
    spctl --assess --type execute --verbose=2 "$app_path"
  fi
elif (( require_signed )); then
  echo "A valid macOS code signature is required." >&2
  exit 1
else
  echo "Unsigned macOS smoke artifact; signature check skipped."
fi

if (( launch )); then
  (
    cd "$app_path/Contents/Resources"
    "$app_path/Contents/MacOS/tabame" -launcher phase9-release-smoke
  ) >"$log_path" 2>&1 &
  pid=$!
  for _ in $(seq 1 "$duration"); do
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$log_path" >&2
      echo "Tabame exited before the macOS smoke interval completed." >&2
      exit 1
    fi
    sleep 1
  done
fi

echo "macOS DMG smoke passed."
