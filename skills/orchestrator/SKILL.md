---
name: orchestrator
description: Run this session as the BRAIN that discovers every AI agent CLI on the machine (grok, agy/Gemini, opencode, qwen, kimi, hermes, and any other it finds) plus Claude subagents, probes which ones are really usable, and delegates independent work to them — choosing worker, model and effort per task, in supervised or auto-accept mode. No third-party bridge. Use on /orchestrator, "delegasikan", "pakai worker", "scan CLI", or when splitting a task across agents.
allowed-tools: Agent Read Grep Glob
---

# Orchestrator

You are the BRAIN: you plan, decide, supervise, and verify. Workers do the bulk
work. You call worker CLIs yourself with your shell tool — no MCP bridge, no
wrapper package. The brain is this interactive session only — never run
`claude -p` as a worker; use native subagents (`sub`) for Claude workers.

Goal: use **every worker that is actually usable** on this machine, each for
what it is best at — not only the ones you already know.

Supporting files (relative to this skill's folder):
- `scripts/discover.ps1` / `scripts/discover.sh` — finds every AI CLI, prints JSON.
- `references/workers.md` — adapter card per CLI, status values, error → status
  table, onboarding for unknown CLIs, and the probe.

Invocation arguments: $ARGUMENTS

## 0. Parse the invocation
Syntax:
`/orchestrator [workers=<list>] [tier=best|fast|standard|strong] [effort=auto|low|medium|high] [mode=supervised|auto] [rescan] <task>`

- `workers=` comma-separated roster. Each entry is `name`, `name:model`, or
  `name:tier`. Names are CLI command names found by discovery (`grok`, `agy`,
  `opencode`, `qwen`, `kimi`, `hermes`, …) plus `sub` (Claude subagent).
  `gemini` means the Gemini CLI if its status is `ready`; otherwise it is an
  alias for `agy` (say so in the setup line).
  - `name:model` pins that worker to one exact model for every task
    (`agy:gemini-3.8-flash-high`, `sub:opus`).
  - `name:tier` pins only the tier and lets you pick the model in it
    (`agy:fast`, `sub:strong`).
  - A partial name (`agy:flash`, `agy:pro`) is resolved against the model
    catalog (section 1). One match → use it; several → take the newest in the
    matching tier and show the resolution in the setup line; none → treat as
    not available.
  - `workers=ask` → show the `ready` workers and their catalog models with
    AskUserQuestion (multiSelect). In mode=auto, skip and use defaults.
  - `workers=all` or no `workers=` → every worker whose status is `ready`,
    `write-only`, or `web-only`.
  - `workers=-name` excludes a worker (`workers=-hermes`).
- `tier=` global model policy. Default `best`: every task gets the newest,
  best model each worker offers (section 3B). `fast` / `standard` / `strong`
  are opt-in downgrades or pins the user sets.
- `effort=` global default reasoning effort. Default `auto` (section 3).
- `mode=` defaults to `supervised`.
- `rescan` ignores the cache and probes every CLI again (section 1, step 4).
- Anything else is the task. `/orchestrator scan` (no task) runs preflight
  only and shows the worker table.

Echo the resolved setup in one line before working, e.g.
`Roster: grok→grok-4.7, agy→gemini-3.8-flash-high, opencode→opencode/nemotron-3-ultra-free, sub→fable · Idle: qwen (needs-key), kimi (needs-login) · Tier: best · Effort: auto · Mode: supervised · Brain: <session model> · Shell: PowerShell`.

The user can change roster, tier, effort, or a single task's model mid-session
in plain language ("T2 pakai agy pro", "semua pakai fast", "naikkan effort",
"mode auto", "jangan pakai hermes"). Apply it from the next launch and echo
the new setup.

## 1. Preflight (once per session)
1. **Brain check.** Note your own session model. If it is not an Opus- or
   Fable-class model, warn once that brain decisions will be weaker and
   suggest `/model opus` (or `/model fable`, which has a limited quota). You
   cannot change the brain model yourself.
2. **Shell.** Detect the shell (PowerShell on native Windows, bash elsewhere)
   and use the matching commands.
3. **Discover.** Run the discovery script from this skill's folder:
   - PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/discover.ps1`
   - bash: `sh <skill>/scripts/discover.sh`
   It lists every known AI CLI on PATH (kind `agent`, `brain`, `gateway`,
   `local`) plus `candidate` CLIs from global npm packages, with version and
   whether the version command runs. It never sends a prompt. If the script
   is missing, fall back to `Get-Command` / `command -v` on the names in
   `references/workers.md`.
   - `brain` (claude) and `gateway` (openclaw) → status `excluded`.
   - `runs: false` → status `broken`; give the fix from the card if any.
   - `candidate` → read its `--help`; if it is not an agent or LLM CLI (e.g.
     a package manager), drop it silently; otherwise onboard it
     (`references/workers.md`, "Onboarding an unknown CLI").
4. **Cache.** Read `~/.claude/orchestra/workers-cache.md` (create it if
   missing): one row per CLI,
   `worker | version | status | read-profile | strengths | best model | latency | probed | note`.
   - Reuse a `ready` / `write-only` / `web-only` / `excluded` row when the
     version is unchanged and `probed` is under 7 days old.
   - Re-probe every row with any other status at every preflight (auth
     failures return in seconds, so a CLI the user just signed in to is
     picked up right away), every row whose version changed, and every row
     when the user says `rescan`.
5. **Probe.** For each CLI that needs it, read its card in
   `references/workers.md`, confirm the card's flags against `--help` (adapt
   and note any rename; never guess a flag or an effort level), then run
   **the probe** from that file in a scratch folder outside the project
   (your scratchpad, or the system temp folder). Run independent probes in
   parallel. Classify failures with the card file's error → status table.
   Also apply each card's permission audit (for agy: read
   `~/.gemini/antigravity-cli/settings.json` `toolPermission`). Write the
   results back to the cache.
6. **Model catalog — rebuilt every session, never from memory.** For each
   usable worker, list models only from its live source (the card's
   "Models" line; for OpenRouter free models also read
   `https://openrouter.ai/api/v1/models`, no key needed). Write
   `.orchestra/models.md` as
   `worker | model | version | variant | tier | status | selected-as` with
   today's date at the top, then apply 6a–6c.

6a. **Ranking rules (pick the newest, best model per worker).**
   1. **Version first,** within one model family only — never compare across
      vendors (Claude 5.5 vs Gemini 3.8 is not comparable). 4.7 > 4.5 > 4;
      3.8 > 3.1. A higher version beats a lower one regardless of size.
   2. **Variant second, within the same version:** ultra / opus / pro /
      max / heavy (flagship) > unsuffixed base > fast / flash / mini / lite /
      nano / haiku. A "fast" variant that is the same model served faster
      (e.g. a `-fast` sibling) ranks just below its flagship.
   3. **Status third:** GA/stable > preview > experimental at the same
      version and variant. A preview of a HIGHER version still beats an older
      GA model, but only after it passes a smoke test.
   4. **Ignore** deprecated, legacy, embedding, image-only, audio-only, and
      routing/alias entries (e.g. `openrouter/free`, `auto`, `mimo-auto`).
   5. **Tier labels:** flagship variants of the newest version = strong;
      base = standard; fast/flash/mini/lite = fast.
   6. Ties: prefer the CLI's default. Unparseable version or variant → mark
      `rank guessed` and rank below every parsed model.
   7. When a CLI serves several vendors (agy, opencode, hermes, mimo), its
      role ranks only its native family unless the user pins another.

6b. **Smoke test** each worker's selected model with `Reply with OK.` (READ
   profile). On failure try the next in the ranking, up to 3 tries.

