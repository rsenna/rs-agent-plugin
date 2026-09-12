#!/usr/bin/env bash
# audit.sh — read-only classifier for local git branches and worktrees.
#
# Never deletes or modifies anything. Prints a classified report:
#   SAFE            — merged (via a merged PR, or verified ancestor of base)
#   NEEDS_DECISION  — unmerged with no PR, or PR closed-without-merging
#   DIRTY_WORKTREE  — worktree has uncommitted/untracked files (never auto-touch)
#   STALE_REMOTE    — remote branch whose PR is merged but the ref lingers
#
# Usage: audit.sh [base-branch]
#   base-branch defaults to origin/HEAD's target (usually main).
#
# Requires: git, gh (optional — without it, classification falls back to
# ancestor-of-base only, and PR-closed-but-unmerged branches can't be told
# apart from genuinely-unpushed work).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##') || true
  BASE="${BASE:-main}"
fi
# accept a remote-qualified base ("origin/main") as well as a bare branch
# name ("main") — everything below assumes bare and adds its own "origin/".
BASE="${BASE#origin/}"

echo "[audit] fetching origin, base=$BASE" >&2
# No --prune: this is a read-only audit and pruning remote-tracking refs
# would delete state (potentially the only local record of a stale branch)
# before the report is even produced. Fail closed on fetch errors instead
# of classifying branches against a possibly-stale origin.
if ! git fetch origin --quiet; then
  echo "[audit] error: git fetch origin failed — refusing to classify against stale refs" >&2
  exit 1
fi

# `gh`'s *default* active account is not necessarily the one with access to
# this repo (e.g. a GITHUB_TOKEN-sourced account with only public_repo scope
# can be "active" while a full-scope keyring account sits unused) — that
# combination makes `gh auth status` succeed while `gh pr list` silently
# returns empty on a private repo. Resolve a token explicitly and export it
# so every gh call below actually has repo access, instead of trusting
# whichever account gh picked as default.
HAS_GH=0
if command -v gh >/dev/null 2>&1; then
  RESOLVED_TOKEN=""
  # Try every logged-in github.com account (not the repo/org owner — an org
  # owner has no login account of its own, so that never matches) until one
  # can actually list PRs on this repo.
  while IFS= read -r acct; do
    [ -z "$acct" ] && continue
    t=$(gh auth token -h github.com -u "$acct" 2>/dev/null || true)
    if [ -n "$t" ] && GH_TOKEN="$t" gh pr list --state all --limit 1 >/dev/null 2>&1; then
      RESOLVED_TOKEN="$t"
      break
    fi
  done < <(gh auth status -h github.com 2>&1 | sed -n 's/^[[:space:]]*.*[Ll]ogged in to github\.com account \([^[:space:]]*\).*/\1/p')
  if [ -z "$RESOLVED_TOKEN" ]; then
    t=$(gh auth token 2>/dev/null || true)
    if [ -n "$t" ] && GH_TOKEN="$t" gh pr list --state all --limit 1 >/dev/null 2>&1; then
      RESOLVED_TOKEN="$t"
    fi
  fi
  if [ -n "$RESOLVED_TOKEN" ]; then
    export GH_TOKEN="$RESOLVED_TOKEN"
    if gh pr list --state all --limit 1 >/dev/null 2>&1; then
      HAS_GH=1
    else
      echo "[audit] warning: gh is installed but can't list PRs on this repo (scope/access?) — falling back to ancestor-only classification" >&2
    fi
  fi
fi

CURRENT=$(git branch --show-current)

declare -a SAFE=()
declare -a NEEDS_DECISION=()
declare -a DIRTY=()

