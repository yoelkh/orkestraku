# Worker adapter cards

Read this file during preflight (SKILL.md section 1). Each card says how to run
one CLI headless, safely. Cards marked **verified** were tested end to end
(smoke, READ probe, quoting probe) on the date shown; everything else must be
re-checked against the CLI's `--help` before use. A newer CLI version can
rename or drop flags: when `--help` disagrees with a card, trust `--help`,
say so in one line, and record the difference in the cache.

Placeholders: `<BF>` = absolute path of the brief file, `<P>` = pointer prompt
`Read the brief file <BF> and follow its instructions exactly.`, `<DIR>` =
absolute working directory (project root, scratch copy, or worktree).

---

## Status values

| Status | Meaning | Use it? |
|---|---|---|
| `ready` | Passed smoke, READ probe and quoting probe | Yes, READ and WRITE profiles |
| `write-only` | Passed smoke, but its READ mode still wrote a file (or it has no READ mode) | Only in a worktree or on a scratch copy |
| `web-only` | Safe only with file and shell tools disabled | Web research tasks only |
| `needs-login` | Installed, not signed in | No. Tell the user the exact login command |
| `needs-key` | Needs an API key or provider configuration | No. Tell the user what to configure. Never set it up yourself |
| `unsupported` | The vendor ended the plan or client the user is on | No. Say why |
| `no-headless` | No non-interactive mode found in `--help` | No |
| `broken` | Fails to start (bad install, missing runtime) | No. Give the fix |
| `excluded` | The brain itself, a messaging/automation gateway, or excluded by the user | No, unless the user opts in |

## Error text → status

Classify the first failing smoke run by its output; match case-insensitively.

| Output contains | Status |
|---|---|
| `not logged in`, `/login`, `log in`, `sign in`, `device-code`, `No model configured` | `needs-login` |
| `No auth type`, `API key`, `Invalid API Key`, `No inference provider`, `0 credentials`, `provider not configured` | `needs-key` |
| `no longer supported`, `IneligibleTier`, `service has ended`, `migrate to` | `unsupported` |
| `guardrail restrictions and data policy`, `Free model training violation` | provider privacy block (OpenRouter): `needs-key` for that provider only; other providers of the same CLI may still work |
| `429`, `rate limit`, `quota`, `resource exhausted`, `usage limit` | temporary: cooldown (SKILL.md 3D), not a status |
| `not a valid application`, `postinstall script was not run`, `command not found`, `MODULE_NOT_FOUND` | `broken` |
| `Cannot combine`, `unknown option`, `unexpected argument` | your flags are wrong: re-read `--help`, fix the card, retry once |

---

## Verified cards

### grok · verified 2026-10-10 (grok 1.0.50)
- **Strengths:** web and X search built in, fast (~5 s overhead), strong general model.
- **Cost:** reports `total_cost_usd` per run (~$0.01 for a trivial prompt: ~16k-token system prompt).
- **Login check:** `grok --no-auto-update models` prints `You are logged in`. Login: `grok login`.
- **Models:** `grok --no-auto-update models` (default marked `(default)`).
- **Run:** `grok --no-auto-update -m <model> --effort <low|medium|high|xhigh> --cwd <DIR> --output-format json -s <uuid> --prompt-file <BF> --max-turns 30`
- **READ profile:** no approve flag. Write attempts are cancelled (`stopReason: cancelled`); reading files and web search still work.
- **WRITE profile:** add `--always-approve` (worktree only).
- **Actual model:** keys of `modelUsage`. `grok-4.7` is served as `grok-4.7-build` (same model, not drift).
- **Session / resume:** `-s <uuid>` to start, `-r <uuid> --prompt-file <answer-file>` to resume.
- **Never:** `--yolo`, `--permission-mode bypassPermissions`.

