---
name: pull-request-process
description: Open a pull request the safe way and handle review comments on it. Use when creating a branch, pushing work, opening a PR, or working through bot/human review threads. Encodes branch hygiene, an explicit-refspec push that can't accidentally advance main, "open the PR but never merge — bots/maintainer review," and the per-thread review-reply loop.
---

# Pull Request Process

The repeatable, safe way to ship a change: branch (in its own git worktree,
never the shared checkout) → run the project's quality gate → push without
ever touching `main` → open a PR → **stop** (never merge) → work each review
thread. This is a **building block** other skills call (`fix-mapped-issue`
follows it for "till the issue is fixed").

The git/gh plumbing is in **`pr.sh`**, next to this file — whatever directory
this `SKILL.md` was loaded from, `pr.sh` is a sibling in that same directory.
Resolve it there rather than assuming a fixed install root: different
installers place skills differently (e.g. `~/.claude/skills/pull-request-process/`,
`~/.agents/skills/pull-request-process/`, or a project-local
`.agents/skills/pull-request-process/`).
`pr.sh` is language-agnostic and **does not run the project's quality gate** — run the gate yourself per the project's `AGENTS.md` before calling `pr.sh push`.
## Agent identity, not the personal one

Every `gh` call and every commit `pr.sh` makes uses a dedicated agent
identity (`GHUB_AGENT_PATC`/`GHUB_AGENT_USERNAME`/`GHUB_AGENT_EMAIL`,
sourced fresh from Doppler on every invocation — see `pr.sh`'s own header
comment for the env vars that control which Doppler project/config), never
whatever personal `gh auth` account or global git identity happens to be
ambient. This isn't optional or best-effort: every subcommand dies loudly if
those secrets aren't reachable, rather than silently falling back to the
ambient identity — that silent fallback is exactly what leaked a personal
GitHub account into commits and PR comments before this existed. Commit
identity is scoped to just the task's own worktree (via git's
`--worktree`-level config), so it never touches the shared checkout's own
identity.

**Never call `gh` directly for anything PR-related** (`gh pr comment`,
`gh pr create`, `gh api .../comments`, etc.) — even for one-off actions that
feel too small to bother with `pr.sh`. A direct `gh` call rides whatever
`gh auth` happens to be ambient (your personal account, if you're logged in
locally), silently reintroducing the exact leak this identity enforcement exists to
prevent. Every PR interaction has a `pr.sh` subcommand: opening (`open`), a
general/top-level comment (`comment`), correcting one (`comment-delete`), a
threaded reply (`reply`), reading review state (`threads`, `reviews`, `checks`). If a
PR action you need has no subcommand yet, that's a gap in `pr.sh` to fix —
add the subcommand rather than reaching for raw `gh`.

## Worktrees, not the shared checkout

`pr.sh start` creates every task's branch in its **own git worktree** — under
a centralized directory (`~/.local/share/copilot-worktrees/<repo-name>/<branch>`
by default; override with `PR_WORKTREE_ROOT=<dir>`) — rather than switching
branches in place inside whatever checkout you started from. This matters
because that shared checkout often has its own uncommitted, unrelated work
sitting in it (the user's own in-progress edits, a previous task's leftovers)
— switching branches in place forces a stash/pop dance around that every
single time, and risks mixing it into the wrong commit. A fresh worktree
sidesteps this entirely: it's created straight from `origin/<BASE>`, so the
shared checkout's working directory is never touched, never needs stashing,
and can't collide with the task branch's own changes.

The centralized location means agent-created worktrees never appear alongside
personal repo checkouts (e.g. inside `~/REPO/ME`) — they live under a
separate, clearly agent-owned directory.

Override with `PR_WORKTREE_ROOT=<absolute-path>` for non-standard layouts
(e.g. a different disk). Must be absolute and must not be inside your repo
checkout. If `XDG_DATA_HOME` is set, `~/.local/share` is replaced by its
value (standard XDG convention).

**cd into the printed worktree path after `start`**, and run every remaining
step (implement, gate, push, open, review loop) from there — not from the
directory you ran `start` in. **Don't run `cleanup` right after `open`** —
unlike the old switch-in-place behavior, `cleanup` now *deletes* the
worktree, and the review loop still needs to push fixes from that same
branch. Only run `cleanup` once the task is genuinely done: the PR merged,
or abandoned.

## Portability — read the project's specifics first

This skill hardcodes nothing project-specific. Before shipping, read the project's
`AGENTS.md`:
- **Base branch** (usually `main`) → pass as `BASE=<branch>` to `pr.sh`.
- **The quality gate command** and any coverage bar (e.g. `cargo test` for
  Rust, `mix precommit --cover` for Elixir — see AGENTS.md for the exact
  command and thresholds).

If the project has no documented gate, run its tests + formatter/linter and say so.

## The process

1. **Branch.** `pr.sh start <branch>` — creates a fresh git worktree off
   up-to-date `origin/<BASE>` and prints its path. **`cd` into that path** —
   every remaining step runs from there, never from the shared checkout.
