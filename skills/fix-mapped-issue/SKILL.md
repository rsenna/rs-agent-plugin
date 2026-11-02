---
name: fix-mapped-issue
description: Implement the tasks mapped from a GitHub issue, ship each through the pull-request process, and close the issue once everything is merged. Use when asked to fix/work/implement/resolve a GitHub issue that already has a task breakdown (tasks/issue-<n>-*.md). Runs after map-issue-to-tasks.
---

# Fix Mapped Issue

Steps 4–6 of the issue lifecycle: **implement the mapped tasks, ship them via the
pull-request process, then update and close the issue.** Assumes
`map-issue-to-tasks` already produced `tasks/issue-<n>-<slug>.md`. If that file
doesn't exist, run `map-issue-to-tasks` first.

Reuses the sibling skills' scripts (this plugin's other skills, installed as
siblings of this one under the same skills root — resolve these relative to
wherever this `fix-mapped-issue` skill itself was loaded from):
- `../pull-request-process/pr.sh` (branch/push/PR/threads)
- `../map-issue-to-tasks/issue.sh` (`close` for the final comment)

## Portability — read the project's specifics first
From the project's `AGENTS.md`: the **base branch** and the
**quality gate command + coverage bar** (e.g. `what-about`:
`mix precommit --cover`, ≥ 90% — see AGENTS.md:23–30). Pass the base branch as
`BASE=` to `pr.sh`.

## Do this (per task, until the issue is done)

0. **Preflight label gate (required).** Before executing tasks for issue `<n>`,
   verify labels via `issue.sh fetch <n>` (or `issue.sh json <n>`): proceed only
   when `mapped` is present and `must-remap` is absent. If `must-remap` is set,
   stop and run `map-issue-to-tasks` first to regenerate mapping and clear it.
1. **Pick the next task** from `tasks/issue-<n>-*.md`: the next unchecked box,
   respecting dependency order. If the file predates the checkbox convention
   (any heading with no leading `- [ ]`/`- [x]`), retrofit a checkbox onto
   **every** heading before picking — `- [x]` for tasks the file already notes
   as done/merged, `- [ ]` for the rest — so the "next unchecked box" rule has
   something to operate on. If it's a 🔒 ask-first gate (new dependency, DB
   migration, CI/secret change), **pause and get explicit approval** before starting.
2. **Implement** via the `incremental-implementation` and
   `test-driven-development` skills. New or changed behaviour **must be described
   by tests** (behaviour-asserting, not coverage-padding).
3. **Ship it via the `pull-request-process` skill** — one task ≈ one PR:
   `pr.sh start` (then `cd` into the worktree path it prints) → implement/commit
   → run the gate → run `pull-request-process` step 3's exact
   `requesting-code-review` pass and fix what it flags
   → **re-run the gate if any code changed** → `REVIEWED=1 pr.sh push` → `pr.sh open` → **STOP** (never merge). Then
   handle review threads per that skill.
4. **After the maintainer/bots merge**, tick the task's checkbox in
   `tasks/issue-<n>-*.md` (`- [ ]` → `- [x]`) and append the merged PR link to
   that task's heading line in exactly this form: `— ✅ merged (#<n>)` — a
   fixed syntax so later automation can parse it reliably. If a task shipped
   across more than one PR, list every merged PR in that same parenthetical,
   in merge order, comma-separated (`— ✅ merged (#9, #12)`); never drop an
   earlier PR link when a later one for the same task lands. This edit is
   itself a change to a tracked file, so commit and ship it through the same
   `pull-request-process` flow as any other change — never push it straight to
   the base branch. Either give it its own small PR or fold it into the next
   task's branch if you're about to start that task anyway. Then move to the
   next task. Repeat until every task is merged.

## Close it (step 6)

Once **all** tasks are merged:
1. Write a **solution comment**: what shipped, and links to the merged PRs.
2. `issue.sh close <n> <solution.md>` — posts the comment and closes the issue.
   (`DRY_RUN=1` previews without posting/closing.)

```bash
P=<this-skill's-own-directory>/../pull-request-process/pr.sh   # e.g. ~/.claude/skills/fix-mapped-issue/../pull-request-process/pr.sh,
                                                                 # or ~/.agents/skills/fix-mapped-issue/../pull-request-process/pr.sh —
                                                                 # wherever your installer put this plugin's skills, as siblings
I=<this-skill's-own-directory>/../map-issue-to-tasks/issue.sh
BASE=main "$P" start fix/issue-24-notify
cd <printed-worktree-path>
# …implement + test…  then run the project gate…
BASE=main REVIEWED=1 "$P" push fix/issue-24-notify   # after a requesting-code-review pass and fixes
BASE=main "$P" open "feat: notify on (re)publish (#24)" pr-body.md   # then STOP
# …after all tasks merged…
DRY_RUN=1 "$I" close 24 solution.md      # preview
"$I" close 24 solution.md                # post solution + close
```

## Guardrails (never violate)

- Never merge a PR, never mark it ready — bots/maintainer do that.
- Never resolve review threads — reply per thread; the maintainer resolves.
- Never close the issue until **every** mapped task is merged.
- Never push unless the project's quality gate is green.
- Never push without running a `requesting-code-review` pass first and
  addressing what it flags (enforced by `pr.sh push` requiring `REVIEWED=1`).

## Close-out comment template

After every task merged, draft this before handing off:

```
# Summary
- (what shipped)

# PRs merged
- #<n>

# Follow-ups
- (next steps or “none”)
```
