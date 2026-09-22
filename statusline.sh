#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code session status line
# Adapted from github.com/kcchien/claude-code-statusline for Git Bash on Windows,
# with the context/usage/cache/status features of github.com/Djentinga/claude-statusline.
#
# Line 1: <brand> model (effort) | context gradient bar + % + tokens/compact-at | prompt cache | cost | elapsed
# Line 2: 5h usage bar (expected) -> reset | 7d usage bar (expected)   [or enterprise credit bar]
# Line 3: branch* | +added/-removed | dir | agent/worktree | Claude service status
#
# Env vars:
#   CLAUDE_STATUSLINE_ASCII=1        plain ASCII fallback
#   CLAUDE_STATUSLINE_NERDFONT=1     Nerd Font glyphs
#   CLAUDE_STATUSLINE_POWERLINE=1    Powerline separators (defaults to NERDFONT)
#   CLAUDE_STATUSLINE_NO_TRUECOLOR=1 force 16-color mode

set -uo pipefail

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_NERDFONT="${CLAUDE_STATUSLINE_NERDFONT:-0}"
USE_POWERLINE="${CLAUDE_STATUSLINE_POWERLINE:-$USE_NERDFONT}"

# Claude Code's TUI is truecolor-capable; opt out explicitly rather than relying
# on COLORTERM, which is usually unset in this subprocess on Windows.
USE_TRUECOLOR=1
[[ "${CLAUDE_STATUSLINE_NO_TRUECOLOR:-0}" == "1" ]] && USE_TRUECOLOR=0

RST='\033[0m'
CYAN='\033[36m'
BLUE='\033[34m'
GRAY='\033[90m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
BRIGHT_RED='\033[91m'

# Anthropic brand purple (#7266EA)
if (( USE_TRUECOLOR )); then
  PURPLE='\033[38;2;114;102;234m'
  ORANGE='\033[38;2;255;165;0m'
else
  PURPLE='\033[35m'
  ORANGE='\033[33m'
fi

if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND="<>"; S_BRANCH=">"; S_WARN="!"; S_TIME=""; S_COST=""; S_GEAR="*"; SEP=" | "
  S_5H="5h"; S_7D="7d"; S_CREDIT="credit"; S_STATUS="#"
  S_OK="ok"; S_CWARN="!"; S_BAD="x"; S_RESET="->"; S_DIR=""
elif [[ "$USE_NERDFONT" == "1" ]]; then
  S_BRAND="◆"; S_BRANCH="🌿 "; S_WARN=" 󰀦"; S_TIME="󰔟 "; S_COST=" "; S_GEAR="⚙ "
  if [[ "$USE_POWERLINE" == "1" ]]; then SEP="  "; else SEP=" │ "; fi
  S_5H="🕐 5h"; S_7D="📅 7d"; S_CREDIT="💳"; S_STATUS="▣"
  S_OK="✓"; S_CWARN="⚠"; S_BAD="✗"; S_RESET="→"; S_DIR="📁 "
else
  S_BRAND="◆"; S_BRANCH="🌿 "; S_WARN=" ⚠"; S_TIME=""; S_COST=""; S_GEAR="⚙ "
  if [[ "$USE_POWERLINE" == "1" ]]; then SEP="  "; else SEP=" │ "; fi
  S_5H="🕐 5h"; S_7D="📅 7d"; S_CREDIT="💳"; S_STATUS="▣"
  S_OK="✓"; S_CWARN="⚠"; S_BAD="✗"; S_RESET="→"; S_DIR="📁 "
fi

fallback_prompt() {
  printf '%b' "${GRAY}${1:-─}${RST}"
  exit 0
}

command -v jq >/dev/null 2>&1 || fallback_prompt "─ │ jq not found"

input=$(cat)

