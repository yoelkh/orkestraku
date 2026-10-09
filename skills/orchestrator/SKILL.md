---
name: orchestrator
description: Run this session as the BRAIN that delegates independent work to user-chosen workers — local CLIs (grok, agy/Gemini, opencode) called directly from the shell, or Claude subagents — choosing the model and effort per task, in supervised or auto-accept mode. No third-party bridge. Use on /orchestrator, "delegasikan", "pakai worker", or when splitting a task across agents.
allowed-tools: Agent Read Grep Glob
---

# Orchestrator

You are the BRAIN: you plan, decide, supervise, and verify. Workers do the bulk
work. You call worker CLIs yourself with your shell tool — no MCP bridge, no
wrapper package. The brain is this interactive session only — never run
`claude -p` as a worker; use native subagents (`sub`) for Claude workers.

Invocation arguments: $ARGUMENTS

## 0. Parse the invocation
Syntax:
`/orchestrator [workers=<list>] [tier=best|fast|standard|strong] [effort=auto|low|medium|high] [mode=supervised|auto] <task>`

- `workers=` comma-separated roster. Each entry is `name`, `name:model`, or
  `name:tier`. Names: `grok`, `gemini` (Antigravity CLI `agy`), `opencode`,
  `sub` (Claude subagent).
  - `name:model` pins that worker to one exact model for every task
    (`gemini:gemini-3.8-flash`, `sub:opus`).
  - `name:tier` pins only the tier and lets you pick the model in it
    (`gemini:fast`, `sub:strong`).
  - A partial name (`gemini:flash`, `gemini:pro`) is resolved against the
    model catalog (section 1). One match → use it; several → take the newest
    in the matching tier and show the resolution in the setup line; none →
    treat as not available.
  - `workers=ask` → show the workers and catalog models that passed preflight
    with AskUserQuestion (multiSelect). In mode=auto, skip and use defaults.
  - No `workers=` → every worker that passes preflight.
- `tier=` global model policy. Default `best`: every task gets the newest,
  best model each worker offers (section 3B). `fast` / `standard` / `strong`
  are opt-in downgrades or pins the user sets.
- `effort=` global default reasoning effort. Default `auto` (section 3).
- `mode=` defaults to `supervised`. Anything else is the task.

Echo the resolved setup in one line before working, e.g.
`Roster: grok→<best slug>, gemini→<best slug>, opencode→<best free slug>, sub→fable · Tier: best · Effort: auto · Mode: auto · Brain: <session model> · Shell: PowerShell`.