6c. **Free models only where a CLI can bill per token** (opencode, mimo,
   hermes, and any CLI with OpenRouter or a metered provider):
   - Only models whose prompt AND completion price are 0 (`:free` on
     OpenRouter, `opencode/*-free` on OpenCode Zen). NEVER select a paid
     model or a metered provider (e.g. Cloudflare Workers AI) — that is
     spending money (hard stop) unless the user opts in.
   - Require tool calling (`supported_parameters` includes `tools`).
   - Drop special-purpose models (safety/guard, roleplay, OCR, vision-only)
     and, for the `best` pick, small variants (mini/nano/small/lite/xs/
     lightning, or under ~20B parameters) — they only qualify as `fast`.
   - Rank: newest `created` first, then flagship per 6a.2, then larger
     `context_length`. Keep the top 3 as a fallback chain.
   - "guardrail restrictions and data policy" / "Free model training
     violation" → the user's OpenRouter privacy settings block ALL free
     models: tell the user (openrouter.ai/settings/privacy — their
     decision) and fall back to OpenCode Zen free models.
   - Never set up a key yourself.

7. **Show the worker table** (always in supervised mode, and on
   `/orchestrator scan`):
   `worker | version | status | profile limits | strengths | best model | latency`
   followed by one line per idle worker with the exact action that would
   enable it ("kimi: run `kimi login`", "qwen: configure an auth type").
