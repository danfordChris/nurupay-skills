#!/bin/sh
# Installs NuruPay's integration rules for AI coding assistants.
#
#   Project (default): AGENTS.md gets a NuruPay section; CLAUDE.md and GEMINI.md
#   load AGENTS.md, so every assistant reads the same rules. Also installs the
#   `nurupay` skill into the project.
#   Global (-g): the section goes into each installed assistant's user-level
#   instructions file, and the skill is installed for your user.
#
# Only the section between the nurupay markers is ever added, replaced, or
# removed; the rest of your files is left as it is. Re-running updates it.
#
#   curl -fsSL https://raw.githubusercontent.com/danfordChris/nurupay-skills/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/danfordChris/nurupay-skills/main/install.sh | sh -s -- --global
set -eu

REPO="danfordChris/nurupay-skills"
RAW="https://raw.githubusercontent.com/$REPO/main"
START="<!-- nurupay:start (managed by $REPO/install.sh; re-run it to update) -->"
END="<!-- nurupay:end -->"
IMPORT_MARK="<!-- nurupay: load the shared rules in AGENTS.md -->"

scope=project
dir=
action=install
skill=1

usage() {
  cat <<'EOF'
Usage: install.sh [--project | --global] [--dir PATH] [--no-skill] [--uninstall]

  -p, --project   This project (default): AGENTS.md, plus CLAUDE.md and GEMINI.md
                  that load it, and the skill in the project.
  -g, --global    Your user: ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md,
                  ~/.gemini/GEMINI.md, ~/.config/opencode/AGENTS.md, and
                  Windsurf global rules (only for assistants that are installed),
                  and the skill for your user.
      --dir PATH  Project directory (default: the git root, or the current directory).
      --no-skill  Only write instruction files; do not run `npx skills add`.
      --uninstall Remove the NuruPay section, the CLAUDE.md/GEMINI.md import it
                  added, and the skill.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--project) scope=project ;;
    -g|--global) scope=global ;;
    --dir) [ $# -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }; dir=$2; shift ;;
    --no-skill) skill=0 ;;
    --uninstall|--remove) action=uninstall ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }

snippet() {
  if [ -n "${NURUPAY_SNIPPET:-}" ]; then cat "$NURUPAY_SNIPPET"; return; fi
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$RAW/AGENTS.snippet.md"
  elif command -v wget >/dev/null 2>&1; then wget -qO- "$RAW/AGENTS.snippet.md"
  else echo "Need curl or wget to download the NuruPay rules." >&2; exit 1; fi
}

