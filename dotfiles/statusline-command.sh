#!/usr/bin/env bash
# Two-line Claude Code statusLine — minimal, pipe-separated.
#
# Line 1: 󰝰 folder | 󰊢 branch* +2 ~1 -1 | ↑2 ↓1
# Line 2: 󰧑 model 󰓅 effort | 󰆼 █░░░░░ 8% | 󰅐 5h 59% (6:30pm) | 󰃭 7d 62% (Thu 6:30pm)
#
# Design notes:
#   - Exactly 4 subprocesses per render: 1 jq, 1 git, 2 date.
#   - Colors are stored as real ESC bytes ($'...') so the final printf uses
#     %s, never %b — payload data is never escape-interpreted.
#   - Fields are joined with US (0x1f), not TAB: read(1) collapses runs of
#     *whitespace* IFS delimiters, which would silently shift empty fields.
#   - date(1) differs between BSD (macOS) and GNU (Linux): see fmt_time.

input=$(cat)

# ── Single jq pass: extract + round everything ──
US=$'\037'
data=$(printf '%s' "$input" | jq -r '
  def r: if . == null then "" else (round | tostring) end;
  . as $i
  | ($i.context_window // {}) as $cw
  | ($i.rate_limits // {})    as $rl
  | [
      ($i.workspace.current_dir // $i.cwd // ""),
      ($i.model.display_name // $i.model.id // ""),
      ($i.effort.level // ""),
      (if $cw.used_percentage != null then $cw.used_percentage
       elif ($cw.total_input_tokens != null and (($cw.context_window_size // 0) > 0))
         then ($cw.total_input_tokens / $cw.context_window_size * 100)
       else 0 end | r),
      ($rl.five_hour.used_percentage | r),
      ($rl.five_hour.resets_at // "" | tostring),
      ($rl.seven_day.used_percentage | r),
      ($rl.seven_day.resets_at // "" | tostring)
    ] | join("\u001f")
' 2>/dev/null)

IFS=$US read -r cwd model_name effort ctx_pct fh_pct fh_at sd_pct sd_at <<< "$data"

# ── Colors (text only, no backgrounds) ──
MUTED=$'\033[38;2;128;128;128m'

# Section identity — one hue per section, none overlapping the status triad
BLUE=$'\033[38;2;108;155;249m'          # folder
BRANCH_CLR=$'\033[38;2;175;145;215m'    # git branch
ORANGE=$'\033[38;2;246;133;12m'         # model
CTX_CLR=$'\033[38;2;95;175;185m'        # context window
RATE_CLR=$'\033[38;2;215;145;175m'      # rate-limit windows

# Status triad — shared by diff, sync, rate limits, context
GREEN=$'\033[38;2;140;185;130m'
YELLOW=$'\033[38;2;215;175;95m'
RED=$'\033[38;2;220;105;100m'

RESET=$'\033[0m'
SEP="${MUTED} | ${RESET}"

GIT_ICON='󰊢'
BRAIN_ICON='󰧑'
FOLDER_ICON='󰝰'
CTX_ICON='󰆼'
CLOCK_ICON='󰅐'
CAL_ICON='󰃭'
SPEED_ICON='󰓅'

line1=""
line2=""

append1() {
  [ -z "$1" ] && return
  if [ -z "$line1" ]; then line1="$1"; else line1="${line1}${SEP}$1"; fi
}
append2() {
  [ -z "$1" ] && return
  if [ -z "$line2" ]; then line2="$1"; else line2="${line2}${SEP}$1"; fi
}

# Sets _c to the state colour for pct $1; $2 is the colour used below 50%.
_c=""
set_color() {
  if   [ "${1:-0}" -ge 80 ]; then _c=$RED
  elif [ "${1:-0}" -ge 50 ]; then _c=$YELLOW
  else _c=$2
  fi
}

# Emits its own colors: fill carries the state colour, the track stays muted.
make_bar() {
  local p=${1:-0} fill_clr=$2 width=${3:-6} filled empty i fill="" track=""
  filled=$(( (p * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 1 ] && [ "$p" -gt 0 ] && filled=1
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( width - filled ))
  for ((i=0; i<filled; i++)); do fill="${fill}█"; done
  for ((i=0; i<empty; i++)); do track="${track}░"; done
  printf '%s' "${fill_clr}${fill}${MUTED}${track}${RESET}"
}

# One date(1) call per timestamp -> sets _time ("6:30pm") and _dow ("Thu").
#
# BSD date (macOS) reads an epoch with `-r SECONDS`; GNU date (Linux) reads it
# with `-d @SECONDS` and treats `-r` as "reference FILE". Probing costs nothing
# on macOS (the BSD form succeeds first) and one extra call on Linux, after
# which the flavour is cached for the second timestamp.
_time=""; _dow=""
_date_kind=""
fmt_time() {
  _time=""; _dow=""
  [ -z "$1" ] && return
  local raw h m ap dow fmt='+%l:%M:%p:%a'
  case $_date_kind in
    bsd) raw=$(date -r "$1" "$fmt" 2>/dev/null) ;;
    gnu) raw=$(date -d "@$1" "$fmt" 2>/dev/null) ;;
    *)
      if raw=$(date -r "$1" "$fmt" 2>/dev/null) && [ -n "$raw" ]; then
        _date_kind=bsd
      elif raw=$(date -d "@$1" "$fmt" 2>/dev/null) && [ -n "$raw" ]; then
        _date_kind=gnu
      else
        return
      fi
      ;;
  esac
  [ -z "$raw" ] && return
  IFS=: read -r h m ap dow <<< "$raw"
  h=${h// /}
  case "$ap" in AM|am) ap=am ;; PM|pm) ap=pm ;; esac
  _time="${h}:${m}${ap}"
  _dow=$dow
}

# ==== LINE 1 ====

# Strip to the last path segment. The bracket class covers Git Bash on Windows,
# where cwd arrives as a backslash-separated path.
folder_name=${cwd##*[/\\]}
[ -n "$folder_name" ] && append1 "${BLUE}${FOLDER_ICON} ${folder_name}${RESET}"

# Single git call: branch name, ahead/behind and file status all at once.
gitout=""
if [ -n "$cwd" ] && cd "$cwd" 2>/dev/null; then
  gitout=$(git --no-optional-locks status --porcelain=v2 --branch --untracked-files=all 2>/dev/null)
fi

branch=""; ahead=0; behind=0
added=0; modified=0; deleted=0; conflicts=0

if [ -n "$gitout" ]; then
  while IFS= read -r line; do
    case "$line" in
      '# branch.head '*)
        branch=${line#\# branch.head }
        ;;
      '# branch.ab '*)
        ab=${line#\# branch.ab }
        ahead=${ab%% *}; ahead=${ahead#+}
        behind=${ab##* }; behind=${behind#-}
        ;;
      '# '*) ;;
      '? '*) added=$(( added + 1 )) ;;
      'u '*) conflicts=$(( conflicts + 1 )) ;;
      '1 '*|'2 '*)
        # v2 entry: "1 XY sub mH mI mW hH hI path"  -> XY at offset 2
        xy=${line:2:2}; x=${xy:0:1}; y=${xy:1:1}
        if   [ "$x" = 'A' ]; then added=$(( added + 1 ))
        elif [ "$x" = 'D' ] || [ "$y" = 'D' ]; then deleted=$(( deleted + 1 ))
        else modified=$(( modified + 1 ))
        fi
        ;;
    esac
  done <<< "$gitout"
fi

[ "$branch" = '(detached)' ] && branch='detached'

if [ -n "$branch" ]; then
  total=$(( added + modified + deleted ))

  dirty=""
  [ "$total" -gt 0 ] && dirty="${YELLOW}*"

  append1 "${BRANCH_CLR}${GIT_ICON} ${branch}${dirty}${RESET}"

  # Diff: +A ~M -D
  if [ "$total" -gt 0 ]; then
    diff_str=""
    [ "$added" -gt 0 ] && diff_str="${GREEN}+${added}${RESET}"
    [ "$modified" -gt 0 ] && { [ -n "$diff_str" ] && diff_str="${diff_str} "; diff_str="${diff_str}${YELLOW}~${modified}${RESET}"; }
    [ "$deleted" -gt 0 ] && { [ -n "$diff_str" ] && diff_str="${diff_str} "; diff_str="${diff_str}${RED}-${deleted}${RESET}"; }
    append1 "$diff_str"
  fi

  # Sync: ↑ahead ↓behind !conflicts
  sync_parts=""
  [ "${ahead:-0}" -gt 0 ] && sync_parts="${GREEN}↑${ahead}"
  [ "${behind:-0}" -gt 0 ] && { [ -n "$sync_parts" ] && sync_parts="${sync_parts} "; sync_parts="${sync_parts}${RED}↓${behind}"; }
  [ "$conflicts" -gt 0 ] && { [ -n "$sync_parts" ] && sync_parts="${sync_parts} "; sync_parts="${sync_parts}${RED}!${conflicts}"; }
  [ -n "$sync_parts" ] && append1 "${sync_parts}${RESET}"
fi

# ==== LINE 2 ====

model_name=${model_name/ context)/)}
if [ -n "$model_name" ]; then
  model_part="${ORANGE}${BRAIN_ICON} ${model_name}${RESET}"
  [ -n "$effort" ] && model_part="${model_part} ${ORANGE}${SPEED_ICON} ${effort}${RESET}"
  append2 "$model_part"
fi

# Context: 󰆼 ██░░░░ 8%
if [ -n "$ctx_pct" ]; then
  set_color "$ctx_pct" "$CTX_CLR"
  bar=$(make_bar "$ctx_pct" "$_c")
  append2 "${CTX_CLR}${CTX_ICON}${RESET} ${bar} ${_c}${ctx_pct}%${RESET}"
fi

# 5h: 󰅐 5h 59% (6:30pm)
if [ -n "$fh_pct" ]; then
  set_color "$fh_pct" "$GREEN"
  fmt_time "$fh_at"
  fh_part="${RATE_CLR}${CLOCK_ICON} 5h${RESET} ${_c}${fh_pct}%${RESET}"
  [ -n "$_time" ] && fh_part="${fh_part} ${RATE_CLR}(${_time})${RESET}"
  append2 "$fh_part"
fi

# 7d: 󰃭 7d 62% (Thu 6:30pm)
if [ -n "$sd_pct" ]; then
  set_color "$sd_pct" "$GREEN"
  fmt_time "$sd_at"
  sd_part="${RATE_CLR}${CAL_ICON} 7d${RESET} ${_c}${sd_pct}%${RESET}"
  [ -n "$_time" ] && sd_part="${sd_part} ${RATE_CLR}(${_dow} ${_time})${RESET}"
  append2 "$sd_part"
fi

printf '%s\n%s' "$line1" "$line2"