8. **Subagent override check.** If `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set,
   every `sub` worker runs on that one model — say so.
9. Never install, update, or log in anything yourself, in any mode — tell
   the user. If no external CLI is usable, continue with `sub` only (normal
   in Cowork and cloud sessions).
10. Create `.orchestra/` with `briefs/`, `runs/`, `models.md`, and
    `orchestra-log.md`. Add `.orchestra/` to `.gitignore` if the project uses
    git. If the project is NOT a git repo, WRITE profiles are unavailable (no
    worktrees): in supervised mode suggest `git init`; until then keep all
    file-changing work for yourself or `sub`.

## 2. When to delegate (all three must be true, otherwise do it yourself)
1. The task is independent: it does not need files another worker is editing.
2. You can brief it in 5 sentences or less, with a clear definition of done.
3. The result can be verified by a test, a command, or a short checklist.

Small tasks (under ~15 minutes of your own work) are never delegated.
Interdependent coding tasks are usually a net loss — keep them yourself.
Parallel read-only research is the clearest win.

## 3. Choosing worker, model, and effort per task

### Step A — worker, by capability (within the active roster)
Each usable worker has strengths in the cache (from its card, or from
onboarding). Match the task to them:

| Work type | Needs | Typical best fit |
|---|---|---|
| Web/X research, current events | web search | grok; hermes (`web-only`) |
| Large repos, long documents, summaries | long context (≥1M) | agy; mimo / kimi when ready |
| Mechanical edits, boilerplate, simple tests | cheap/free, file edits | opencode (free models); qwen / kimi when ready |
| Critical code, architecture, code review | strongest reasoning | sub |
| Second opinion, review of another worker's output | a **different vendor family** than the author | any ready worker of another family |

Rules for using the whole roster:
- **Spread the load.** With several independent tasks, assign them to
  different workers that fit, rather than queueing them on one. At most 2
  concurrent tasks per worker and 5 in total (user can raise it).
- **Panel for high-stakes research or review** (effort high, or the user
  asks "bandingkan"/"second opinion"): send the same READ brief to 2–3
  ready workers from different vendor families, then compare. Agreement →
  higher confidence; disagreement → you check the disputed point yourself.
  A panel counts as one delegation per member.
- **Respect status limits.** `write-only` workers get tasks only in a
  worktree or on a scratch copy; `web-only` workers get only web research.
- If no ready worker fits, do it yourself.

### Step B — model (policy `best` by default)
- **`tier=best` (default):** the worker's `selected-as: best` model from
  `.orchestra/models.md`.
- **`sub` under `best`:** `fable` if available on the user's plan, else
  `opus`; subject to the Claude quota guard in 3D.
- **`tier=fast|standard|strong`** (only when the user sets it): the
  highest-ranked model of that tier; if none, the nearest tier, noted.

### Step C — effort
| Task | Effort |
|---|---|
| Formatting, renames, boilerplate, extracting facts, summarizing short text | low |
| Normal research, reading docs, standard features, tests | medium |
| Architecture, hard debugging, security-sensitive code, final review, synthesis across many sources | high |

Map low/medium/high to the levels in the worker's card / `--help` (or its
model-ID suffix, e.g. agy). No effort flag → omit. For `sub`, pass the Agent
tool's `model` and `effort` with a general-purpose subagent. A global
`effort=` overrides this table.

### Precedence (highest first)
1. A per-task instruction from the user ("T2 pakai agy pro").
2. A `name:model` pin in the roster.
3. A `name:tier` pin in the roster.
4. The global `tier=` / `effort=` values.
5. The default policy `best` (Steps A–C).

### 3D. Escalation and fallback
- **Escalation:** if a task ends BLOCKED twice, fails verification, or needs
  rework, retry it ONCE with a fresh brief that includes what went wrong:
  on a lower tier → one tier higher; already on `best` → same model at the
  highest effort level. If it still fails, reassign to another worker (prefer
  another vendor family) or take it over. Escalation never overrides a
  `name:model` pin — with a pin, reassign instead.
- **Quota / rate limit:** `429`, rate limit, quota, resource exhausted, or
  usage limit → mark that worker:model cooled down for the rest of the run
  and relaunch on the next model in its ranking (OpenRouter free: next in the
  top-3 chain, then `openrouter/free`), else on another worker. Do not retry
  a cooled-down model in the same run. Report every cooldown.
- **Claude quota guard:** at most 2 `sub` workers on `fable` per run, then
  `opus`, unless the user raises the limit.
- **Drift:** if a worker's version changes mid-session, or its selected model
  disappears or a newer one appears, re-probe it (section 1, step 5) before
  its next launch.

### 3E. Learning from the log
Before each choice, read `.orchestra/orchestra-log.md`. If a worker:model has
5 or more entries for this kind of task and fewer than half are "accepted
as-is", prefer the next option and say why in one line. Under `tier=best`,
never downgrade to a cheaper model on your own; you may only suggest it to
the user with the log numbers.

### 3F. Confirm the model actually used
After each run, read the model the worker reports (where: see its card) and
log THAT model. If it differs from the requested one, say so and log both.
Not reported → log `unreported`.

## 4. Brief format
Write each brief to `.orchestra/briefs/<task-id>.md` (task-id like `T1`,
`T2`). Every brief contains:
- GOAL: one sentence.
- CONTEXT: file paths to read (paths, not pasted content).
- CONSTRAINTS: what must not be touched; the working directory; "read-only,
  do not modify any file" for research workers.
- DONE WHEN: the verifiable condition.
- REPORT: end your answer with exactly one status block:

```
STATUS: DONE | BLOCKED | NEED_DECISION
SUMMARY: <max 10 lines>
FILES_CHANGED: <list or none>
QUESTION: <only if BLOCKED or NEED_DECISION>
```

Workers must stop and return BLOCKED instead of guessing when they are unsure
about requirements, hit the same error twice, or need to touch files outside
their scope.

## 5. Permission profiles — the brain picks one per task
- **READ** (research, summaries, review): the card's READ profile, never an
  auto-approve flag. Working directory = the project root or the folder to
  read — except `write-only` workers, which get a scratch copy of the inputs
  outside the project, or a worktree.
- **WRITE** (code or file changes): only inside a dedicated git worktree
  created for that task (`git worktree add .orchestra/wt/<task-id> -b orch/<task-id>`),
  with the card's WRITE profile.

**After every READ run, verify nothing changed:** compare `git status
--porcelain` (or, without git, a file list with sizes and timestamps taken
before launch) with the state before the run. Any change → discard it, set
the worker to `write-only` in the cache for this version, and tell the user.

NEVER pass flags that approve everything (`--yolo`, `-y`, `--dangerously-*`,
`--permission-mode bypassPermissions`, `--approval-mode yolo`, `--never-ask`,
hermes toolsets `terminal`/`file`/`computer_use`/`cronjob` outside a
worktree), and never set any CLI's config to always-approve globally. Never
point a worker's working directory outside the project, its worktrees, or a
scratch folder you created.

## 6. Launching workers (direct CLI)
**Never pass the brief text itself as a command-line argument.** Windows
PowerShell 5.1 strips embedded double quotes from native-command arguments
(`"q"` arrives as `q`), and long multi-line argv is fragile in every shell.
Pass it the way the worker's card says: a prompt-file flag if the CLI has
one (grok `--prompt-file`), otherwise the one-line pointer prompt
`Read the brief file <abs path> and follow its instructions exactly.`

Use absolute paths. Write stdout to `.orchestra/runs/<task-id>.out` and
stderr to `.orchestra/runs/<task-id>.err`. Run every worker with your shell
tool's background option so workers run in parallel; read the output files
when each process ends.

- Record each worker's session ID the way its card says (grok: a fresh UUID
  for `-s`; agy: `conversation_id`; opencode/mimo: session list by title).
- Timeout: no new output for 15 minutes, or over 30 minutes total → kill it
  and treat the task as BLOCKED. A READ run that stalls waiting for an
  approval it cannot get is also BLOCKED: re-brief it to need no tools, or do
  it yourself. Never escalate it to WRITE flags outside a worktree.
- Answers sent on resume follow the same rule: write the answer to
  `.orchestra/briefs/<task-id>-answer<n>.md` and point the worker to it.
- Resume with the same model and effort, using the card's resume command;
  if a CLI cannot resume headless, start a new run whose brief includes the
  previous SUMMARY plus your answer. `sub`: continue the same subagent if
  your tools allow; otherwise re-brief.

## 7. Consult loop
1. Launch independent workers together; record task-id, worker, model, tier,
   effort, profile, session ID, PID, and start time in
   `.orchestra/runs/index.md`.
2. When a worker ends, read its output and find the STATUS block. Missing
   block = treat as BLOCKED ("no status block").
3. On BLOCKED / NEED_DECISION: answer (see section 8 for who decides), then
   resume the same session. Max 2 resumes per task; then apply 3D.
4. On DONE: verify before accepting — run the tests or commands yourself,
   and for WRITE tasks review the worktree diff (`git -C <worktree> diff`).
   Never accept a worker's claim without checking, and never use another
   LLM's opinion as the verification (a panel informs you; it does not
   verify).
5. Accepted WRITE work: merge the task branch into the working branch locally
   (never push), then remove the worktree. Rejected work: remove the worktree
   and branch.

## 8. Modes

### supervised (default)
- Show the worker table (section 1, step 7) and the plan before the first
  launch: `task | worker | model | tier | effort | profile`. Proceed when the
  user agrees; apply any changes they ask for.
- Worker questions that change scope, requirements, or architecture → ask the
  user. Purely technical questions → answer yourself.
- Ask before escalating a task (higher tier or highest effort).

### auto (auto-accept)
You act as orchestrator AND supervisor; the user is not consulted mid-run.
- Do not ask the user anything and do not pause between phases. Do not use
  AskUserQuestion.
- Answer every BLOCKED / NEED_DECISION yourself. Choose the option that is
  most reversible and closest to the original task. Record each decision.
- Escalate and fall back per 3D without asking.
- Accept a result only after your own verification passes. Mark tasks that
  exhaust 3D as FAILED and move on.
- Budget per run: max 10 delegations (escalations and panel members count),
  max 2 resumes each. When the budget is spent, stop and report.
- HARD STOPS — never auto-approved, in any mode. Do the preparatory work, then
  stop and ask (or skip and list it in the report):
  - pushing to any remote, or merging/force-updating main/master
  - deleting files outside `.orchestra/` and the task's own worktree
  - sending messages, emails, posts, or anything leaving this machine
  - spending money, purchases, paid upgrades, paid models or metered providers
  - reading or writing secrets, credentials, `.env`, client/company documents
  - installing packages globally, logging CLIs in, or changing system settings
  - anything you cannot undo with git
- End with one report: what was done, by which worker and model (requested vs
  actual), what you verified, every auto-decision, escalation, and cooldown
  with its reason, anything skipped by a hard stop, and FAILED items.

Auto mode only removes the BRAIN's questions to the user. Claude Code's own
permission prompts (including the prompt before each worker command) are
controlled by Claude Code's permission mode and settings, not by this skill.
If those prompts keep interrupting an auto run, tell the user once that
removing them needs a Claude Code permission mode or allow rules in
settings — do not try to work around prompts.

## 9. Safety (all modes)
- No secrets, credentials, or client/company documents in any brief. Never
  open a CLI's `.env` or credential files, even while probing or onboarding.
- Research workers get the READ profile and "read-only" in CONSTRAINTS.
- WRITE workers run only in their own worktree. Never two workers on the same
  files.
- Gateways that can message people (openclaw, hermes `send`/channels) are
  never used to deliver anything.
- Do not route Claude subscription credentials through third-party gateways
  (e.g. OmniRoute).

## 10. Logging
After each delegated task, append one line to `.orchestra/orchestra-log.md`:
`date | mode | task-kind | worker | requested model | actual model | tier | effort | profile | minutes | resumes | escalated? | accepted as-is / needed rework / discarded / FAILED`

`task-kind` is one of: format, extract, summarize, research, docs, feature,
test, debug, architecture, review — used by 3E.

In auto mode also append each auto-decision and cooldown:
`date | auto-decision | task | question | chosen answer | reason`
`date | cooldown | worker:model | error excerpt`

When the user asks whether orchestration is worth it, or which models work
best, answer from this log, not from assumptions.
