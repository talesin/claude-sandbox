# Sandbox Rules

## Prohibited Actions
- Do not run `git push` or any command that pushes to a remote
- Do not switch or create git branches
- Do not run `git commit` without explicit user confirmation
- Do not install system packages with apt/brew
- Do not make outbound network requests except to the Anthropic API
- Do not use `git fetch`, `git pull`, or `git clone` (blocked by git-wrapper)
- Do not use `git reset --hard` or `git clean -f` (both blocked)

## Git File Operations

The git wrapper blocks branch switching. To restore files, use the explicit `--` separator:

- Restore from index:          `git checkout -- <file>`
- Restore from HEAD:           `git checkout HEAD -- <file>`
- Restore from another ref:    `git checkout <branch-or-commit> -- <file>`
- Restore to working tree:     `git restore <file>`
- Restore from another ref:    `git restore --source=<ref> <file>`

Do NOT use `git checkout <name>` without `--` — it will be blocked as an ambiguous branch switch.

## Git Write Operations

The environment variable `GIT_WRITES_ENABLED` controls whether the main `.git` directory is writable.

**When `GIT_WRITES_ENABLED=0` (default — read-only git):**
- Read-only operations work: `git status`, `git diff`, `git log`, `git show`
- File restores work: `git checkout -- <file>`, `git restore <file>`
- These fail (need writes to .git): `git add`, `git commit`, `git checkout --theirs`, `git checkout --ours`, `git merge`, `git rebase`

**When `GIT_WRITES_ENABLED=1` (launched with `--allow-git-writes`):**
- All of the above work
- `git push` and branch switching are still blocked by the wrapper

If you need to stage, commit, or resolve merge conflicts, ask the user to relaunch the sandbox with:
```
./claude-sandbox.sh --allow-git-writes
```

## Available Claude Code Flags

The sandbox is launched with `claude --dangerously-skip-permissions` by default. Useful flags the user can pass at launch:

- `--allow-git-writes` — enables git add/commit inside the container
- `--with-skills` — mounts the user's `~/.claude/skills/` read-only into the container
- `--safe` — removes `--dangerously-skip-permissions`; permissions prompts become active
- `-n "name"` — sets a display name for this session
- `--bare -p "prompt"` — non-interactive headless mode; skips hooks/plugins/skill walks
- `--from-pr <number>` — pre-loads a GitHub PR's diff into context

## Orchestration & Model Strategy

**Delegate to keep context lean.** Offload fan-out search/exploration to subagents (or the `Explore` agent type) — they return conclusions, not file dumps. Delegate when scope is uncertain or spans many files; read directly when it's a single known file or fact. Run independent agents in parallel (one message, multiple calls).

**Model** — set `model` on each Agent call based on task complexity:

- `haiku` — trivial: file lookups, grep/glob, single-fact extraction, mechanical reads
- `sonnet` — most work: research, code review, unit tests, docs, routine planning
- `opus` — deep reasoning: multi-file refactors, hard debugging, architectural design, high-stakes review

Opus costs several× sonnet — reserve it for reasoning, not volume.

**Reserve workflows** for work that genuinely fans out (broad audit/review, multi-file migration, multi-source research). They're opt-in and high-overhead — a single agent or pipeline beats them for linear work.

When launched with `--with-skills`, the `agent-orchestration` skill has the full playbook.

## tmux

Use tmux for any process that would otherwise block the agent loop or needs to outlive a single tool call: dev servers, file watchers, `tail -f`, long builds, REPLs (`python3`, `node`, `psql`), and multi-step interactive CLIs.

**Core pattern:**

```bash
# Start detached
tmux new-session -d -s <name> '<command>'

# Inspect output (last 200 lines; omit -S for current screen only)
tmux capture-pane -p -t <name> -S -200

# Send input to a running session
tmux send-keys -t <name> '<text>' Enter

# List sessions / clean up
tmux ls
tmux kill-session -t <name>
```

**Pick descriptive session names** (`devserver`, `pytest-watch`, `pyrepl`) so multiple concurrent sessions stay legible.

**Don't use tmux for one-shot commands.** For `npm test` or `ls`, plain Bash is fine. Tmux is for things that would otherwise hang the conversation or need to outlive a single tool call.

**Persistence caveat:** the container runs with `docker run --rm`, so the tmux server dies when the Claude session ends. Tmux is for *in-session* concurrency, not for resuming work across sandbox launches.

## Tooling

The following CLIs are baked into the image — prefer them over reimplementing:

| Tool | Binary name | Notes |
|---|---|---|
| ripgrep | `rg` | fast recursive grep |
| fd-find | `fdfind` | `fd` is a different package; use `fdfind` |
| bat | `batcat` | `bat` is a different package; use `batcat` |
| jq | `jq` | JSON processing |
| yq | `yq` | YAML/JSON processing |
| fzf | `fzf` | fuzzy finder |
| tree | `tree` | directory listing |
| GitHub CLI | `gh` | GitHub API and PR workflow |
| GNU parallel | `parallel` | run commands in parallel |
| entr | `entr` | run commands on file change |
| sqlite3 | `sqlite3` | embedded SQL |
| make | `make` | build automation |
| tmux | `tmux` | terminal multiplexer (see section above) |
| Node 22 + Playwright | `node`, `npx playwright` | Chromium bundled |

## Notes on Effort and Models

- `/model` switches between the tiers available in this build (Opus / Sonnet / Haiku)
- `/effort` sets `low`, `medium`, `high`, or `xhigh` (xhigh requires the top Opus tier)
- The binary auto-updates in place, so the exact command set may shift between sessions; use `/help` if something seems missing

## Memory

Auto-memory is stored at `/home/claude/.claude/memory/` and persists across sessions in the
`claude-sandbox-config` named volume. Memory accumulates across sessions automatically.

## References

Curated reference docs are mounted read-only at `/references` (also available as `$REFERENCES`):

1. `ls /references` to see available technologies.
2. Read `/references/{tech}/index.md` first for task-based navigation, then specific chapters.
