#!/usr/bin/env sh
# Installs (or removes) the OrkestraKu /orchestrator skill for Claude Code.
#
#   curl -fsSL https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.sh | sh -s -- --project
#   curl -fsSL https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.sh | sh -s -- --uninstall
#
# Options: --project (install into ./.claude/skills)  --ref <branch|tag>
#          --source <local SKILL.md>  --uninstall
set -eu

REPO="yoelkh/orkestraku"
SKILL="orchestrator"
REF="main"
SCOPE="user"
SOURCE=""
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) SCOPE="project" ;;
    --ref) REF="$2"; shift ;;
    --source) SOURCE="$2"; shift ;;
    --uninstall) UNINSTALL=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$SCOPE" = "project" ]; then BASE="$(pwd)/.claude/skills"; else BASE="$HOME/.claude/skills"; fi
TARGET="$BASE/$SKILL"
FILE="$TARGET/SKILL.md"

printf '\n  OrkestraKu  /orchestrator skill for Claude Code\n\n'

if [ "$UNINSTALL" -eq 1 ]; then
  if [ -f "$FILE" ]; then
    rm -f "$FILE"; echo "  [OK] Removed $FILE"
    rmdir "$TARGET" 2>/dev/null && echo "  [OK] Removed empty $TARGET" || true
  else
    echo "  [--] Nothing to remove at $FILE"
  fi
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ -n "$SOURCE" ]; then
  cp "$SOURCE" "$TMP"; echo "  [OK] Using local source $SOURCE"
else
  URL="https://raw.githubusercontent.com/$REPO/$REF/skills/$SKILL/SKILL.md"
  echo "  Downloading $URL"
  curl -fsSL "$URL" -o "$TMP"
fi

if ! head -n 1 "$TMP" | grep -q '^---' || ! grep -Eq "^name:[[:space:]]*$SKILL[[:space:]]*$" "$TMP"; then
  echo "  [!!] Downloaded file does not look like the $SKILL skill. Nothing was changed." >&2
  exit 1
fi

mkdir -p "$TARGET"
if [ -f "$FILE" ]; then
  if cmp -s "$TMP" "$FILE"; then
    echo "  [OK] Already up to date: $FILE"
  else
    BAK="$FILE.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$FILE" "$BAK"; echo "  [OK] Backed up previous version to $BAK"
    cp "$TMP" "$FILE"; echo "  [OK] Updated $FILE"
  fi
else
  cp "$TMP" "$FILE"; echo "  [OK] Installed $FILE"
fi

printf '\n  Workers\n'
check() {
  name="$1"; cmd="$2"; shift 2
  if command -v "$cmd" >/dev/null 2>&1; then
    if v="$("$cmd" "$@" 2>&1 | head -n 1)"; then echo "  [OK] $name  $v"; else echo "  [!!] $name  found but failed to run"; fi
  else
    echo "  [--] $name  not installed"
  fi
}
check "grok    " grok --no-auto-update --version
check "agy     " agy --version
check "opencode" opencode --version
echo "  [OK] sub       Claude subagents (always available inside Claude Code)"

printf '\n  Next: open Claude Code and run /orchestrator <your task>\n'
printf '  Missing workers are skipped automatically; the skill never installs or logs in anything for you.\n\n'