### agy (Antigravity CLI, Gemini) · verified 2026-10-10 (agy 1.3.2)
- **Strengths:** Gemini 3.x long context; also serves Claude and GPT-OSS models (only when the user pins them).
- **Cost:** subscription; ~40–50 s fixed overhead per run.
- **Models:** `agy models`. IDs carry effort as a suffix (`gemini-3.8-flash-high|-medium|-low`): choose the suffix instead of `--effort`. The `gemini` role ranks only `gemini-*` IDs.
- **Run:** `agy -p "<P>" --output-format json --model <model-with-suffix> --add-dir <DIR> --print-timeout 15m`
- **READ profile:** `--mode plan`, **but** if `~/.gemini/antigravity-cli/settings.json` has `"toolPermission": "always-proceed"`, plan mode still writes (verified). Then status = `write-only`.
- **WRITE profile:** `--mode accept-edits` (worktree only).
- **Actual model:** not reported in JSON → log `unreported`. Session: `conversation_id`. Resume: `--conversation <id>`.
- **Never:** `--dangerously-skip-permissions`.

### opencode · verified 2026-10-10 (opencode 1.18.35)
- **Strengths:** many providers in one CLI; free models (OpenCode Zen `opencode/*-free`, OpenRouter `:free`); good for bulk mechanical work.
- **Cost:** free models only (SKILL.md 4c). Cloudflare Workers AI and other metered providers count as paid: do not use unless the user opts in.
- **Login check:** `opencode auth list`.
- **Models:** `opencode models`, `opencode models openrouter`.
- **Run:** `opencode run --format json -m <provider/model> [--variant <lvl>] --dir <DIR> --title <task-id> "<P>"`
- **READ profile:** `--agent plan`. The default `build` agent writes files even without `--auto` (verified).
- **WRITE profile:** `--auto` (worktree only).
- **Actual model / session:** `step_finish` events; session via `opencode session list --format json` by title. Resume: `-s <session-id>`.
- **Known issue:** npm install with skipped postinstall → placeholder `opencode.exe` (479 bytes). Fix: `cd "$env:APPDATA\npm\node_modules\opencode-ai"; node postinstall.mjs`.

### sub (Claude subagent) · verified 2026-10-10
- **Strengths:** critical code, architecture, review; shares the brain's tools.
- **Run:** Agent tool, `subagent_type: general-purpose`, `model: fable|opus|sonnet|haiku`, `effort: low|medium|high`.
- **READ profile:** brief says read-only. **WRITE:** its own worktree.
- **Actual model:** ask it to state its model ID in the report.

---

## Cards checked on 2026-10-10 but not usable on this machine yet

Flags below come from `--help` and a real run that stopped at authentication,
so the READ probe is still pending. Run the full probe once the user has
signed in, then promote the card to verified.

### hermes (Hermes Agent) · 0.19.1 · status seen: `needs-key`
- **Run:** `hermes -z "<P>" -m <model> --provider <provider> --reasoning <none|minimal|low|medium|high|xhigh|max> -t <toolsets> --usage-file <DIR>/.orchestra/runs/<task-id>.usage.json`
- **Danger:** one-shot mode (`-z`) **auto-bypasses approvals**. Default toolsets include `terminal`, `file`, `computer_use`, `cronjob`, `delegation`.
- **READ profile:** `-t web` only → status `web-only` (no project file access). Never enable `terminal`, `file`, `computer_use`, `cronjob`, `browser` outside a worktree.
- **Usage report:** `--usage-file` JSON has `model`, `provider`, `estimated_cost_usd`, `failed`.
- **Setup (user):** `hermes model` or `hermes setup`. Never read `~/.hermes/.env` or `%LOCALAPPDATA%\hermes\.env`.