2. **Implement + commit.** (Commit conventions: follow the
   `git-workflow-and-versioning` skill.) If the code you're touching has a
   nearby `TODO` comment, fixing it — if unblocked — takes priority over
   other opportunistic cleanup in the same edit; see **TODO comments**
   below. **Check docs for staleness** before committing: does this change
   make `README.md` or any other project doc (spec files, `docs/*.md`)
   inaccurate — a status/capability claim that no longer holds, a stale
   "not yet implemented" note, a link to a file that doesn't exist? Fix
   those in this same PR, not a follow-up — a doc that contradicts the code
   it describes is a bug, not polish, and it only gets more misleading the
   longer it's left.
3. **Gate.** Run the project's quality gate yourself. **Do not push unless
   green.** Then run an independent review pass via the
   `requesting-code-review` skill.

   Set `BASE_BRANCH` to the project's documented base branch (shown as
   `main`), then calculate the complete PR range from committed revisions:

   ```bash
   BASE_BRANCH=main  # replace when the project's documented base differs
   BASE_SHA="$(git merge-base HEAD "origin/$BASE_BRANCH")"
   HEAD_SHA="$(git rev-parse HEAD)"
   ```

   Dispatch one read-only reviewer subagent using that skill's
   `code-reviewer.md` template. Fill its description, requirements,
   `BASE_SHA`, and `HEAD_SHA` fields; reviewer inspects
   `git diff "$BASE_SHA..$HEAD_SHA"`. This pre-push pass catches what bots
   (cubic-dev-ai, codacy, etc.) would flag anyway, before the diff becomes
   public. If review flags changes: fix them, re-run the quality gate, commit
   them, refresh `HEAD_SHA`, and repeat the review pass. Continue until clean.
   Review only committed changes; never leave reviewer-driven fixes in the
   working tree or index before pushing. `REVIEWED=1` only satisfies push
   guard, not gate.
4. **Push.** `BASE="$BASE_BRANCH" REVIEWED=1 pr.sh push <branch>` —
   explicit-refspec push, then verifies the branch landed and the remote base
   branch did **not** move.
   `REVIEWED=1` is required and attests that step 3's review pass happened
   (the script can only check the flag is set, not that a review actually
   ran); `pr.sh push` refuses to run without it.
5. **Open.** `BASE="$BASE_BRANCH" pr.sh open "<title>" [body.md]` —
   `gh pr create --base "$BASE_BRANCH"`,
   prints the URL, then **STOP.** Do not merge, do not mark ready — automated
   review bots and the maintainer review and merge.
