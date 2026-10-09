#!/usr/bin/env sh
# Finds every AI agent CLI on this machine and prints it as JSON for the
# orchestrator brain. Read-only: runs only each CLI's version command, with a
# timeout, and never sends a prompt, logs in, or changes configuration.
#   sh discover.sh            # JSON
#   sh discover.sh --table    # human-readable
set -u

TIMEOUT_SEC=15
TABLE=0
[ "${1:-}" = "--table" ] && TABLE=1

KNOWN="grok:agent agy:agent opencode:agent gemini:agent qwen:agent kimi:agent mimo:agent
codex:agent crush:agent aider:agent cursor-agent:agent copilot:agent amp:agent goose:agent
droid:agent auggie:agent cline:agent kilocode:agent kilo:agent plandex:agent openhands:agent
hermes:agent cn:agent q:agent kiro-cli:agent jules:agent codebuff:agent qodo:agent iflow:agent
vibe:agent letta:agent trae:agent llm:agent aichat:agent sgpt:agent tgpt:agent mods:agent
fabric:agent claude:brain openclaw:gateway ollama:local lms:local llamafile:local"

KEYWORDS='agent|agentic|[^a-z]ai[^a-z]|llm|copilot|assistant|coding|claude|gpt|gemini|codex|chatbot'

run_version() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SEC" "$@" </dev/null 2>&1
  else
    "$@" </dev/null 2>&1
  fi
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r\n'; }

ROWS=""
SEEN=" "
add_row() { # name kind known source path runs version
  ROWS="$ROWS$1|$2|$3|$4|$5|$6|$7
"
  SEEN="$SEEN$1 "
}

probe() { # name kind known source
  name="$1"
  path="$(command -v "$name" 2>/dev/null)" || return 0
  if [ "$name" = "grok" ]; then out="$(run_version "$name" --no-auto-update --version)"; rc=$?
  else out="$(run_version "$name" --version)"; rc=$?; fi
  line="$(printf '%s\n' "$out" | grep -E '[0-9]+\.[0-9]+' | grep -viE 'warning|migration' | head -n 1)"
  [ -z "$line" ] && line="$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | head -n 1)"
  runs=true
  [ "$rc" -ne 0 ] && runs=false
  printf '%s' "$out" | grep -qiE 'not a valid application|postinstall script was not run' && runs=false
  add_row "$name" "$2" "$3" "$4" "$path" "$runs" "$line"
}

for entry in $KNOWN; do
  probe "${entry%%:*}" "${entry#*:}" true path
done

# Unknown candidates from global npm packages (needs node to read package.json).
if command -v npm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  ROOT="$(npm root -g 2>/dev/null)"
  if [ -d "$ROOT" ]; then
    LIST="$(node -e '
      const fs=require("fs"),p=require("path"),r=process.argv[1];
      const dirs=[];
      for (const d of fs.readdirSync(r)) {
        const f=p.join(r,d);
        if (d.startsWith("@")) { for (const s of fs.readdirSync(f)) dirs.push(p.join(f,s)); } else dirs.push(f);
      }
      for (const d of dirs) {
        try {
          const j=JSON.parse(fs.readFileSync(p.join(d,"package.json"),"utf8"));
          if (!j.bin) continue;
          const bins = typeof j.bin==="string" ? [j.name.split("/").pop()] : Object.keys(j.bin);
          const text = (j.name+" "+(j.description||"")+" "+(j.keywords||[]).join(" ")).toLowerCase();
          for (const b of bins) console.log(b+"\t"+j.name+"\t "+text+" ");
        } catch (e) {}
      }' "$ROOT" 2>/dev/null)"
    printf '%s\n' "$LIST" | while IFS="$(printf '\t')" read -r bin pkg text; do
      [ -z "$bin" ] && continue
      case "$SEEN" in *" $bin "*) continue ;; esac
      printf '%s' "$text" | grep -qE "$KEYWORDS" || continue
      command -v "$bin" >/dev/null 2>&1 || continue
      probe "$bin" candidate false "npm:$pkg"
      printf '%s' "$ROWS" | tail -n 1
    done > "${TMPDIR:-/tmp}/orch-discover-$$"
    ROWS="$ROWS$(cat "${TMPDIR:-/tmp}/orch-discover-$$")
"
    rm -f "${TMPDIR:-/tmp}/orch-discover-$$"
  fi
fi

if [ "$TABLE" -eq 1 ]; then
  printf '%-14s %-10s %-6s %s\n' NAME KIND RUNS VERSION
  printf '%s' "$ROWS" | while IFS='|' read -r n k kn s p r v; do
    [ -n "$n" ] && printf '%-14s %-10s %-6s %s  (%s)\n' "$n" "$k" "$r" "$v" "$s"
  done
  exit 0
fi

printf '['
first=1
printf '%s' "$ROWS" | {
  while IFS='|' read -r n k kn s p r v; do
    [ -z "$n" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '\n  {"name":"%s","kind":"%s","known":%s,"source":"%s","path":"%s","runs":%s,"version":"%s"}' \
      "$(json_escape "$n")" "$k" "$kn" "$(json_escape "$s")" "$(json_escape "$p")" "$r" "$(json_escape "$v")"
  done
  printf '\n]\n'
}