parsed=$(printf '%s' "$input" | jq -r '
  def leaf: gsub("\\\\"; "/") | split("/") | map(select(length > 0)) | (last // ".");
  def num($d): (. // $d | floor | tostring);
  (.model.display_name // ""),
  (.context_window.used_percentage | num(0)),
  (.cost.total_cost_usd // 0 | tostring),
  (.workspace.current_dir // "." | leaf),
  (.worktree.branch // ""),
  (.rate_limits.five_hour.used_percentage | num(-1)),
  (.rate_limits.seven_day.used_percentage | num(-1)),
  (.agent.name // ""),
  (.workspace.current_dir // "."),
  (.cost.total_lines_added | num(0)),
  (.cost.total_lines_removed | num(0)),
  (.cost.total_duration_ms | num(0)),
  (.context_window.context_window_size | num(0)),
  (.worktree.name // ""),
  (if .prompt_cache.warm == false then "cold" else "warm" end),
  (.prompt_cache.expires_at | num(-1)),
  (.rate_limits.five_hour.resets_at | num(-1)),
  (.rate_limits.seven_day.resets_at | num(-1)),
  (.context_window.current_usage
     | if . then ((.input_tokens // 0) + (.cache_creation_input_tokens // 0)
                  + (.cache_read_input_tokens // 0)) else -1 end | num(-1)),
  (.version // "unknown"),
  (.effort.level // ""),
  "END"
' 2>/dev/null | tr -d '\r') || fallback_prompt "─ │ parse error"

# jq on Windows writes CRLF; a stray \r would poison every numeric comparison
[[ "$parsed" == *END* ]] || fallback_prompt "─ │ parse error"

{
  IFS= read -r model_name
  IFS= read -r ctx_pct
  IFS= read -r cost
  IFS= read -r dir
  IFS= read -r branch
  IFS= read -r rate5h
  IFS= read -r rate7d
  IFS= read -r agent_name
  IFS= read -r cwd_full
  IFS= read -r lines_add
  IFS= read -r lines_rm
  IFS= read -r duration_ms
  IFS= read -r ctx_size
  IFS= read -r wt_name
  IFS= read -r pc_state
  IFS= read -r pc_expires
  IFS= read -r reset5h
  IFS= read -r reset7d
  IFS= read -r ctx_tokens
  IFS= read -r cc_version
  IFS= read -r effort
  IFS= read -r _sentinel
} <<< "$parsed"

model="${model_name:-─}"
now=$(date +%s)

cache_dir="${TMPDIR:-/tmp}/claude-statusline"
mkdir -p "$cache_dir" 2>/dev/null

# ── shared bar renderer ───────────────────────────────────────────────────────
# green -> yellow -> orange -> red, one colour per cell
GRAD_R=(46 116 186 241 239 236 233 231 211 192)
GRAD_G=(204 195 186 196 161 126 101 76 66 57)
GRAD_B=(113 89 64 15 24 34 44 60 50 43)

# threshold colour for 16-colour mode and for the numbers beside a bar
level_color() {
  if   (( $1 >= 90 )); then printf '%s' "$RED"
  elif (( $1 >= 70 )); then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# Usage vs. where you "should" be at this point in the window. Without an
# expected value, fall back to plain thresholds.
budget_color() {
  local actual=$1 expected=$2
  if (( expected < 0 )); then
    if   (( actual < 50 )); then printf '%s' "$GREEN"
    elif (( actual < 75 )); then printf '%s' "$YELLOW"
    elif (( actual < 90 )); then printf '%s' "$RED"
    else printf '%s' "$BRIGHT_RED"; fi
    return
  fi
  local over=$(( actual - expected ))
  if   (( over <= 0  )); then printf '%s' "$GREEN"
  elif (( over <= 10 )); then printf '%s' "$YELLOW"
  elif (( over <= 25 )); then printf '%s' "$RED"
  else printf '%s' "$BRIGHT_RED"; fi
}

# render_bar <pct 0-100> [marker pct, -1 for none]
# Marker cell (expected usage) shows ▒ when already filled past it, ▓ when not.
render_bar() {
  local pct=$1 marker=${2:--1} filled mpos=-1 i out=""
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$(( pct / 10 ))
  if (( marker >= 0 )); then
    (( marker > 100 )) && marker=100
    mpos=$(( marker / 10 ))
    (( mpos > 9 )) && mpos=9
  fi

  if [[ "$USE_ASCII" == "1" ]]; then
    for (( i=0; i<10; i++ )); do
      if   (( i == mpos )); then out+="|"
      elif (( i < filled )); then out+="#"
      else out+="-"; fi
    done
  elif (( USE_TRUECOLOR )); then
    for (( i=0; i<10; i++ )); do
      if (( i < filled )); then
        out+="\\033[38;2;${GRAD_R[$i]};${GRAD_G[$i]};${GRAD_B[$i]}m"
        if (( i == mpos )); then out+="▒"; else out+="█"; fi
      elif (( i == mpos )); then
        out+="\\033[38;2;150;150;150m▓"
      else
        out+="\\033[38;2;60;60;60m░"
      fi
    done
    out+="${RST}"
  else
    for (( i=0; i<10; i++ )); do
      if   (( i == mpos )); then if (( i < filled )); then out+="▒"; else out+="▓"; fi
      elif (( i < filled )); then out+="█"
      else out+="░"; fi
    done
    out="$(level_color "$pct")${out}${RST}"
  fi
  printf '%s' "$out"
}

fmt_tokens() {
  local t=$1
  if   (( t < 1000 ));    then printf '%d' "$t"
  elif (( t < 1000000 )); then printf '%dk' $(( t / 1000 ))
  else printf '%d.%dM' $(( t / 1000000 )) $(( t % 1000000 / 100000 ))
  fi
}

# ── context bar ───────────────────────────────────────────────────────────────
# Rescaled so 100% = the auto-compact threshold, not the raw window: the bar
# answers "how long until compaction", which is what actually matters.
AUTOCOMPACT_BUFFER=33000

raw_pct=${ctx_pct:-0}
(( raw_pct < 0 )) && raw_pct=0
(( raw_pct > 100 )) && raw_pct=100

ctx_size_int=${ctx_size:-0}
(( ctx_size_int <= 0 )) && ctx_size_int=200000
compact_at=$(( ctx_size_int - AUTOCOMPACT_BUFFER ))
(( compact_at <= 0 )) && compact_at=$ctx_size_int

# exact token count when Claude Code reports it, else derive from the percentage
tokens_used=${ctx_tokens:--1}
(( tokens_used < 0 )) && tokens_used=$(( ctx_size_int * raw_pct / 100 ))
pct_int=$(( tokens_used * 100 / compact_at ))
(( pct_int > 100 )) && pct_int=100

bar=$(render_bar "$pct_int")
pct_color=$(level_color "$pct_int")

ctx_warn=""
(( pct_int >= 90 )) && ctx_warn="${RED}${S_WARN}${RST}"

ctx_label=" ${GRAY}$(fmt_tokens "$tokens_used")/$(fmt_tokens "$compact_at")${RST}"
if [[ "$model" != *[Cc]ontext* ]]; then
  if   (( ctx_size_int >= 1000000 )); then ctx_label+=" ${GRAY}1M${RST}"
  elif (( ctx_size_int >= 200000  )); then ctx_label+=" ${GRAY}200k${RST}"
  fi
fi

# ── prompt cache (hidden when Claude Code doesn't report it) ──────────────────
CACHE_WARN_SECS=30
cache_section=""
pc_exp=${pc_expires:--1}
if (( pc_exp > 0 )); then
  left=$(( pc_exp - now ))
  if (( left >= 60 )); then left_fmt="$(( left / 60 ))m"; else left_fmt="${left}s"; fi
  if [[ "$pc_state" == "cold" ]] || (( left <= 0 )); then
    cache_section="${SEP}${RED}${S_BAD} cache${RST}"
  elif (( left <= CACHE_WARN_SECS )); then
    cache_section="${SEP}${YELLOW}${S_CWARN} cache ${left_fmt}${RST}"
  else
    cache_section="${SEP}${GREEN}${S_OK} cache ${left_fmt}${RST}"
  fi
fi

# ── cost ──────────────────────────────────────────────────────────────────────
cost_val="${cost:-0}"
cost_fmt=$(printf '%.2f' "$cost_val" 2>/dev/null) || cost_fmt="0.00"
cost_int=${cost_val%.*}; cost_int=${cost_int:-0}

if   (( cost_int >= 10 )); then cost_color="$RED"
elif (( cost_int >= 5  )); then cost_color="$YELLOW"
elif [[ "$cost_fmt" == "0.00" ]]; then cost_color="$GRAY"
else cost_color="$YELLOW"; fi

# ── elapsed (hidden when zero) ────────────────────────────────────────────────
dur_ms=${duration_ms:-0}
dur_section=""
if (( dur_ms > 0 )); then
  dur_sec=$(( dur_ms / 1000 ))
  dur_min=$(( dur_sec / 60 ))
  dur_s=$(( dur_sec % 60 ))
  if (( dur_min > 0 || dur_s > 0 )); then
    dur_section="${SEP}${GRAY}${S_TIME}${dur_min}m${dur_s}s${RST}"
  fi
fi

# ── background collector: service status (+ usage when stdin lacks it) ───────
COLLECT_TTL=120
STATUS_CACHE="${cache_dir}/remote.json"
COLLECTOR="$(dirname "${BASH_SOURCE[0]}")/statusline-collector.sh"

mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

rate5h_int=${rate5h:--1}
rate7d_int=${rate7d:--1}
need_usage=0
(( rate5h_int < 0 && rate7d_int < 0 )) && need_usage=1

if [[ -f "$COLLECTOR" ]] && { [[ ! -f "$STATUS_CACHE" ]] || (( now - $(mtime_of "$STATUS_CACHE") > COLLECT_TTL )); }; then
  # fully detached: must not hold our stdout open or Claude Code waits on it
  nohup bash "$COLLECTOR" "$STATUS_CACHE" "$cc_version" "$need_usage" >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null
fi

remote=""
[[ -f "$STATUS_CACHE" ]] && remote=$(jq -r '
  def epoch: if . == null or . == "" then -1
             else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | (fromdateiso8601? // -1)) end;
  (.incident.name // ""), (.incident.status // ""), (.incident.impact // ""),
  (.usage.five_hour == null and .usage.seven_day == null and (.usage.extra_usage.is_enabled // false)
     | tostring),
  (.usage.extra_usage.utilization // 0 | floor | tostring),
  (.usage.extra_usage.used_credits // 0 | floor | tostring),
  (.usage.extra_usage.monthly_limit // 0 | floor | tostring),
  (.usage.extra_usage.currency // "USD"),
  (.usage.five_hour.utilization // -1 | floor | tostring),
  (.usage.seven_day.utilization // -1 | floor | tostring),
  (.usage.five_hour.resets_at | epoch | tostring),
  (.usage.seven_day.resets_at | epoch | tostring),
  "END"
' "$STATUS_CACHE" 2>/dev/null | tr -d '\r')

inc_name=""; inc_status=""; inc_impact=""; is_enterprise="false"
credit_util=0; credit_used=0; credit_limit=0; credit_cur="USD"
if [[ "$remote" == *END* ]]; then
  {
    IFS= read -r inc_name
    IFS= read -r inc_status
    IFS= read -r inc_impact
    IFS= read -r is_enterprise
    IFS= read -r credit_util
    IFS= read -r credit_used
    IFS= read -r credit_limit
    IFS= read -r credit_cur
    IFS= read -r r_5h
    IFS= read -r r_7d
    IFS= read -r r_reset5h
    IFS= read -r r_reset7d
  } <<< "$remote"
  # stdin is authoritative; the OAuth endpoint only fills in when it's absent
  if (( need_usage )); then
    rate5h_int=${r_5h:--1}; rate7d_int=${r_7d:--1}
    reset5h=${r_reset5h:--1}; reset7d=${r_reset7d:--1}
  fi
fi

# ── git branch + dirty flag (cached per workspace) ────────────────────────────
GIT_CACHE_MAX_AGE=5
git_branch="${branch:-}"
dirty=""

# one cache file per workspace, so switching repos never shows a stale branch
cache_key=$(printf '%s' "${cwd_full:-.}" | cksum | tr -cd '0-9')
GIT_CACHE="${cache_dir}/git-${cache_key}"

git_cache_is_stale() {
  [[ ! -f "$GIT_CACHE" ]] && return 0
  (( now - $(mtime_of "$GIT_CACHE") > GIT_CACHE_MAX_AGE ))
}

if [[ -n "${cwd_full:-}" && -d "${cwd_full:-}" ]]; then
  if git_cache_is_stale; then
    if git -C "$cwd_full" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
      cached_branch="${git_branch}"
      if [[ -z "$cached_branch" ]]; then
        cached_branch=$(git -C "$cwd_full" --no-optional-locks branch --show-current 2>/dev/null)
        [[ -z "$cached_branch" ]] && cached_branch=$(git -C "$cwd_full" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
      fi
      cached_dirty=""
      if ! git -C "$cwd_full" --no-optional-locks diff --quiet 2>/dev/null || \
         ! git -C "$cwd_full" --no-optional-locks diff --cached --quiet 2>/dev/null; then
        cached_dirty="*"
      fi
      printf '%s|%s\n' "$cached_branch" "$cached_dirty" > "$GIT_CACHE"
    else
      printf '|\n' > "$GIT_CACHE"
    fi
  fi
  if [[ -f "$GIT_CACHE" ]]; then
    IFS='|' read -r cached_br cached_dt < "$GIT_CACHE"
    [[ -z "$git_branch" ]] && git_branch="${cached_br}"
    dirty="${cached_dt}"
  fi
fi

# ── lines changed (hidden when zero) ──────────────────────────────────────────
lines_add=${lines_add:-0}
lines_rm=${lines_rm:-0}
lines_section=""
if (( lines_add > 0 || lines_rm > 0 )); then
  lines_section="${GREEN}+${lines_add}${RST}/${RED}-${lines_rm}${RST}"
fi

# ── usage bars: 5h / 7d with expected-usage markers (Pro/Max) ─────────────────
WINDOW_5H=$(( 5 * 3600 ))
WINDOW_7D=$(( 7 * 86400 ))

# expected_pct <resets_at epoch> <window secs> [daily:0|1]
# How much of the window has elapsed; the 7-day one counts in whole days, so a
# fresh day's allowance is available from its first minute.
expected_pct() {
  local resets=$1 window=$2 daily=${3:-0} elapsed e
  (( resets <= 0 )) && { printf '%s' -1; return; }
  elapsed=$(( window - (resets - now) ))
  (( elapsed < 0 )) && elapsed=0
  if (( daily )); then
    e=$(( ( (elapsed + 86399) / 86400 ) * 100 / (window / 86400) ))
  else
    e=$(( elapsed * 100 / window ))
  fi
  (( e > 100 )) && e=100
  printf '%s' "$e"
}

usage_part() {
  local label=$1 used=$2 exp=$3 c exp_str
  c=$(budget_color "$used" "$exp")
  if (( exp >= 0 )); then exp_str=" ${GRAY}(${exp})${RST}"; else exp_str=""; fi
  printf '%s' "${label} $(render_bar "$used" "$exp") ${c}${used}%${RST}${exp_str}"
}

usage_parts=()
if (( rate5h_int >= 0 )); then
  exp5h=$(expected_pct "${reset5h:--1}" "$WINDOW_5H")
  part=$(usage_part "$S_5H" "$rate5h_int" "$exp5h")
  if (( ${reset5h:--1} > 0 )); then
    reset_hm=$(date -d "@${reset5h}" +%H:%M 2>/dev/null || date -r "${reset5h}" +%H:%M 2>/dev/null)
    [[ -n "$reset_hm" ]] && part+=" ${GRAY}${S_RESET} ${reset_hm}${RST}"
  fi
  (( rate5h_int >= 80 )) && part+="${RED}${S_WARN}${RST}"
  usage_parts+=("$part")
fi
if (( rate7d_int >= 0 )); then
  exp7d=$(expected_pct "${reset7d:--1}" "$WINDOW_7D" 1)
  part=$(usage_part "$S_7D" "$rate7d_int" "$exp7d")
  (( rate7d_int >= 80 )) && part+="${RED}${S_WARN}${RST}"
  usage_parts+=("$part")
fi

# Enterprise: no 5h/7d windows — show monthly credit spend instead
if (( ${#usage_parts[@]} == 0 )) && [[ "$is_enterprise" == "true" ]]; then
  if [[ "$credit_cur" == "USD" ]]; then sym='$'; else sym="${credit_cur} "; fi
  c=$(budget_color "$credit_util" -1)
  used_fmt="${sym}$(( credit_used / 100 )).$(printf '%02d' $(( credit_used % 100 )))"
  usage_parts+=("${S_CREDIT} $(render_bar "$credit_util") ${c}${used_fmt}${RST} / ${sym}$(( credit_limit / 100 )) ${GRAY}(${credit_util}%)${RST}")
fi

# ── Claude service status ─────────────────────────────────────────────────────
status_section=""
if [[ -f "$STATUS_CACHE" ]]; then
  if [[ -z "$inc_name" ]]; then
    status_section="${GREEN}${S_STATUS} Status${RST}"
  else
    case "$inc_impact" in
      critical) sc="$RED" ;;
      major)    sc="$ORANGE" ;;
      minor)    sc="$YELLOW" ;;
      *)        sc="$GRAY" ;;
    esac
    status_section="${sc}${S_STATUS} ${inc_status}: ${inc_name}${RST}"
  fi
fi

# ── line 1 ────────────────────────────────────────────────────────────────────
line1="${PURPLE}${S_BRAND}${RST} ${CYAN}${model}${RST}"
# absent when the model doesn't support the effort parameter
[[ -n "$effort" ]] && line1+=" ${GRAY}(${effort})${RST}"
line1+="${SEP}${bar} ${pct_color}${pct_int}%${RST}${ctx_warn}${ctx_label}"
line1+="${cache_section}"
line1+="${SEP}${cost_color}${S_COST}\$${cost_fmt}${RST}"
line1+="${dur_section}"

# ── line 2 ────────────────────────────────────────────────────────────────────
line2=""
for i in "${!usage_parts[@]}"; do
  (( i > 0 )) && line2+="${SEP}"
  line2+="${usage_parts[$i]}"
done

# ── line 3 ────────────────────────────────────────────────────────────────────
parts=()
[[ -n "$git_branch"    ]] && parts+=("${GRAY}${S_BRANCH}${git_branch}${dirty}${RST}")
[[ -n "$lines_section" ]] && parts+=("${lines_section}")
parts+=("${BLUE}${S_DIR}${dir}${RST}")

if   [[ -n "${wt_name:-}"    ]]; then parts+=("${YELLOW}${S_GEAR}worktree:${wt_name}${RST}")
elif [[ -n "${agent_name:-}" ]]; then parts+=("${YELLOW}${S_GEAR}${agent_name}${RST}")
fi
[[ -n "$status_section" ]] && parts+=("$status_section")

line3=""
for i in "${!parts[@]}"; do
  (( i > 0 )) && line3+="${SEP}"
  line3+="${parts[$i]}"
done

if [[ -n "$line2" ]]; then
  printf '%b\n%b\n%b' "$line1" "$line2" "$line3"
else
  printf '%b\n%b' "$line1" "$line3"
fi
