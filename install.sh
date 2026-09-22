#!/usr/bin/env bash
# install.sh — install the Claude Code status line into ~/.claude
#
#   ./install.sh               install (or update) and wire it into settings.json
#   ./install.sh --uninstall   remove the scripts and the statusLine setting
#
# Also works piped from the web:
#   curl -fsSL https://raw.githubusercontent.com/WisteriaLabs/claude-status-line/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/WisteriaLabs/claude-status-line/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
FILES=(statusline.sh statusline-collector.sh)

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq / apt install jq / scoop install jq)"
command -v curl >/dev/null 2>&1 || warn "curl not found — service status and usage fallback will be disabled"

mkdir -p "$CLAUDE_DIR"
stamp=$(date +%Y%m%d%H%M%S)

backup() { [[ -f "$1" ]] && cp "$1" "$1.bak-$stamp" && info "backed up $1 -> $1.bak-$stamp"; return 0; }

if [[ "${1:-}" == "--uninstall" ]]; then
  for f in "${FILES[@]}"; do rm -f "$CLAUDE_DIR/$f"; done
  if [[ -f "$SETTINGS" ]]; then
    backup "$SETTINGS"
    tmp=$(mktemp)
    jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  fi
  info "uninstalled — restart Claude Code to apply"
  exit 0
fi

# Prefer the copies next to this script; fall back to downloading them.
src_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

for f in "${FILES[@]}"; do
  backup "$CLAUDE_DIR/$f"
  if [[ -n "$src_dir" && -f "$src_dir/$f" ]]; then
    cp "$src_dir/$f" "$CLAUDE_DIR/$f"
  else
    curl -fsSL "$REPO_RAW/$f" -o "$CLAUDE_DIR/$f" || die "failed to download $f"
  fi
  # strip CRLF in case the file was checked out on Windows with autocrlf
  sed -i.tmp 's/\r$//' "$CLAUDE_DIR/$f" && rm -f "$CLAUDE_DIR/$f.tmp"
  chmod +x "$CLAUDE_DIR/$f"
  info "installed $CLAUDE_DIR/$f"
done

[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
backup "$SETTINGS"
tmp=$(mktemp)
script_path="$CLAUDE_DIR/statusline.sh"
[[ "$CLAUDE_DIR" == "$HOME/.claude" ]] && script_path="~/.claude/statusline.sh"
jq --arg cmd "bash $script_path" '.statusLine = {
      type: "command",
      command: $cmd,
      timeout: 10,
      refreshInterval: 5
    }' "$SETTINGS" > "$tmp" || die "could not parse $SETTINGS"
mv "$tmp" "$SETTINGS"
info "statusLine configured in $SETTINGS"

info "done — restart Claude Code (or start a new session) to see it"
