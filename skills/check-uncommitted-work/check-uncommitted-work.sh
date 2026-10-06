#!/usr/bin/env bash
# Read-only audit of the current shared checkout's branch and local state.
set -euo pipefail

fail() {
  printf '[check-uncommitted-work] error: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "usage: check-uncommitted-work.sh (run from the shared checkout)"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
cd "$repo_root"

git_dir="$(cd "$(git rev-parse --git-dir)" && pwd -P)" || fail "cannot resolve git directory"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)" || fail "cannot resolve common git directory"
[[ "$git_dir" == "$common_dir" ]] || fail "this is a linked worktree; run from the shared checkout"

remote_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || \
  fail "origin/HEAD is not set; run 'git remote set-head origin --auto' or configure the remote default branch"
default_branch="${remote_head#origin/}"
default_ref="refs/remotes/origin/$default_branch"
git show-ref --quiet --verify "$default_ref" || fail "default-branch ref origin/$default_branch is missing"
current_branch="$(git branch --show-current)"
printf 'Checkout: %s\nDefault branch: origin/%s\n' "$repo_root" "$default_branch"
if [[ -z "$current_branch" ]]; then
  printf 'Branch state: detached HEAD; needs review\n'
elif [[ "$current_branch" == "$default_branch" ]]; then
  printf 'Branch state: on default branch\n'
else
  if git merge-base --is-ancestor HEAD "$default_ref"; then
    printf 'Branch state: drift — on %s, whose HEAD is already merged into origin/%s\n' "$current_branch" "$default_branch"
  else
    merge_status=$?
    if [[ $merge_status -eq 1 ]]; then
      printf 'Branch state: drift — on %s, not merged into origin/%s\n' "$current_branch" "$default_branch"
    else
      printf 'Branch state: drift — on %s; could not determine merge state\n' "$current_branch"
    fi
  fi
fi
noise_patterns=( '.pi' '.pi/*' '.skillkit' '.skillkit/*' )

config_home="$(printenv XDG_CONFIG_HOME 2>/dev/null || true)"
if [[ -z "$config_home" ]]; then
  home="$(printenv HOME 2>/dev/null || true)"
  [[ -z "$home" ]] || config_home="$home/.config"
fi
config_file=""
if [[ -n "$config_home" ]]; then
  config_file="$config_home/check-uncommitted-work/noisy-paths"
fi
if [[ -n "$config_file" && -e "$config_file" ]]; then
  [[ -f "$config_file" && -r "$config_file" ]] || fail "noise pattern config is not a readable file: $config_file"
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    pattern="${pattern%$'\r'}"
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    noise_patterns+=("$pattern")
  done < "$config_file"
fi

is_known_noise() {
  local path="$1" pattern
  for pattern in "${noise_patterns[@]}"; do
    # shellcheck disable=SC2254 # These are user-configured glob patterns.
    case "$path" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

status_file="$(mktemp "${TMPDIR:-/tmp}/check-uncommitted-work.XXXXXX")" || fail "cannot create temporary status file"
trap 'rm -f "$status_file"' EXIT
git status --porcelain=v1 --no-renames --untracked-files=all --ignored=matching -z > "$status_file" || fail "git status failed"
status_count=0
while IFS= read -r -d '' entry; do
  [[ -n "$entry" ]] || continue
  status="${entry:0:2}"
  path="${entry:3}"
  status_count=$((status_count + 1))
  if is_known_noise "$path"; then
    classification=KNOWN_NOISE
  else
    classification=REVIEW
  fi
  printf '  %s [%s] ' "$status" "$classification"
  printf '%q\n' "$path"
done < "$status_file"
if [[ $status_count -eq 0 ]]; then
  printf 'Working tree: clean (no uncommitted, untracked, or ignored paths)\n'
else
  printf 'Working tree: %d path(s) reported; inspect every REVIEW item before classifying it as real work or ambiguous.\n' "$status_count"
fi
