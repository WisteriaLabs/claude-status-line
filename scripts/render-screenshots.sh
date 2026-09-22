#!/usr/bin/env bash
# scripts/render-screenshots.sh — regenerate docs/*.png from examples/*.json
#
# Each examples/<name>.json is fed to statusline.sh as Claude Code would feed
# it. examples/<name>.remote.json, if present, pre-seeds the collector cache so
# the service status / enterprise credit sections render without the network.
# The ANSI output is converted to HTML and captured with headless Chrome.
#
# Requires: bash, jq, git, python3 with Pillow, Chrome/Chromium/Edge.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$root/docs"
mkdir -p "$out_dir"

python=""
for p in python3 python; do
  # skip stubs (e.g. the Windows Store alias) that exist but can't run Pillow
  if "$p" -c 'import PIL' >/dev/null 2>&1; then python=$p; break; fi
done
[[ -n "$python" ]] || { echo "python with Pillow not found (pip install pillow)" >&2; exit 1; }

find_chrome() {
  [[ -n "${CHROME:-}" ]] && { printf '%s' "$CHROME"; return; }
  local c
  for c in google-chrome chromium chromium-browser \
           "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/c/Program Files/Google/Chrome/Application/chrome.exe" \
           "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"; do
    if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then printf '%s' "$c"; return; fi
  done
  echo "Chrome not found — set CHROME=/path/to/chrome" >&2; exit 1
}
chrome=$(find_chrome)

# branch and dirty state of the fake repo shown on line 3, per example
declare -A BRANCH=([pro-max]="feat/checkout-flow" [under-pressure]="fix/race-in-queue" [enterprise]="main")
declare -A DIRTY=([pro-max]=1 [under-pressure]=1 [enterprise]=0)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Windows browsers need native paths
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

for input in "$root"/examples/*.json; do
  [[ "$input" == *.remote.json ]] && continue
  name=$(basename "$input" .json)

  repo="$work/$name/acme-web"
  mkdir -p "$repo"
  git -C "$repo" init -q -b "${BRANCH[$name]:-main}"
  git -C "$repo" -c user.name=demo -c user.email=demo@example.com commit -q --allow-empty -m init
  if [[ "${DIRTY[$name]:-0}" == 1 ]]; then
    echo x > "$repo/file" && git -C "$repo" add file
  fi

  tmp="$work/$name/tmp"
  mkdir -p "$tmp/claude-statusline"
  remote="$root/examples/$name.remote.json"
  [[ -f "$remote" ]] && cp "$remote" "$tmp/claude-statusline/remote.json"

  now=$(date +%s)
  json=$(sed -e "s|__CWD__|$repo|" "$input" |
    perl -pe 's/__NOW_PLUS_(\d+)__/'"$now"'+$1/ge')

  # hide the collector so it can't overwrite the seeded cache
  cp "$root/statusline.sh" "$work/$name/statusline.sh"

  printf '%s' "$json" | TMPDIR="$tmp" bash "$work/$name/statusline.sh" |
    "$python" "$root/scripts/ansi2html.py" > "$work/$name/page.html"

  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1300,200 --screenshot="$(native "$work/$name/raw.png")" \
    "file:///$(native "$work/$name/page.html" | tr '\\' '/')" >/dev/null 2>&1

  "$python" - "$work/$name/raw.png" "$out_dir/$name.png" <<'EOF'
import sys
from PIL import Image, ImageChops
img = Image.open(sys.argv[1]).convert("RGB")
bg = Image.new("RGB", img.size, img.getpixel((0, 0)))
x0, y0, x1, y1 = ImageChops.difference(img, bg).getbbox()
pad = 36
box = (max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + pad, img.width), min(y1 + pad, img.height))
img.crop(box).save(sys.argv[2], optimize=True)
EOF
  echo "wrote docs/$name.png"
done
