#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: package-linux-deb.sh --bundle PATH --version VERSION [options]

Options:
  --bundle PATH             Flutter release bundle directory.
  --version VERSION         Debian package version (for example 2.0.0).
  --arch ARCH              Debian architecture (default: dpkg architecture).
  --output-dir PATH        Destination directory (default: dist).
  --source-date-epoch SEC  Reproducible timestamp (default: git commit time).
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle_path=""
app_version=""
deb_arch=""
output_dir="$repo_root/dist"
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
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      output_dir="$2"
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

if [[ -z "$bundle_path" || -z "$app_version" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$bundle_path" || ! -x "$bundle_path/tabame" ]]; then
  echo "Flutter Linux bundle must contain an executable tabame: $bundle_path" >&2
  exit 1
fi

command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required." >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum is required." >&2; exit 1; }
command -v sed >/dev/null || { echo "sed is required." >&2; exit 1; }
command -v find >/dev/null || { echo "find is required." >&2; exit 1; }

if [[ -z "$deb_arch" ]]; then
  if command -v dpkg >/dev/null; then
    deb_arch="$(dpkg --print-architecture)"
  else
    case "$(uname -m)" in
      x86_64) deb_arch=amd64 ;;
      aarch64|arm64) deb_arch=arm64 ;;
      *) echo "Cannot infer Debian architecture from $(uname -m)." >&2; exit 1 ;;
    esac
  fi
fi

if [[ -z "$source_date_epoch" ]]; then
  source_date_epoch="$(git -C "$repo_root" log -1 --format=%ct 2>/dev/null || true)"
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "--source-date-epoch must be an integer Unix timestamp." >&2
  exit 2
fi
export SOURCE_DATE_EPOCH="$source_date_epoch"

# Debian versions cannot contain the Dart build metadata separator. Keep the
# release version readable while mapping a pubspec '+' to a Debian '~'.
deb_version="${app_version//+/~}"
if [[ ! "$deb_version" =~ ^[0-9A-Za-z.+:~-]+$ ]]; then
  echo "Unsupported package version: $app_version" >&2
  exit 2
fi

desktop_template="$repo_root/packaging/linux/tabame.desktop"
metainfo_template="$repo_root/packaging/linux/tabame.metainfo.xml.in"
control_template="$repo_root/packaging/linux/control.in"
launcher_template="$repo_root/packaging/linux/tabame-launcher"
icon_path="$repo_root/resources/logo_light.png"
for required_file in "$desktop_template" "$metainfo_template" "$control_template" "$launcher_template" "$icon_path"; do
  [[ -f "$required_file" ]] || { echo "Missing packaging input: $required_file" >&2; exit 1; }
done

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
package_name="tabame_${deb_version}_${deb_arch}.deb"
output_path="$output_dir/$package_name"
checksum_path="$output_path.sha256"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/tabame-deb.XXXXXX")"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

package_root="$staging_dir/root"
mkdir -p \
  "$package_root/DEBIAN" \
  "$package_root/opt/tabame" \
  "$package_root/usr/bin" \
  "$package_root/usr/share/applications" \
  "$package_root/usr/share/icons/hicolor/256x256/apps" \
  "$package_root/usr/share/metainfo"

cp -a "$bundle_path/." "$package_root/opt/tabame/"
cp "$launcher_template" "$package_root/usr/bin/tabame"
cp "$icon_path" "$package_root/usr/share/icons/hicolor/256x256/apps/tabame.png"
cp "$desktop_template" "$package_root/usr/share/applications/tabame.desktop"
release_date="$(date -u -d "@$source_date_epoch" +%Y-%m-%d)"
sed -e "s/@VERSION@/$deb_version/g" \
  -e "s/@DATE@/$release_date/g" \
  "$metainfo_template" > "$package_root/usr/share/metainfo/com.farse.tabame.metainfo.xml"
sed -e "s/@VERSION@/$deb_version/g" \
  -e "s/@ARCH@/$deb_arch/g" \
  "$control_template" > "$package_root/DEBIAN/control"

chmod 0755 "$package_root/opt/tabame/tabame" "$package_root/usr/bin/tabame"

# Normalize every package input before dpkg-deb creates its data archive.
# Combined with a fixed source timestamp and a locked dependency graph, this
# makes repeated packaging of the same checkout compare byte-for-byte.
find "$package_root" -exec touch -h -d "@$source_date_epoch" {} +

rm -f "$output_path" "$checksum_path"
dpkg-deb --build --root-owner-group "$package_root" "$output_path" >/dev/null
sha256sum "$output_path" | awk '{print $1 "  " $2}' | sed "s#${output_dir}/##" > "$checksum_path"

echo "Created $output_path"
echo "Created $checksum_path"