The user can change roster, tier, effort, or a single task's model mid-session
in plain language ("T2 pakai gemini pro", "semua pakai fast", "naikkan
effort", "mode auto"). Apply it from the next launch and echo the new setup.

## 1. Preflight (once per session)
1. **Brain check.** Note your own session model. If it is not an Opus- or
   Fable-class model, warn once that brain decisions will be weaker and
   suggest `/model opus` (or `/model fable`, which has a limited quota). You
   cannot change the brain model yourself.
2. **Shell.** Detect the shell (PowerShell on native Windows, bash elsewhere)
   and use the matching templates in section 6.
3. **CLI check.** For each roster CLI run its version and help once:
   `grok --no-auto-update --version`, `agy --version`, `opencode --version`,
   then `grok --help`, `agy --help`, `opencode run --help`. Confirm every flag
   used in sections 3 and 6 exists, including each CLI's effort flag
   (`grok --effort`, `agy --effort`, `opencode --variant`) and the levels it
   accepts. If a flag is missing or renamed, adapt to `--help` and say so in
   one line. Never guess a flag or an effort level. Known levels (re-verify):
   grok `low|medium|high|xhigh` (an invalid level prints the valid list);
   agy `low|medium|high|xhigh|max`; opencode `--variant` is provider-specific.
   - **Login check:** `grok --no-auto-update models` prints `You are logged in`
     when signed in; otherwise the user must run `grok login` themselves. For
     opencode run `opencode auth list` to see which providers have keys.
   - **Broken npm shim (Windows):** if `opencode --version` fails with "not a
     valid application" or prints "postinstall script was not run", the npm
     postinstall was skipped. Tell the user to run
     `cd "$env:APPDATA\npm\node_modules\opencode-ai"; node postinstall.mjs`
     (never run it yourself — it modifies a global install). Until fixed, you
     may call the platform binary directly for this session:
     `$env:APPDATA\npm\node_modules\opencode-ai\node_modules\opencode-windows-x64\bin\opencode.exe`.
4. **Model catalog — rebuilt every session, never from memory.** Model
   lineups change monthly; your own knowledge of model names is stale. List
   models only from the live source of truth:
   - grok: `grok --no-auto-update models`
   - gemini: `agy models` (add `--output-format json` if supported). agy
     model IDs carry the effort level as a suffix
     (`gemini-3.8-flash-high|-medium|-low`): treat the suffix as effort, not
     as a separate model, and pick the suffix from Step C instead of passing
     `--effort`. agy also lists non-Gemini models (Claude, GPT-OSS); the
     `gemini` worker ranks only `gemini-*` models — others are used only when
     the user pins them by name.
   - opencode: `opencode models` (and `opencode models openrouter` for
     OpenRouter). For OpenRouter free models also read the public catalog
     `https://openrouter.ai/api/v1/models` (no key needed) to get each
     model's `created` date, `context_length`, `pricing`, and
     `supported_parameters`. If that request fails, rank from the opencode
     list alone and say so.
     Also list opencode's own free models (`opencode/*-free`, OpenCode Zen):
     they need no OpenRouter key and are a valid free fallback.
   - sub: aliases `fable`, `opus`, `sonnet`, `haiku` (or full IDs).
   Write `.orchestra/models.md` as
   `worker | model | version | variant | tier | status | selected-as` with
   today's date at the top, then apply the ranking rules in 4a to pick each
   worker's **best** model and its **fast** fallback.

4a. **Ranking rules (pick the newest, best model per worker).**
   1. **Version first.** Parse the version number in each model ID and rank
      the highest version first (4.7 > 4.5 > 4; 3.8 > 3.1). A higher version
      always beats a lower one, regardless of size. Compare versions only
      within one model family — never across vendors (Claude 5.5 vs Gemini
      3.8 is not comparable).
   2. **Variant second, within the same version:** ultra / opus / pro /
      max / heavy (flagship) > unsuffixed base > fast / flash / mini / lite /
      nano / haiku. A "fast" variant that is the same model served faster
      (e.g. a `-fast` sibling of the flagship) ranks just below its flagship.
   3. **Status third:** GA/stable > preview > experimental at the same
      version and variant. A preview of a HIGHER version still beats an older
      GA model, but only after it passes the smoke test in step 4b.
   4. **Ignore** deprecated, legacy, embedding, image-only, audio-only, and
      routing/alias entries (e.g. `openrouter/free`, `auto`) when ranking.
   5. **Tier labels for the catalog:** flagship variants of the newest
      version = strong; base = standard; fast/flash/mini/lite = fast.
   6. If two models still tie, prefer the one the CLI marks as default.
      If version or variant cannot be parsed, mark the row `rank guessed`
      and rank it below every parsed model.

4b. **Smoke test the selected models.** For each worker's selected best
   model, run one tiny READ-profile prompt (e.g. `Reply with OK.`). If it
   fails (no access on the plan, model unavailable, quota), pick the next
   model in the ranking and test again, up to 3 tries per worker. Record the
   result in `models.md`.

4c. **OpenRouter free models (opencode).**
   - Only models whose prompt AND completion price are 0 (IDs ending in
     `:free`). NEVER select a paid OpenRouter model — that is spending money
     (hard stop).
   - Required: `supported_parameters` includes `tools`, because opencode
     needs tool calling. Drop models without it.
   - Drop special-purpose models (safety/guard/content-moderation, roleplay,
     OCR, vision-only) and, for the `best` pick, small variants
     (mini/nano/small/lite/xs/lightning, or under ~20B parameters) — those
     only qualify as the `fast` pick. Otherwise the newest model is often a
     tiny one.
   - Rank the remaining free models: newest `created` date first, then
     flagship family/size per 4a.2, then larger `context_length`.
   - An error containing "guardrail restrictions and data policy" or
     "Free model training violation" means the user's OpenRouter privacy
     settings block ALL free models. Do not cycle through the chain; tell the
     user (they can allow it at openrouter.ai/settings/privacy — their
     decision, never yours) and fall back to OpenCode Zen free models.
   - Keep the top 3 as a fallback chain. Free models are rate-limited often:
     on a rate-limit error, move to the next one (section 3D). Use
     `openrouter/free` only as the last resort and log the model it actually
     routed to.
   - If opencode has no OpenRouter key configured, say so; never set one up
     yourself.

4d. Show the catalog's selected models to the user in supervised mode before
   the first launch, and always in the setup line.
5. **Subagent override check.** If the environment variable
   `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set, every `sub` worker runs on one
   forced model regardless of your choice — say so and treat `sub` as a
   single fixed model.
6. A CLI that is not installed or not logged in fails preflight. Never
   install or log in anything yourself, in any mode — tell the user. If no
   external CLI passes, continue with `sub` only (normal in Cowork and cloud
   sessions).
7. Create `.orchestra/` with `briefs/`, `runs/`, `models.md`, and
   `orchestra-log.md`. Add `.orchestra/` to `.gitignore` if the project uses
   git. If the project is NOT a git repo, the WRITE profile is unavailable
   (no worktrees): in supervised mode suggest `git init`; until then, keep
   all file-changing work for yourself or `sub`.
8. **Permission audit (READ safety).** A CLI's global config can silently
   override per-run read-only flags. Check once per session:
   - agy: read `~/.gemini/antigravity-cli/settings.json`. If `toolPermission`
     is `always-proceed` (or similar), `--mode plan` does NOT stop writes —
     agy plans and then executes. Mark agy `READ-unsafe`: give it READ tasks
     only with a scratch copy of the inputs (outside the project) as its
     workspace, or inside a worktree. Tell the user once; never edit the
     config yourself.
   - opencode: the default `build` agent allows all edits even without
     `--auto`; READ runs must use `--agent plan`.
   - grok: without `--always-approve`, headless runs cancel write attempts
     (`stopReason: cancelled`) but can still read files and search the web.

## 2. When to delegate (all three must be true, otherwise do it yourself)
1. The task is independent: it does not need files another worker is editing.
2. You can brief it in 5 sentences or less, with a clear definition of done.
3. The result can be verified by a test, a command, or a short checklist.

Small tasks (under ~15 minutes of your own work) are never delegated.
Interdependent coding tasks are usually a net loss — keep them yourself.
Parallel read-only research is the clearest win.

## 3. Choosing worker, model, and effort per task

### Step A — worker (within the active roster)
| Work type | Preferred worker |
|---|---|
| Web/X research, current events, second opinion | grok |
| Large repos or long documents, summaries, docs drafting | gemini |
| Mechanical edits: boilerplate, renames, simple tests, formatting | opencode |
| Critical code, architecture-sensitive changes, code review | sub |

If the preferred worker is not in the roster, use the next best one in the
roster; if none fits, do it yourself. Max 3–5 concurrent workers.

### Step B — model (policy `best` by default)
- **`tier=best` (default):** every task uses the worker's `selected-as: best`
  model from `.orchestra/models.md` — the newest, highest-ranked model that
  passed the smoke test (section 1, steps 4a–4b). For opencode that is the top-ranked free
  OpenRouter model (section 1, step 4c), or the top model of whichever provider opencode
  is configured with.
- **`sub` under `best`:** `fable` if available on the user's plan, else
  `opus`; subject to the Claude quota guard in 3D.
- **`tier=fast|standard|strong`** (only when the user sets it, globally, per
  worker, or per task): take the highest-ranked model of that tier for that
  worker. If the worker has no model in that tier, use the nearest tier and
  note it.

### Step C — effort
Effort is chosen per task even under `best`:
| Task | Effort |
|---|---|
| Formatting, renames, boilerplate, extracting facts, summarizing short text | low |
| Normal research, reading docs, standard features, tests | medium |
| Architecture, hard debugging, security-sensitive code, final review, synthesis across many sources | high |

Map low/medium/high to the levels the CLI's `--help` shows; if a CLI has no
effort flag, omit it. For `sub`, pass the Agent tool's `model` and `effort`
parameters and use a general-purpose subagent so the model parameter
applies. A global `effort=` overrides this table.

### Precedence (highest first)
1. A per-task instruction from the user ("T2 pakai gemini pro").
2. A `name:model` pin in the roster.
3. A `name:tier` pin in the roster.
4. The global `tier=` / `effort=` values.
5. The default policy `best` (Steps B–C).

### 3D. Escalation and fallback
- **Escalation:** if a task ends BLOCKED twice, fails verification, or needs
  rework, retry it ONCE with a fresh brief that includes what went wrong:
  on a lower tier → one tier higher; already on `best` → same model at the
  highest effort level. If it still fails, reassign to another worker or
  take it over. Escalation never overrides a `name:model` pin — with a pin,
  reassign instead.
- **Quota / rate limit:** if a run's output or `.err` shows a rate limit,
  quota, "429", "resource exhausted", or usage-limit error, mark that
  worker:model as cooled down for the rest of the run, and relaunch on the
  next model in that worker's ranking (for OpenRouter free: the next model of
  the top-3 chain, then `openrouter/free`), else on another worker. Do not
  retry a cooled-down model in the same run. Report every cooldown and the
  model it fell back to.
- **Claude quota guard:** at most 2 `sub` workers on `fable` per run, then
  `opus`, unless the user raises the limit. Fable usage counts against a
  limited weekly quota.
- **Model drift:** if a worker's selected model disappears mid-session or a
  newer one appears in its `models` output, re-run section 1 steps 4a–4b for that worker
  before its next launch.

### 3E. Learning from the log
Before each choice, read `.orchestra/orchestra-log.md`. If a worker:model has
5 or more entries for this kind of task and fewer than half are "accepted
as-is", prefer the next option and say why in one line. Under `tier=best`,
never downgrade to a cheaper model on your own; you may only suggest it to
the user with the log numbers.

### 3F. Confirm the model actually used
After each run, read the model reported in the CLI's JSON output when present
and log THAT model. If it differs from the requested one, say so and log both.
Where each CLI reports it: grok → keys of `modelUsage` (a `-build` suffix,
e.g. `grok-4.7` → `grok-4.7-build`, is grok's serving name for the same
model, not drift); agy → not reported in JSON, log `unreported`; opencode →
the `step_finish` / message events when present, else `unreported`;
sub → ask the subagent to state its model ID in the report.

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
- **READ** (research, summaries, review): no auto-approve flag. Working
  directory = the project root or the folder to read.
- **WRITE** (code or file changes): only inside a dedicated git worktree
  created for that task (`git worktree add .orchestra/wt/<task-id> -b orch/<task-id>`).
  Auto-approve flags are allowed ONLY with the worktree as working directory.

| Worker | READ profile | WRITE profile (worktree only) |
|---|---|---|
| grok | (no approve flag) `--max-turns 30` | `--always-approve --max-turns 30` |
| agy | `--mode plan` (+ scratch/worktree workspace if `READ-unsafe`, see 1.8) | `--mode accept-edits` |
| opencode | `--agent plan` (no `--auto`) | `--auto` |

**After every READ run, verify nothing changed:** compare `git status
--porcelain` (or, without git, a file list with sizes/timestamps taken
before launch) with the state before the run. Any change → discard it,
log the worker as READ-unsafe for the session, and tell the user.

grok also offers `--deny <RULE>`, `--permission-mode plan`, and `--sandbox
<PROFILE>`; use them for READ runs only after confirming their exact syntax
in grok's docs — never guess a rule format. NEVER pass
`agy --dangerously-skip-permissions`, `grok --yolo`, or set any CLI's config to
always-approve globally. Never point a worker's working directory outside the
project or its worktrees.

## 6. Launching workers (direct CLI)
**Never pass the brief text itself as a command-line argument.** Windows
PowerShell 5.1 strips embedded double quotes from native-command arguments
(`"q"` arrives as `q`), and long multi-line argv is fragile in every shell.
Instead: grok reads the file via `--prompt-file`; agy and opencode get a
one-line pointer prompt that tells them to read the brief file (verified to
preserve quotes and special characters). Use absolute paths. Write stdout to
`.orchestra/runs/<task-id>.out` and stderr to `.orchestra/runs/<task-id>.err`.
Run every worker with your shell tool's background option so workers run in
parallel; read the output files when each process ends.

bash:
```bash
BF=<abs>/.orchestra/briefs/T1.md
P="Read the brief file $BF and follow its instructions exactly."
grok --no-auto-update -m <model> [--effort <lvl>] --cwd <abs-dir> --output-format json -s <uuid> --prompt-file "$BF" [profile flags]
agy -p "$P" --output-format json --model <model-with-effort-suffix> --add-dir <abs-dir> --print-timeout 15m [profile flags]
opencode run --format json -m <provider/model> [--variant <lvl>] --dir <abs-dir> --title T1 [profile flags] "$P"
```

PowerShell:
```powershell
$BF = "<abs>\.orchestra\briefs\T1.md"
$P  = "Read the brief file $BF and follow its instructions exactly."
grok --no-auto-update -m <model> [--effort <lvl>] --cwd <abs-dir> --output-format json -s <uuid> --prompt-file $BF [profile flags]
agy -p $P --output-format json --model <model-with-effort-suffix> --add-dir <abs-dir> --print-timeout 15m [profile flags]
opencode run --format json -m <provider/model> [--variant <lvl>] --dir <abs-dir> --title T1 [profile flags] $P
```

Answers sent on resume follow the same rule: write the answer to
`.orchestra/briefs/<task-id>-answer<n>.md` and point the worker to it.

Observed costs (re-measure; for planning only): agy has ~40–50 s fixed
overhead per run, opencode Zen ~20 s, grok ~5 s. grok reports
`total_cost_usd` per run (~$0.01 for a trivial prompt, because of a ~16k-token
system prompt) — sum it in the final report.

- grok: always pass `--no-auto-update`. Generate a fresh UUID per task for
  `-s` (`uuidgen` / `[guid]::NewGuid()`) and record it.
- agy: record `conversation_id` from the JSON output.
- opencode: get the session ID from `opencode session list --format json`
  by the `--title` you set.
- Timeout: if a worker produces no new output for 15 minutes or exceeds 30
  minutes total, kill it and treat the task as BLOCKED. A READ run that
  stalls waiting for an approval it cannot get is also BLOCKED: re-brief it
  to need no tools, or do it yourself. Never escalate it to WRITE flags
  outside a worktree.

### Resuming a worker
Resume with the same model and effort as the original run.
- grok: `grok --no-auto-update -r <uuid> --prompt-file <answer-file> [same flags]`
- agy: `agy -p "<pointer to answer-file>" --conversation <conversation_id> [same flags]` — if
  `--help` shows this cannot combine with `-p`, start a new run whose brief
  includes the previous SUMMARY plus your answer.
- opencode: `opencode run -s <session-id> [same flags] "<pointer to answer-file>"`
- sub: continue the same subagent if your tools allow; otherwise re-brief.

## 7. Consult loop
1. Launch independent workers together; record task-id, worker, model, tier,
   effort, profile, session/conversation ID, PID, and start time in
   `.orchestra/runs/index.md`.
2. When a worker ends, read its output and find the STATUS block. Missing
   block = treat as BLOCKED ("no status block").
3. On BLOCKED / NEED_DECISION: answer (see section 8 for who decides), then
   resume the same session. Max 2 resumes per task; then apply 3D.
4. On DONE: verify before accepting — run the tests or commands yourself,
   and for WRITE tasks review the worktree diff (`git -C <worktree> diff`).
   Never accept a worker's claim without checking, and never use another
   LLM's opinion as the verification.
5. Accepted WRITE work: merge the task branch into the working branch locally
   (never push), then remove the worktree. Rejected work: remove the worktree
   and branch.

## 8. Modes

### supervised (default)
- Show the plan before the first launch as a table:
  `task | worker | model | tier | effort | profile`. Proceed when the user
  agrees; apply any model changes they ask for.
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
- Budget per run: max 10 delegations (escalations count), max 2 resumes each.
  When the budget is spent, stop and report.
- HARD STOPS — never auto-approved, in any mode. Do the preparatory work, then
  stop and ask (or skip and list it in the report):
  - pushing to any remote, or merging/force-updating main/master
  - deleting files outside `.orchestra/` and the task's own worktree
  - sending messages, emails, posts, or anything leaving this machine
  - spending money, purchases, paid upgrades
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
- No secrets, credentials, or client/company documents in any brief.
- Research workers get the READ profile and "read-only" in CONSTRAINTS.
- WRITE workers run only in their own worktree. Never two workers on the same
  files.
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
