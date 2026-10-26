#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-uncommitted-work.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local text="$1" expected="$2"
  [[ "$text" == *"$expected"* ]] || fail "expected output to contain '$expected'"
}

init_repo() {
  local repo="$TMP_ROOT/$1"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.invalid
  printf 'cache/\n' > "$repo/.gitignore"
  printf 'base\n' > "$repo/base.txt"
  git -C "$repo" add .gitignore base.txt
  git -C "$repo" commit -qm base
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  printf '%s' "$repo"
}

run_audit() {
  local repo="$1"
  shift
  (cd "$repo" && HOME="$TMP_ROOT/home" XDG_CONFIG_HOME="$TMP_ROOT/config" "$@" "$SCRIPT")
}

mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/config/check-uncommitted-work"

# Exact default-branch tip is the only no-drift state.
repo="$(init_repo in-sync)"
out="$(run_audit "$repo" env)"
assert_contains "$out" "Branch state: on default branch and in sync with origin/main"
assert_contains "$out" "Worktrees:"
assert_contains "$out" "For worktree cleanup decisions, use git-branch-hygiene"

# Tracked and untracked work is reported as reviewable path-level state.
repo="$(init_repo mixed-state)"
printf 'modified\n' >> "$repo/base.txt"
printf 'new\n' > "$repo/new-file.txt"
out="$(run_audit "$repo" env)"
assert_contains "$out" " M [REVIEW] base.txt"
assert_contains "$out" "?? [REVIEW] new-file.txt"

# The local default branch must report remote-only commits as drift.
repo="$(init_repo default-behind)"
git -C "$repo" switch -q -c upstream
printf 'upstream\n' >> "$repo/base.txt"
git -C "$repo" commit -qam upstream
git -C "$repo" update-ref refs/remotes/origin/main HEAD
git -C "$repo" switch -q main
out="$(run_audit "$repo" env)"
assert_contains "$out" "local main is behind origin/main by 1 commit(s)"

# The local default branch must report local-only commits as drift.
repo="$(init_repo default-ahead)"
printf 'local\n' >> "$repo/base.txt"
git -C "$repo" commit -qam local
out="$(run_audit "$repo" env)"
assert_contains "$out" "local main is ahead of origin/main by 1 commit(s)"

# The local default branch must report both-sided divergence distinctly from a one-sided drift.
repo="$(init_repo default-diverged)"
printf 'local\n' >> "$repo/base.txt"
git -C "$repo" commit -qam local
git -C "$repo" switch -q -c upstream HEAD~1
printf 'upstream\n' >> "$repo/base.txt"
git -C "$repo" commit -qam upstream
git -C "$repo" update-ref refs/remotes/origin/main HEAD
git -C "$repo" switch -q main
out="$(run_audit "$repo" env)"
assert_contains "$out" "local main and origin/main have diverged (1 remote-only, 1 local-only commit(s))"

# An ancestor branch is recognized as integrated.
repo="$(init_repo ancestry-merged)"
git -C "$repo" switch -q -c feature
printf 'feature\n' > "$repo/feature.txt"
git -C "$repo" add feature.txt
git -C "$repo" commit -qm feature
git -C "$repo" update-ref refs/remotes/origin/main HEAD
out="$(run_audit "$repo" env)"
assert_contains "$out" "work is integrated into origin/main (ancestry or patch-equivalent)"

# A cherry-picked equivalent is recognized even though the source commit is not an ancestor.
repo="$(init_repo cherry-picked)"
git -C "$repo" switch -q -c feature
printf 'feature\n' > "$repo/feature.txt"
git -C "$repo" add feature.txt
git -C "$repo" commit -qm feature
git -C "$repo" switch -q main
printf 'other\n' > "$repo/other.txt"
git -C "$repo" add other.txt
git -C "$repo" commit -qm other
git -C "$repo" cherry-pick feature >/dev/null
git -C "$repo" update-ref refs/remotes/origin/main HEAD
git -C "$repo" switch -q feature
out="$(run_audit "$repo" env)"
assert_contains "$out" "work is integrated into origin/main (ancestry or patch-equivalent)"

# A squash-equivalent patch is recognized even when the source commit is not an ancestor.
repo="$(init_repo squash-merged)"
git -C "$repo" switch -q -c feature
printf 'feature\n' > "$repo/feature.txt"
git -C "$repo" add feature.txt
git -C "$repo" commit -qm feature
printf 'feature two\n' > "$repo/feature-two.txt"
git -C "$repo" add feature-two.txt
git -C "$repo" commit -qm 'feature two'
git -C "$repo" switch -q main
git -C "$repo" merge --squash feature >/dev/null
git -C "$repo" commit -qm 'squash feature'
git -C "$repo" update-ref refs/remotes/origin/main HEAD
git -C "$repo" switch -q feature
out="$(run_audit "$repo" env)"
assert_contains "$out" "work is integrated into origin/main (ancestry or patch-equivalent)"

# Recursively ignored descendants are listed and individually matched against configured patterns.
repo="$(init_repo ignored-descendants)"
mkdir -p "$repo/cache/nested"
printf 'known\n' > "$repo/cache/nested/known.log"
printf 'review\n' > "$repo/cache/nested/unknown.log"
printf 'cache/nested/known.log\n' > "$TMP_ROOT/config/check-uncommitted-work/noisy-paths"
out="$(cd "$repo" && HOME="$TMP_ROOT/home" XDG_CONFIG_HOME="$TMP_ROOT/config" TMPDIR="$repo" "$SCRIPT")"
assert_contains "$out" "[KNOWN_NOISE] cache/nested/known.log"
assert_contains "$out" "[REVIEW] cache/nested/unknown.log"
if [[ "$out" == *"check-uncommitted-work."* ]]; then
  fail "audit reported its own temporary status file"
fi

# Inventory reports linked worktrees without changing or removing them —
# both a dirty one (local/ignored state) and a clean one side by side.
repo="$(init_repo worktree-inventory)"
linked="$TMP_ROOT/linked-worktree"
git -C "$repo" worktree add -q -b task-worktree "$linked" HEAD
printf 'leftover\n' > "$linked/leftover.txt"
git -C "$repo" worktree lock "$linked"
clean_linked="$TMP_ROOT/clean-linked-worktree"
git -C "$repo" worktree add -q -b clean-worktree "$clean_linked" HEAD
out="$(run_audit "$repo" env)"
assert_contains "$out" "$repo [main] clean"
assert_contains "$out" "$linked [task-worktree locked] has local or ignored state; review before cleanup"
assert_contains "$out" "$clean_linked [clean-worktree] clean"
assert_contains "$out" "For worktree cleanup decisions, use git-branch-hygiene"
[[ -d "$linked" ]] || fail "audit removed a linked worktree"
[[ -d "$clean_linked" ]] || fail "audit removed a linked worktree"

# A check invoked inside a linked worktree must still refuse to treat it as the shared checkout.
if out="$(cd "$linked" && HOME="$TMP_ROOT/home" XDG_CONFIG_HOME="$TMP_ROOT/config" "$SCRIPT" 2>&1)"; then
  fail "expected linked-worktree invocation to fail"
fi
assert_contains "$out" "this is a linked worktree"

printf 'ok\n'
