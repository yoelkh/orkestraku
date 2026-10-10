#!/usr/bin/env sh
# Installs (or removes) the OrkestraKu /orchestrator skill for Claude Code.
#
#   curl -fsSL https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.sh | sh -s -- --project
#   curl -fsSL https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.sh | sh -s -- --uninstall
#
# Options: --project (install into ./.claude/skills)  --ref <branch|tag>
#          --source <local skill folder>  --uninstall  --no-scan
set -eu

REPO="yoelkh/orkestraku"
SKILL="orchestrator"
FILES="SKILL.md references/workers.md scripts/discover.ps1 scripts/discover.sh"
REF="main"
SCOPE="user"
SOURCE=""
UNINSTALL=0
SCAN=1

while [ $# -gt 0 ]; do
  case "$1" in
    --project) SCOPE="project" ;;
    --ref) REF="$2"; shift ;;
    --source) SOURCE="$2"; shift ;;
    --uninstall) UNINSTALL=1 ;;
    --no-scan) SCAN=0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$SCOPE" = "project" ]; then BASE="$(pwd)/.claude/skills"; else BASE="$HOME/.claude/skills"; fi
TARGET="$BASE/$SKILL"

printf '\n  OrkestraKu  /orchestrator skill for Claude Code\n\n'

if [ "$UNINSTALL" -eq 1 ]; then
  removed=0
  for f in $FILES; do
    if [ -f "$TARGET/$f" ]; then rm -f "$TARGET/$f"; removed=$((removed + 1)); fi
  done
  rmdir "$TARGET/references" "$TARGET/scripts" "$TARGET" 2>/dev/null || true
  if [ "$removed" -gt 0 ]; then echo "  [OK] Removed $removed file(s) from $TARGET"; else echo "  [--] Nothing to remove at $TARGET"; fi
  [ -d "$TARGET" ] && echo "  Kept other files in $TARGET"
  exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ -n "$SOURCE" ]; then echo "  [OK] Using local source $SOURCE"; else echo "  Downloading from github.com/$REPO ($REF)"; fi
for f in $FILES; do
  mkdir -p "$STAGE/$(dirname "$f")"
  if [ -n "$SOURCE" ]; then cp "$SOURCE/$f" "$STAGE/$f"
  else curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/skills/$SKILL/$f" -o "$STAGE/$f"; fi
  if [ ! -s "$STAGE/$f" ]; then echo "  [!!] $f is empty. Nothing was changed." >&2; exit 1; fi
done

if ! head -n 1 "$STAGE/SKILL.md" | grep -q '^---' || ! grep -Eq "^name:[[:space:]]*$SKILL[[:space:]]*\$" "$STAGE/SKILL.md"; then
  echo "  [!!] SKILL.md does not look like the $SKILL skill. Nothing was changed." >&2
  exit 1
fi

BACKUP="$HOME/.claude/orchestra/backups/$(date +%Y%m%d-%H%M%S)"
new=0; upd=0; same=0
for f in $FILES; do
  mkdir -p "$TARGET/$(dirname "$f")"
  if [ -f "$TARGET/$f" ]; then
    if cmp -s "$STAGE/$f" "$TARGET/$f"; then same=$((same + 1)); continue; fi
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$TARGET/$f" "$BACKUP/$f"
    cp "$STAGE/$f" "$TARGET/$f"; upd=$((upd + 1))
  else
    cp "$STAGE/$f" "$TARGET/$f"; new=$((new + 1))
  fi
done
[ "$upd" -gt 0 ] && echo "  [OK] Backed up $upd changed file(s) to $BACKUP"
if [ $((new + upd)) -eq 0 ]; then echo "  [OK] Already up to date: $TARGET"
else echo "  [OK] Installed $TARGET  ($new new, $upd updated, $same unchanged)"; fi

if [ "$SCAN" -eq 1 ]; then
  printf '\n  AI CLIs found on this machine\n'
  sh "$TARGET/scripts/discover.sh" --table | sed 's/^/  /' || echo "  [--] Scan skipped"
  echo "  sub            agent      true   Claude subagents (always available)"
fi

printf '\n  Next: open Claude Code and run /orchestrator setup to analyze your CLIs and get setup advice, then /orchestrator <task>\n'
printf '  Sign-in and API keys stay your call; the skill never installs or logs in anything for you.\n\n'
