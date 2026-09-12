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

echo "[audit] fetching + pruning origin, base=$BASE" >&2
git fetch origin --prune --quiet 2>&1 | grep -v '^$' >&2 || true

# `gh`'s *default* active account is not necessarily the one with access to
# this repo (e.g. a GITHUB_TOKEN-sourced account with only public_repo scope
# can be "active" while a full-scope keyring account sits unused) — that
# combination makes `gh auth status` succeed while `gh pr list` silently
# returns empty on a private repo. Resolve a token explicitly and export it
# so every gh call below actually has repo access, instead of trusting
# whichever account gh picked as default.
HAS_GH=0
if command -v gh >/dev/null 2>&1; then
  GH_OWNER=$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$#\1#')
  RESOLVED_TOKEN=""
  for u in "$GH_OWNER" ""; do
    [ -z "$u" ] && continue
    t=$(gh auth token -h github.com -u "$u" 2>/dev/null || true)
    if [ -n "$t" ] && GH_TOKEN="$t" gh pr list --state all --limit 1 >/dev/null 2>&1; then
      RESOLVED_TOKEN="$t"
      break
    fi
  done
  if [ -z "$RESOLVED_TOKEN" ]; then
    RESOLVED_TOKEN=$(gh auth token 2>/dev/null || true)
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

# map branch -> worktree path, if any
declare -A WORKTREE_OF
while IFS= read -r line; do
  path=$(echo "$line" | awk '{print $1}')
  branch=$(echo "$line" | grep -o '\[[^]]*\]' | tr -d '[]')
  [ -n "$branch" ] && WORKTREE_OF["$branch"]="$path"
done < <(git worktree list | tail -n +1)

while IFS= read -r b; do
  [ "$b" = "$BASE" ] && continue
  [ "$b" = "$CURRENT" ] && continue

  wt="${WORKTREE_OF[$b]:-}"
  if [ -n "$wt" ]; then
    dirty=$(git -C "$wt" status --porcelain -uall 2>/dev/null || true)
    if [ -n "$dirty" ]; then
      DIRTY+=("$b|$wt")
      continue
    fi
  fi

  pr_state=""
  if [ "$HAS_GH" = "1" ]; then
    pr_state=$(gh pr list --state all --head "$b" --json state --jq '.[0].state' 2>/dev/null || true)
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
    state=$(gh pr list --state merged --head "$rb" --json state --jq '.[0].state' 2>/dev/null || true)
    if [ "$state" = "MERGED" ]; then
      echo "  origin/$rb"
    fi
  done
else
  echo "  (gh not available/authenticated — skipped)"
fi
exit 0