### qwen (Qwen Code) · 0.21.8 · status seen: `needs-key` ("No auth type is selected")
- **Run:** `qwen -p "<P>" -o json -m <model>` (prompt also accepted on stdin).
- **READ profile (unverified):** `--approval-mode plan` was accepted by the parser. Probe before trusting it.
- **JSON:** result object has `session_id`, `usage`, `permission_denials`, `is_error`.
- **Setup (user):** configure an auth type in Qwen Code settings or pass `--auth-type`; the old free Qwen OAuth login was removed.

### kimi (Kimi Code) · 0.18.0 · status seen: `needs-login` ("No model configured")
- **Run:** `kimi -p "<P>" -m <model> --output-format stream-json`.
- **READ profile:** none headless — `--plan` cannot combine with `--prompt` (verified). Status after login: `write-only` unless a newer version allows it.
- **WRITE profile:** `--auto` (worktree only). **Never:** `-y/--yolo`.
- **Setup (user):** `kimi login`.

### mimo (MiMo Code, opencode-based) · 0.1.10 · status seen: `needs-key` ("MiMo free API service has ended", 0 credentials)
- **Models:** `mimo models` (MiMo v2.5 / v2.6, 1M context).
- **Run:** `mimo run --format json -m <provider/model> --dir <DIR> --title <task-id> "<P>"` (same shape as opencode).
- **READ profile:** `--agent plan` (agent exists; probe pending). **WRITE:** worktree only; **never** `--dangerously-skip-permissions`.
- **Note:** first run performs a one-time database migration (slow).
- **Setup (user):** `mimo providers` to sign in or add an API key.

### gemini (Google Gemini CLI) · 0.55.1 · status seen: `unsupported`
- Free "Gemini Code Assist for individuals" is no longer accepted by this client ("migrate to Antigravity"). Use `agy` for Gemini. With a paid Gemini API key it would work, but that is spending money: only on explicit user opt-in.
- **If enabled:** `gemini -p "<P>" -o json -m <model> --approval-mode plan --skip-trust` (READ) / `--approval-mode auto_edit` (WRITE, worktree). **Never:** `-y/--yolo`, `--approval-mode yolo`.

### openclaw · 2026.9.4 · status: `excluded` (gateway)
- Personal-assistant gateway with chat channels (Telegram, WhatsApp, …) that can send messages off the machine. Not used as a worker unless the user opts in, and then only `openclaw agent --local` with no channel delivery.

### claude · status: `excluded` (brain)
- The brain is this session. Never run `claude -p` as a worker; use `sub`.

---

## Onboarding an unknown CLI (no card)

1. Read `<cli> --help` and the help of any `run` / `exec` / `chat` subcommand.
2. Draft a card: headless prompt flag, how to pass the brief (prompt file >
   stdin > one-line pointer prompt), working-directory flag, model flag and
   model-list command, effort flag, JSON output and where it reports model /
   session / cost, a read-only or plan mode, a scoped auto-edit mode.
3. Run the **probe** (below). Classify with the error table.
4. Record the draft card and result in the cache. Use it only if `ready`,
   `write-only` (worktree/scratch), or `web-only`.
5. Flags that approve everything (`yolo`, `dangerously-*`, `bypass*`,
   `skip-permissions`, `--never-ask`) are never used, in any profile.

## The probe (run in a scratch folder, never in the project)

Create `<scratch>/<worker>/note.txt` containing `The secret word is PELANGI.`
and `<scratch>/<worker>/brief.md`:

```
Do these steps in order:
1. Read the file note.txt in the current directory and find the secret word.
2. Try to create a file named probe.txt containing the word hello. If you are not allowed to, skip it and say so.
3. Reply with exactly three lines:
SECRET: <the secret word>
WROTE: yes or no
QUOTE: "a & b | c > d"
```

Run the worker with its READ profile, `<DIR>` = that folder, prompt passed the
way its card says. Pass when: `SECRET: PELANGI` (it can read), `probe.txt`
does NOT exist (READ is safe), and the QUOTE line arrives intact with its
double quotes (brief passing is safe). Record latency. A worker that passes
everything except the write check is `write-only`.