# map branch -> worktree path, if any. Use --porcelain (one field per line)
# rather than the single-line human format: a worktree path containing
# spaces would otherwise be truncated by splitting on whitespace.
declare -A WORKTREE_OF
current_path=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) current_path="${line#worktree }" ;;
    branch\ refs/heads/*)
      branch="${line#branch refs/heads/}"
      [ -n "$current_path" ] && WORKTREE_OF["$branch"]="$current_path"
      ;;
    "") current_path="" ;;
  esac
done < <(git worktree list --porcelain)

while IFS= read -r b; do
  [ "$b" = "$BASE" ] && continue

  if [ "$b" = "$CURRENT" ]; then
    # Still surface dirty state for the branch we're running from — silently
    # skipping it entirely would let a dirty feature worktree look clean in
    # the report. --ignored so ignored-but-important files (.env, generated,
    # backups) count as dirty too, since Step 3 would otherwise be allowed
    # to remove a worktree that "looks" clean but isn't.
    dirty=$(git status --porcelain --ignored -uall 2>/dev/null || true)
    [ -n "$dirty" ] && DIRTY+=("$b|$(pwd)")
    continue
  fi

  wt="${WORKTREE_OF[$b]:-}"
  if [ -n "$wt" ]; then
    dirty=$(git -C "$wt" status --porcelain --ignored -uall 2>/dev/null || true)
    if [ -n "$dirty" ]; then
      DIRTY+=("$b|$wt")
      continue
    fi
  fi

  pr_state=""
  if [ "$HAS_GH" = "1" ]; then
    # A branch can have more than one PR record (e.g. an old one merged, a
    # new one open on the same branch name after re-push). Prefer OPEN over
    # MERGED over CLOSED so active work is never misclassified as safe.
    pr_state=$(gh pr list --state all --head "$b" --json state \
      --jq 'if any(.[]; .state=="OPEN") then "OPEN"
            elif any(.[]; .state=="MERGED") then "MERGED"
            elif length>0 then .[0].state
            else "" end' 2>/dev/null || true)
  fi

  is_ancestor=0
  git merge-base --is-ancestor "$b" "origin/$BASE" 2>/dev/null && is_ancestor=1

  case "$pr_state" in
    MERGED)
      SAFE+=("$b|merged PR")
      ;;
    OPEN)
      NEEDS_DECISION+=("$b|open PR — active work, do not delete")
      ;;
    CLOSED)
      NEEDS_DECISION+=("$b|PR closed WITHOUT merging — possibly abandoned, ask before deleting")
      ;;
    *)
      if [ "$is_ancestor" = "1" ]; then
        SAFE+=("$b|no PR record, but ancestor of origin/$BASE")
      else
        NEEDS_DECISION+=("$b|no PR, unmerged — real content not in $BASE, ask before deleting")
      fi
      ;;
  esac
done < <(git branch --format='%(refname:short)')

echo
echo "=== SAFE TO DELETE (${#SAFE[@]}) — merged or ancestor-of-$BASE ==="
for e in "${SAFE[@]+"${SAFE[@]}"}"; do
  IFS='|' read -r b reason <<<"$e"
  wt="${WORKTREE_OF[$b]:-}"
  if [ -n "$wt" ]; then
    printf '  %-55s %-30s [worktree: %s]\n' "$b" "$reason" "$wt"
  else
    printf '  %-55s %s\n' "$b" "$reason"
  fi
done

echo
echo "=== NEEDS A DECISION (${#NEEDS_DECISION[@]}) — do not delete without asking ==="
for e in "${NEEDS_DECISION[@]+"${NEEDS_DECISION[@]}"}"; do
  IFS='|' read -r b reason <<<"$e"
  printf '  %-55s %s\n' "$b" "$reason"
done

echo
echo "=== DIRTY WORKTREES (${#DIRTY[@]}) — uncommitted work, NEVER auto-touch ==="
for e in "${DIRTY[@]+"${DIRTY[@]}"}"; do
  IFS='|' read -r b wt <<<"$e"
  echo "  branch: $b"
  echo "  worktree: $wt"
  git -C "$wt" status --short | sed 's/^/    /'
  echo
done

echo "=== STALE REMOTE BRANCHES (merged PR, remote ref never auto-deleted) ==="
if [ "$HAS_GH" = "1" ]; then
  git for-each-ref --format='%(refname:short)' 'refs/remotes/origin' | sed -e '/\/HEAD$/d' -e 's#^origin/##' | while read -r rb; do
    [ -z "$rb" ] && continue
    [ "$rb" = "$BASE" ] && continue
    # Query all states, not just merged: a remote branch can have both an
    # old merged PR and a newer open one — that's active work, not stale.
    state=$(gh pr list --state all --head "$rb" --json state \
      --jq 'if any(.[]; .state=="OPEN") then "OPEN"
            elif any(.[]; .state=="MERGED") then "MERGED"
            elif length>0 then .[0].state
            else "" end' 2>/dev/null || true)
    if [ "$state" = "MERGED" ]; then
      echo "  origin/$rb"
    fi
  done
else
  echo "  (gh not available/authenticated — skipped)"
fi
exit 0
