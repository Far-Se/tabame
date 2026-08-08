#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: check-linux-reproducibility.sh --bundle PATH --version VERSION --arch ARCH --source-date-epoch SEC
EOF
}

bundle_path=""
app_version=""
deb_arch=""
source_date_epoch="${SOURCE_DATE_EPOCH:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      bundle_path="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      app_version="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      deb_arch="$2"
      shift 2
      ;;
    --source-date-epoch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_date_epoch="$2"
      shift 2
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

if [[ -z "$bundle_path" || -z "$app_version" || -z "$deb_arch" || -z "$source_date_epoch" ]]; then
  usage
  exit 2
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "--source-date-epoch must be an integer Unix timestamp." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tabame-repro.XXXXXX")"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

for pass in one two; do
  mkdir -p "$temp_dir/$pass"
  SOURCE_DATE_EPOCH="$source_date_epoch" bash "$repo_root/tool/release/package-linux-deb.sh" \
    --bundle "$bundle_path" \
    --version "$app_version" \
    --arch "$deb_arch" \
    --output-dir "$temp_dir/$pass" \
    --source-date-epoch "$source_date_epoch" >/dev/null
done

package_name="tabame_${app_version//+/~}_${deb_arch}.deb"
cmp "$temp_dir/one/$package_name" "$temp_dir/two/$package_name"
cmp "$temp_dir/one/$package_name.sha256" "$temp_dir/two/$package_name.sha256"
echo "Linux package is byte-for-byte reproducible for source date $source_date_epoch."