6. **Review loop.** When comments arrive: `pr.sh threads <pr>` lists unresolved
   threads (with numeric comment IDs). `pr.sh reviews <pr>` lists PR-level
   review comments (a bot's "Overall Comments" on the review itself, not on a
   line — these have no thread and can't be replied to with `reply`; the
   command pulls out each bot's "Prompt for AI Agent(s)" block when present).
   `pr.sh checks <pr>` lists CI check results (name, pass/fail/pending, link)
   — **check this too, not just `threads`/`reviews`**: a third-party analyzer
   like SonarQube/SonarCloud posts its findings as its own check with a link
   to its own web UI, not as GitHub review comments, so a PR can have zero
   unresolved threads and still be carrying real findings that `threads`
   alone would never surface. A `pass` bucket doesn't mean zero findings
   either — a non-blocking quality gate can pass while individual issues
   remain open; open the check's link (or query the analyzer's own API, e.g.
   SonarCloud's public `api/issues/search?pullRequest=<pr>&componentKeys=<key>`)
   to see the actual list before deciding there's nothing to do.

   **For each unresolved thread (and each CI-check finding worth fixing):** make the fix if warranted, run the project
   quality gate, commit the fix, then repeat step 3's
   `requesting-code-review` loop with the same `BASE_BRANCH` and a fresh
   `HEAD_SHA`. Re-push only after that loop is clean (step 4):

   ```bash
   BASE="$BASE_BRANCH" REVIEWED=1 "$P" push <branch>
   ```

   Then **reply on that thread** with your conclusion:

   ```bash
   # Reply with an inline message:
   pr.sh reply 27 3623709612 "Fixed in abc1234. ..."

   # Or reply from a file:
   pr.sh reply 27 3623709612 /tmp/reply.md
   ```

   For a general/top-level PR comment that isn't tied to a review thread
   (e.g. flagging something found while reviewing a *different* PR, a
   follow-up note, a status update): `pr.sh comment 27 "<body>"` (or a file
   path, same convention as `reply`). To correct a prior comment,
   `pr.sh comment-delete <id>` (the id from the URL `comment` printed) then
   repost via `pr.sh comment` — never a raw `gh api -X DELETE`/`-X PATCH`,
   same reason as everywhere else in this doc.

   **For PR-level (non-thread) review comments** from `pr.sh reviews`: these
   can't be threaded, so reply the same way — as a regular PR comment via
   `pr.sh comment`. Use **quote-reply format** (`> quoted text`) so readers
   know exactly which part of the review you're addressing:

   ```bash
   "$P" comment 27 "> The \`die\` message is quite long...
   Acknowledged — shortened the message and moved the rationale to SKILL.md."
   ```

   **Never resolve threads yourself and never merge** — the maintainer does both.
7. **Cleanup.** Once — and only once — the task is fully done (PR **merged**,
   or abandoned): `pr.sh cleanup` (run from inside the task's worktree)
   verifies the tree is **pristine**, removes the worktree, and prints the
   main checkout's path — `cd` there for the next task. **Do not run this
   right after `open`** — the review loop (step 6) still needs to push
   fixes from this same worktree, and `cleanup` deletes it. It's
   **non-destructive**: uncommitted/untracked files (including gitignored
   ones `git worktree remove` would otherwise silently delete along with
   the whole directory) make it report and stop rather than discard
   anything, so you can commit/stash/move them and re-run.

## Commands (verified)

```bash
P=<this-skill's-own-directory>/pr.sh   # e.g. ~/.claude/skills/pull-request-process/pr.sh,
                                        # or ~/.agents/skills/pull-request-process/pr.sh —
                                        # wherever your installer put this skill
BASE=main "$P" start  my-feature          # new worktree off up-to-date origin/main, prints its path
cd '<path printed by pr.sh start>'         # <-- cd into THAT exact printed path; everything below runs from here
BASE=main REVIEWED=1 "$P" push my-feature # requires a requesting-code-review pass first; safe push + verify main didn't advance
BASE=main "$P" open   "feat: my feature" body.md   # gh pr create --base main, then STOP
BASE=main DRAFT=1 "$P" open "wip: experiment"      # open as draft (bots typically skip drafts)
BASE=main DRY_RUN=1 "$P" open "feat: foo"          # preview the gh command without creating
"$P" threads 17                            # list unresolved review threads on PR #17
"$P" reviews 17                            # list PR-level review comments + their AI-agent prompts
"$P" checks 17                             # list CI check results (SonarQube/SonarCloud etc. included)
"$P" comment 17 "Status update: ..."               # general/top-level PR comment (inline)
"$P" comment 17 /tmp/comment.md                    # general/top-level PR comment (file)
"$P" comment-delete 5148799955                     # delete a prior comment (id from its URL)
"$P" reply 17 3623709612 "Fixed in abc1234."       # reply to a thread (inline)
"$P" reply 17 3623709612 /tmp/reply.md             # reply to a thread (file)
"$P" comment 17 $'> quoted text\nAcknowledged.'    # PR-level quote-reply (bot identity); $'...' for a real newline
# ...only once the PR is merged or abandoned, never right after `open`:
BASE=main "$P" cleanup                     # verify pristine, remove worktree, print main checkout path
```

`threads` truncates each comment body to 280 chars — enough to identify the
concern, not enough to read an entire review. Use the PR URL for full context.
The numeric comment IDs shown can be passed to `reply` to post a response on
that thread.

## Why the push is done this way (don't shortcut it)

- `pr.sh start` branches with `git worktree add --no-track -b <name> <path>
  origin/<BASE>`. The `--no-track` matters: branching from a remote-tracking
  ref like `origin/main` would otherwise (via `branch.autoSetupMerge`,
  on by default) set the new branch to *track* `origin/main`; with
  `push.default=upstream` a bare `git push` would then write straight to
  `origin/main`, bypassing the whole PR/review flow. `pr.sh start` does this
  safely for you — don't recreate the branch by hand without the same flag.
- Always push with an **explicit refspec** (`git push origin HEAD:refs/heads/<name>`)
  and verify afterward. `pr.sh push` captures `origin/main` before and after and
  **fails loudly if it moved** — this is the guardrail against the once-real
  accident of pushing straight to `main`.

## TODO comments

Inline `TODO` comments in code are fine — encouraged, even — for technical
debt where having the surrounding code context is specially relevant to
understanding it. This complements (doesn't replace) any project-level debt
tracker the repo already has (e.g. a `tech-debt.md` with TD-NNN entries):
use the tracker for debt that's better understood at the epic/spec level,
and an inline `TODO` for debt that only really makes sense next to the code
it concerns.

- Make a `TODO` specific enough to act on later — what's deferred, and
  ideally why — not a bare `TODO: fix this`.
- They need periodic review, not just creation. When doing broader
  codebase work (audits, automation recommendations, epic close-outs), a
  sweep of existing `TODO`s is worth surfacing as part of that pass.
- **When editing code that already has a nearby `TODO`, fixing it — if
  unblocked — takes priority over other opportunistic cleanup in the same
  change.** Don't leave it for "later" again if you're already there and
  nothing blocks resolving it now.

## Guardrails (never violate)

- Never merge a PR or mark it ready-to-merge.
- Never resolve review threads — reply, and let the maintainer resolve.
- Never push unless the project's quality gate is green.
- Never push without running a `requesting-code-review` pass first and
  addressing what it flags (enforced by `pr.sh push` requiring `REVIEWED=1`).
- Never call `gh` directly for a PR interaction — always through `pr.sh`
  (`open`/`comment`/`comment-delete`/`reply`/`threads`/`reviews`/`checks`), so the
  agent identity enforcement can never be silently bypassed.
- One concern per PR.
