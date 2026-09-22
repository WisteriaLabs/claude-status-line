#!/usr/bin/env bash
# ~/.claude/statusline-collector.sh — background fetcher for statusline.sh
# Ported from github.com/Djentinga/claude-statusline (src/collector.ts).
#
# Usage: statusline-collector.sh <cache_file> <claude_version> <fetch_usage:0|1>
#
# Writes {"ts", "incident", "usage"} atomically to <cache_file>. Spawned
# detached by statusline.sh when the cache is older than CACHE_TTL, so the
# status line itself never waits on the network.

set -uo pipefail

cache_file="$1"
version="${2:-unknown}"
fetch_usage="${3:-0}"

lock_dir="${cache_file}.lock"
# mkdir is atomic — the loser of a race between two sessions just exits.
# A lock older than 60s belongs to a collector that died; reclaim it.
if ! mkdir "$lock_dir" 2>/dev/null; then
  lock_mtime=$(stat -c %Y "$lock_dir" 2>/dev/null || stat -f %m "$lock_dir" 2>/dev/null || echo 0)
  (( $(date +%s) - lock_mtime > 60 )) || exit 0
  rm -rf "$lock_dir"; mkdir "$lock_dir" 2>/dev/null || exit 0
fi
trap 'rm -rf "$lock_dir"' EXIT

incident=$(curl -fsS --max-time 3 https://status.claude.com/api/v2/incidents/unresolved.json 2>/dev/null |
  jq -c '
    {critical: 3, major: 2, minor: 1, none: 0} as $rank
    | .incidents // [] | sort_by(-($rank[.impact] // 0)) | first // null
    | if . then {name, status, impact} else null end
  ' 2>/dev/null | tr -d '\r')
[[ -z "$incident" ]] && incident=null

# Plan usage from the OAuth endpoint — only needed when Claude Code's stdin
# carries no rate_limits (enterprise accounts bill credits instead).
usage=null
if [[ "$fetch_usage" == "1" ]]; then
  token=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null | tr -d '\r')
  if [[ -n "$token" ]]; then
    usage=$(curl -fsS --max-time 3 https://api.anthropic.com/api/oauth/usage \
      -H "Authorization: Bearer ${token}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "User-Agent: claude-code/${version}" 2>/dev/null | jq -c . 2>/dev/null | tr -d '\r')
    [[ -z "$usage" ]] && usage=null
  fi
fi

tmp="${cache_file}.$$.tmp"
jq -n -c --argjson incident "$incident" --argjson usage "$usage" \
  '{ts: now, incident: $incident, usage: $usage}' > "$tmp" 2>/dev/null &&
  mv -f "$tmp" "$cache_file"
rm -f "$tmp"
