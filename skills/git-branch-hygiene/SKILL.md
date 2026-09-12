---
name: git-branch-hygiene
description: Audit and clean up accumulated local git branches and worktrees (from past pr.sh/pull-request-process sessions that never ran cleanup). Use when the user says branches/worktrees feel cluttered, asks for a branch cleanup or "git hygiene" pass, or periodically after a run of merged PRs — never automatically deletes anything without a review pass and explicit confirmation.
---

# Git Branch Hygiene

The `pull-request-process` skill's `cleanup` step only removes the *one*
worktree/branch a task just finished with — and only when explicitly run,
right after a PR merges. In practice that step gets skipped constantly
(session ends before merge, user moves on, a new session starts cold), so
local branches and `pr.sh start` worktrees pile up silently across many
sessions. This skill is the periodic sweep that catches all of that at
once, for the whole repo — not a replacement for `pull-request-process`'s
per-task cleanup, a backstop for when it didn't happen.

## Core principle

**Classify everything before touching anything.** A branch merged via a
squash or true-merge PR is NOT an ancestor of `main` by git's own ancestry
check — relying on `git branch --merged` alone silently mis-classifies
those as unmerged. Always cross-check against the forge's actual PR state
(`gh pr list --head <branch>`) when available, and only fall back to the
ancestor check for branches with no PR record at all.

**Never delete on inference.** A branch with real commits and no PR record
might be abandoned scratch work — or it might be someone's still-relevant
draft that never got pushed. A worktree with uncommitted files is never
safe to force-remove, no matter how old it looks. Every ambiguous case
gets surfaced to the user; only clearly-merged branches get deleted without
individual confirmation (and even then, as one batch confirmation showing
the full list — see Step 3).

## Step 1: Run the audit

`audit.sh` is a sibling of whatever directory this `SKILL.md` was loaded
from — resolve it there rather than assuming a fixed install root (e.g.
`~/.claude/skills/git-branch-hygiene/audit.sh`,
`~/.agents/skills/git-branch-hygiene/audit.sh`, or a project-local
`.agents/skills/git-branch-hygiene/audit.sh`, depending on how this skill
was installed).

```bash
A=<this-skill's-own-directory>/audit.sh
"$A" [base-branch]
```

Read-only — fetches + prunes `origin`, then classifies every local branch
and its worktree (if any) into four buckets:

- **SAFE TO DELETE** — merged PR, or (no PR record) verified ancestor of
  the base branch.
- **NEEDS A DECISION** — open PR (active, never touch), closed-without-
  merging PR (possibly abandoned), or no PR + unmerged (real content not
  in the base branch — could be forgotten work).
- **DIRTY WORKTREES** — uncommitted or untracked files sitting in a
  worktree. Never force-remove these. Read what's actually there
  (`git -C <path> diff`, `git -C <path> status --short`, open the files) —
  don't just count lines. It might be nothing (a stray regenerated file
  safe to discard) or it might be real unshipped work (a script, a doc, a
  fix) that deserves its own commit and PR before the worktree goes away.
- **STALE REMOTE BRANCHES** — remote refs whose PR already merged but
  were never auto-deleted (repo's auto-delete-branch-on-merge setting is
  off, or the merge happened before it was enabled).

## Step 2: Resolve every NEEDS A DECISION and DIRTY WORKTREE item first

For each one, actually look before asking:

- **Closed-without-merging PR**: check the PR itself (`gh pr view <n>`) —
  was it closed as superseded/rejected, or just gone stale? Diff it against
  current `main` to see if it still adds anything real.
- **No PR, unmerged**: diff against the same base you passed to `audit.sh`
  (`git diff origin/<base>..<branch> --stat` — e.g. `origin/main..<branch>`
  only if the base is `main`; use whatever base the audit actually ran
  against, or the diff is comparing against the wrong ref). If the diff is
  dominated by deletions of files the base later added (the branch is just
  old and behind, not adding anything new), it's likely safe. If it adds
  real, unique content, it needs the user's call.
- **Dirty worktree**: read every uncommitted/untracked file's content. If
  it's substantive (a script, systemd unit, doc rewrite, anything that
  represents actual unshipped effort), the right move is usually to commit
  it on a **fresh, rebased branch** (the old worktree's branch is often
  far behind `main` — don't just commit atop stale history) and open a PR
  via `pull-request-process`, not to silently drop it.

Then ask the user, one option per item, using their answer to decide:
delete / keep / commit-and-PR / reopen-PR. Batch related items into one
question set rather than asking one at a time when there are several.

## Step 3: Execute

**SAFE items** — present the full branch list (names + reason) in one
message and get a single explicit "yes, delete these" before running
anything; deleting branches is a destructive action per the standard
safety rules even when confirmed-merged. Then:

```bash
# For each SAFE branch WITH a worktree, remove the worktree first. Do NOT
# use --force: the audit's clean/dirty read is a snapshot from Step 1, and
# Step 2's investigation takes time — a file can land in the worktree in
# between. Plain `git worktree remove` re-checks and refuses (rather than
# destroying anything) if the worktree became dirty since the audit ran:
git worktree remove "<worktree-path>"

# Then delete the branch (force flag is fine — merge state was verified
# via PR/ancestry, not git's own --merged check, which can't see squash
# or true merges):
git branch -D "<branch>"
```

**STALE REMOTE branches** — confirm, then:

```bash
git push origin --delete "<branch>"
```

**Recovered work from a dirty worktree** — follow `pull-request-process`
end to end (rebase onto current base if the worktree was stale, commit,
self-review, push, open PR) before removing that worktree.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "`git branch --merged` says these are unmerged, so they're not safe" | Squash and true merges break ancestry — check the PR's actual state via `gh`, not just ancestry. |
| "It's just a stray file in the worktree, not worth reading" | Read it anyway. This is exactly how a real backup script sat uncommitted and unshipped for two weeks. |
| "38 branches all say merged, I'll just delete them all without a summary" | Still one batch confirmation with the full list — destructive actions get confirmed even when they're individually low-risk. |
| "The branch is old, so whatever it adds is obsolete" | Diff it. A stale branch behind main is usually just behind, but occasionally it's genuinely unmerged real work nobody finished — check before assuming which. |
| "PR was closed, so the work is dead" | Closed ≠ rejected. Check why it was closed before deleting the branch or the remote copy. |
