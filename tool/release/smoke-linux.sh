#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: smoke-linux.sh (--package PATH | --bundle PATH) [options]

Options:
  --package PATH     Extract and smoke-test a Tabame .deb.
  --bundle PATH      Smoke-test an extracted Flutter bundle directly.
  --duration SEC     Liveness interval (default: 6).
  --no-launch        Validate package/bundle layout without starting GTK.
EOF
}

package_path=""
bundle_path=""
duration=6
no_launch=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      package_path="$2"
      shift 2
      ;;
    --bundle)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      bundle_path="$2"
      shift 2
      ;;
    --duration)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      duration="$2"
      shift 2
      ;;
    --no-launch)
      no_launch=1
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

if [[ -n "$package_path" && -n "$bundle_path" ]] || [[ -z "$package_path" && -z "$bundle_path" ]]; then
  usage
  exit 2
fi
if [[ ! "$duration" =~ ^[1-9][0-9]*$ ]]; then
  echo "--duration must be a positive integer." >&2
  exit 2
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tabame-linux-smoke.XXXXXX")"
log_path="$temp_dir/tabame.log"
pid=""
cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$temp_dir"
}
trap cleanup EXIT

if [[ -n "$package_path" ]]; then
  command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required." >&2; exit 1; }
  [[ -f "$package_path" ]] || { echo "Package does not exist: $package_path" >&2; exit 1; }
  dpkg-deb --info "$package_path" >/dev/null
  dpkg-deb --extract "$package_path" "$temp_dir/root"
  bundle_path="$temp_dir/root/opt/tabame"
  [[ -x "$temp_dir/root/usr/bin/tabame" ]] || { echo "Package is missing /usr/bin/tabame." >&2; exit 1; }
fi

[[ -x "$bundle_path/tabame" ]] || { echo "Bundle executable is missing: $bundle_path/tabame" >&2; exit 1; }
[[ -d "$bundle_path/data" ]] || { echo "Bundle data directory is missing: $bundle_path/data" >&2; exit 1; }
[[ -d "$bundle_path/lib" ]] || { echo "Bundle lib directory is missing: $bundle_path/lib" >&2; exit 1; }

if (( no_launch )); then
  echo "Linux package layout smoke passed (launch skipped)."
  exit 0
fi

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "A graphical session is required for launch smoke; use --no-launch for layout-only validation." >&2
  exit 2
fi

(
  cd "$bundle_path"
  ./tabame -launcher phase9-release-smoke
) >"$log_path" 2>&1 &
pid=$!

for _ in $(seq 1 "$duration"); do
  if ! kill -0 "$pid" 2>/dev/null; then
    cat "$log_path" >&2
    echo "Tabame exited before the Linux smoke interval completed." >&2
    exit 1
  fi
  sleep 1
done

echo "Linux package launch smoke passed for ${duration}s."
