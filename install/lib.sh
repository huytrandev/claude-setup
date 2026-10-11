# Installer functions for claude-setup. Sourced by install.sh and the tests; no side effects on load.

cs_is_windows() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# Moves dest into backup_dir, keeping its path relative to .claude/ (basename outside .claude/).
_cs_backup() { # $1=dest $2=backup_dir
  local rel
  case "$1" in */.claude/*) rel="${1##*/.claude/}" ;; *) rel="$(basename "$1")" ;; esac
  mkdir -p "$(dirname "$2/$rel")"
  mv "$1" "$2/$rel"
}

cs_link_item() {
  local src="$1" dest="$2" backup="$3" mode="$4"
  if [ "$mode" = link ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "ok $dest"; return 0
  fi
  if [ "$mode" = copy ] && [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
    echo "ok $dest"; return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then _cs_backup "$dest" "$backup"; fi
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = link ]; then ln -s "$src" "$dest"; else cp -R "$src" "$dest"; fi
  echo "changed $dest"
}

# Installs settings.json as a copy. With jq, extraKnownMarketplaces (written by the Claude CLI)
# is preserved from the target and ignored when comparing; without jq, a plain copy.
cs_install_settings() {
  local src="$1" dest="$2" backup="$3" merged
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$dest" ] || [ -L "$dest" ] || ! jq empty "$dest" >/dev/null 2>&1; then
    cs_link_item "$src" "$dest" "$backup" copy
    return
  fi
  merged="$(jq -S --slurpfile old "$dest" \
    '. + (if $old[0].extraKnownMarketplaces then {extraKnownMarketplaces: $old[0].extraKnownMarketplaces} else {} end)' "$src")" \
    || { cs_link_item "$src" "$dest" "$backup" copy; return; }
  if [ "$merged" = "$(jq -S . "$dest")" ]; then echo "ok $dest"; return 0; fi
  _cs_backup "$dest" "$backup"
  printf '%s\n' "$merged" > "$dest"
  echo "changed $dest"
}

cs_enabled_plugins() {
  tr -d '\n' < "$1" | grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' | sed 's/^"\([^"]*\)".*/\1/'
}

cs_check_deps() {
  local rc=0
  command -v git >/dev/null 2>&1 || echo "warn: git not found — needed to clone and update this repo."
  command -v jq >/dev/null 2>&1 || echo "warn: jq not found — the destructive-command guard hook and the statusline are INACTIVE until jq is installed."
  command -v claude >/dev/null 2>&1 || { echo "warn: claude CLI not found — plugin steps skipped. Install Claude Code, then re-run."; rc=1; }
  return "$rc"
}

cs_ensure_marketplace() {
  if claude plugin marketplace list 2>/dev/null </dev/null | grep -q -F "$1"; then echo "ok marketplace $1"; return 0; fi
  if claude plugin marketplace add "$2" </dev/null; then echo "changed marketplace $1"; else echo "failed marketplace $1"; return 1; fi
}

cs_ensure_plugin() {
  if claude plugin list 2>/dev/null </dev/null | grep -q -F "$1"; then echo "ok plugin $1"; return 0; fi
  if claude plugin install "$1" </dev/null; then echo "changed plugin $1"; else echo "failed plugin $1"; return 1; fi
}
