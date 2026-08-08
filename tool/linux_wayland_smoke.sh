#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <linux-bundle-executable> [expected-compositor]" >&2
  exit 2
fi

bundle="$1"
expected_compositor="${2:-mutter}"
if [[ ! -x "$bundle" ]]; then
  echo "Linux bundle executable is missing or not executable: $bundle" >&2
  exit 2
fi
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "This smoke test must run inside a Wayland session." >&2
  exit 2
fi

desktop_identity="${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}"
desktop_identity="${desktop_identity,,}"
case "$expected_compositor" in
  mutter)
    if [[ "$desktop_identity" != *gnome* && "$desktop_identity" != *mutter* ]]; then
      echo "Expected GNOME Shell/Mutter, but desktop identity is: ${desktop_identity#:}" >&2
      exit 2
    fi
    ;;
  weston)
    if [[ "$desktop_identity" != *weston* ]]; then
      echo "Expected Weston, but desktop identity is: ${desktop_identity#:}" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unsupported expected compositor: $expected_compositor (use mutter or weston)." >&2
    exit 2
    ;;
esac

log_file="$(mktemp "${TMPDIR:-/tmp}/tabame-wayland-smoke.XXXXXX.log")"
pid=""
cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$log_file"
}
trap cleanup EXIT

"$bundle" >"$log_file" 2>&1 &
pid=$!

# A live GTK application after startup has been scheduled is the smoke signal.
# This intentionally does not synthesize input or inspect compositor-private
# state.
for _ in {1..8}; do
  if ! kill -0 "$pid" 2>/dev/null; then
    cat "$log_file" >&2
    echo "Tabame exited before the Wayland smoke window became usable." >&2
    exit 1
  fi
  sleep 1
done

echo "Tabame stayed alive under $expected_compositor Wayland for the smoke interval."