# Prints the file without the managed section and without trailing blank lines.
strip_block() {
  awk -v s="<!-- nurupay:start" -v e="$END" '
    index($0, s) == 1 { skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { lines[++n] = $0 }
    END { while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }
  ' "$1"
}

has_block() { [ -f "$1" ] && grep -q "^<!-- nurupay:start" "$1"; }

# Adds or replaces the managed section at the end of a file.
upsert() {
  file=$1
  mkdir -p "$(dirname "$file")"
  tmp=$(mktemp)
  if [ -f "$file" ]; then strip_block "$file" >"$tmp"; fi
  if [ -s "$tmp" ]; then printf '\n' >>"$tmp"; fi
  { printf '%s\n' "$START"; printf '%s\n' "$BODY"; printf '%s\n' "$END"; } >>"$tmp"
  existed=0; [ -f "$file" ] && existed=1
  cat "$tmp" >"$file"   # write through, keeping symlinks and permissions
  rm -f "$tmp"
  if [ $existed -eq 1 ]; then say "  updated  $file"; else say "  created  $file"; fi
}

# Removes the managed section; deletes the file if nothing else was in it.
remove_block() {
  file=$1
  has_block "$file" || return 0
  tmp=$(mktemp)
  strip_block "$file" >"$tmp"
  if [ -s "$tmp" ]; then cat "$tmp" >"$file"; say "  cleaned  $file"; else rm -f "$file"; say "  removed  $file"; fi
  rm -f "$tmp"
}

# Makes CLAUDE.md / GEMINI.md load AGENTS.md (both support @imports).
ensure_import() {
  file=$1
  if [ -L "$file" ]; then say "  kept     $file (symlink)"; return; fi
  if [ -f "$file" ] && grep -qx '@AGENTS.md' "$file"; then say "  kept     $file (already loads AGENTS.md)"; return; fi
  if [ -f "$file" ]; then
    tmp=$(mktemp)
    awk '{ l[++n] = $0 } END { while (n > 0 && l[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print l[i] }' "$file" >"$tmp"
    { printf '\n%s\n@AGENTS.md\n' "$IMPORT_MARK"; } >>"$tmp"
    cat "$tmp" >"$file"; rm -f "$tmp"
    say "  updated  $file (loads AGENTS.md)"
  else
    printf '%s\n@AGENTS.md\n' "$IMPORT_MARK" >"$file"
    say "  created  $file (loads AGENTS.md)"
  fi
}

# Removes only the import this script added.
remove_import() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] && grep -qxF "$IMPORT_MARK" "$file" || return 0
  tmp=$(mktemp)
  awk -v m="$IMPORT_MARK" '
    $0 == m { drop = 1; next }
    drop && $0 == "@AGENTS.md" { drop = 0; next }
    { drop = 0; l[++n] = $0 }
    END { while (n > 0 && l[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print l[i] }
  ' "$file" >"$tmp"
  if [ -s "$tmp" ]; then cat "$tmp" >"$file"; say "  cleaned  $file"; else rm -f "$file"; say "  removed  $file"; fi
  rm -f "$tmp"
}

run_skills() {
  [ "$skill" -eq 1 ] || return 0
  if ! command -v npx >/dev/null 2>&1; then
    say "  skipped  skill (npx not found; install Node.js, then run: npx skills add $REPO $1)"
    return 0
  fi
  if [ "$action" = install ]; then
    # shellcheck disable=SC2086
    npx -y skills add "$REPO" --skill nurupay -y $1 </dev/null >/dev/null 2>&1 \
      && say "  installed skill nurupay" \
      || say "  skipped  skill (run: npx skills add $REPO $1)"
  else
    # shellcheck disable=SC2086
    npx -y skills remove nurupay -y $1 </dev/null >/dev/null 2>&1 && say "  removed  skill nurupay" || true
  fi
}

if [ "$action" = install ]; then BODY=$(snippet); fi

if [ "$scope" = project ]; then
  if [ -z "$dir" ]; then dir=$(git rev-parse --show-toplevel 2>/dev/null || pwd); fi
  cd "$dir"
  say "NuruPay rules for AI assistants, project: $(pwd)"
  if [ "$action" = install ]; then
    upsert AGENTS.md
    ensure_import CLAUDE.md
    ensure_import GEMINI.md
    run_skills ""
    say "Done. Codex, Cursor, Copilot, Windsurf, and others read AGENTS.md; Claude Code and Gemini CLI load it through CLAUDE.md and GEMINI.md. Commit these files to share them with your team."
  else
    remove_import CLAUDE.md
    remove_import GEMINI.md
    remove_block AGENTS.md
    run_skills ""
    say "Done."
  fi
else
  say "NuruPay rules for AI assistants, global (user: $HOME)"
  found=0
  for pair in \
    "$HOME/.claude|$HOME/.claude/CLAUDE.md" \
    "$HOME/.codex|$HOME/.codex/AGENTS.md" \
    "$HOME/.gemini|$HOME/.gemini/GEMINI.md" \
    "$HOME/.config/opencode|$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.codeium/windsurf|$HOME/.codeium/windsurf/memories/global_rules.md"; do
    tooldir=${pair%%|*}; file=${pair#*|}
    [ -d "$tooldir" ] || continue
    found=1
    if [ "$action" = install ]; then upsert "$file"; else remove_block "$file"; fi
  done
  [ $found -eq 1 ] || say "  No supported assistant found in $HOME (Claude Code, Codex, Gemini CLI, opencode, Windsurf). Use --project instead."
  run_skills "-g"
  say "Done. Cursor and VS Code Copilot keep global rules in their settings; use --project for them."
fi
