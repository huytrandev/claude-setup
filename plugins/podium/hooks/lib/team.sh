# Team resolution for the podium SessionStart hook.
# Pure bash + sed/grep; jq or python3 are used only to syntax-check team.json when present.

PODIUM_SLOTS="planner critic builder scout"

podium_default_agent() {
  case "$1" in
    planner) echo "podium:composer" ;;
    critic) echo "podium:critic" ;;
    builder) echo "podium:performer" ;;
    scout) echo "podium:scout" ;;
    *) return 1 ;;
  esac
}

# Prints the first string value of "key": "value" in file. Keys in team.json are unique,
# so flat extraction is enough; null and absent keys print nothing.
podium_json_string() {
  [ -f "$1" ] || return 0
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

# 0 = valid, 1 = invalid, 2 = no working checker.
podium_json_valid() {
  if command -v jq >/dev/null 2>&1; then
    jq empty "$1" >/dev/null 2>&1 && return 0 || return 1
  fi
  # On Windows python3 may be a Store stub that exits non-zero; probe before trusting it.
  if command -v python3 >/dev/null 2>&1 && python3 -c 'pass' >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1 && return 0 || return 1
  fi
  return 2
}

podium_agent_exists() {
  local name="$1" project_dir="$2" plugin_root="$3" home="$4" dir f
  case "$name" in
    podium:*) [ -f "${plugin_root}/agents/${name#podium:}.md" ]; return $? ;;
    *:*) return 0 ;;  # another plugin's agent: cannot be checked cheaply, trust the binding
  esac
  for dir in "${project_dir}/.claude/agents" "${home}/.claude/agents"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      grep -q -E "^name:[[:space:]]*${name}[[:space:]]*$" "$f" && return 0
    done
  done
  return 1
}

podium_workspace() {
  local team_file="$1" project_dir="$2" home="$3" ws
  ws="$(podium_json_string "$team_file" workspace)"
  if [ -z "$ws" ]; then echo "${home}/.agent-work"; return 0; fi
  case "$ws" in
    "~"*) echo "${home}${ws#\~}" ;;
    /*|[A-Za-z]:*) echo "$ws" ;;
    *) echo "${project_dir}/${ws}" ;;
  esac
}

podium_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

podium_build_context() {
  local project_dir="$1" plugin_root="$2" home="$3"
  local team_file="${project_dir}/.claude/team.json"
  local source="podium defaults" use_team=0 warnings="" rows="" rc slot agent bound fallback
  if [ -f "$team_file" ]; then
    rc=0; podium_json_valid "$team_file" || rc=$?
    case "$rc" in
      0) use_team=1; source=".claude/team.json" ;;
      2) use_team=1; source=".claude/team.json (syntax not checked: no jq or python3)" ;;
      *) warnings="${warnings}- .claude/team.json is not valid JSON; using podium defaults for every slot."$'\n' ;;
    esac
  fi
  for slot in $PODIUM_SLOTS; do
    agent="$(podium_default_agent "$slot")"
    if [ "$use_team" = 1 ]; then
      bound="$(podium_json_string "$team_file" "$slot")"
      if [ -n "$bound" ]; then
        if podium_agent_exists "$bound" "$project_dir" "$plugin_root" "$home"; then
          agent="$bound"
        else
          warnings="${warnings}- Slot '${slot}' binds missing agent '${bound}'; falling back to ${agent}."$'\n'
        fi
      fi
    fi
    rows="${rows}| ${slot} | ${agent} |"$'\n'
  done
  fallback=""
  [ "$use_team" = 1 ] && fallback="$(podium_json_string "$team_file" fallbackModel)"
  [ -n "$warnings" ] || warnings="none"$'\n'
  case "$warnings" in none*) warnings="Warnings: none" ;; *) warnings="Warnings:"$'\n'"${warnings%$'\n'}" ;; esac
  printf '%s\n' "<podium>
Podium is active and you are the CONDUCTOR. Before handling any user request, invoke the \`podium:conduct\` skill and follow it. It overrides superpowers' instruction to brainstorm or write plans in the main session: that work is delegated to the planner slot below.

Team source: ${source}
| slot | agent |
|---|---|
${rows%$'\n'}
Workspace root: $(podium_workspace "$team_file" "$project_dir" "$home")
Fallback model: ${fallback:-none}
${warnings}
</podium>"
}
