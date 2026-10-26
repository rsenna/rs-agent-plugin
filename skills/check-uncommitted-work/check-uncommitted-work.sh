#!/usr/bin/env bash
# Read-only audit of the current shared checkout's branch and local state.
set -euo pipefail

fail() {
  printf '[check-uncommitted-work] error: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "usage: check-uncommitted-work.sh (run from the shared checkout)"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
repo_root="$(cd "$repo_root" && pwd -P)" || fail "cannot resolve repository root"
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
  branch_counts="$(git rev-list --left-right --count "$default_ref...HEAD")" || fail "cannot compare local and remote default branch"
  read -r remote_only local_only <<< "$branch_counts"
  if [[ "$remote_only" -eq 0 && "$local_only" -eq 0 ]]; then
    printf 'Branch state: on default branch and in sync with origin/%s\n' "$default_branch"
  elif [[ "$remote_only" -gt 0 && "$local_only" -eq 0 ]]; then
    printf 'Branch state: drift — local %s is behind origin/%s by %s commit(s)\n' "$default_branch" "$default_branch" "$remote_only"
  elif [[ "$remote_only" -eq 0 && "$local_only" -gt 0 ]]; then
    printf 'Branch state: drift — local %s is ahead of origin/%s by %s commit(s)\n' "$default_branch" "$default_branch" "$local_only"
  else
    printf 'Branch state: drift — local %s and origin/%s have diverged (%s remote-only, %s local-only commit(s))\n' \
      "$default_branch" "$default_branch" "$remote_only" "$local_only"
  fi
else
  branch_is_integrated() {
    local merge_base branch_patch default_patch commit cherry_output

    if git merge-base --is-ancestor HEAD "$default_ref"; then
      return 0
    fi

    # `git cherry` catches commits that were cherry-picked or rebased onto the
    # default branch, even though their original commit IDs are not ancestors.
    if cherry_output="$(git cherry "$default_ref" HEAD 2>/dev/null)"; then
      if [[ -z "$cherry_output" ]] || ! grep -q '^+' <<< "$cherry_output"; then
        return 0
      fi
    fi

    # A squash merge changes commit identity and combines the branch diff into
    # one commit. Compare the complete branch patch with each first-parent
    # default-branch commit so a typical squash merge is not mislabeled.
    merge_base="$(git merge-base "$default_ref" HEAD 2>/dev/null)" || return 1
    branch_patch="$(git diff --binary "$merge_base" HEAD | git patch-id --stable | awk 'NR == 1 { print $1 }')"
    [[ -n "$branch_patch" ]] || return 1
    while IFS= read -r commit; do
      default_patch="$(git diff --binary "${commit}^1" "$commit" | git patch-id --stable | awk 'NR == 1 { print $1 }')"
      [[ "$branch_patch" == "$default_patch" ]] && return 0
    done < <(git rev-list --first-parent "$default_ref" "^$merge_base")
    return 1
  }

  if branch_is_integrated; then
    printf 'Branch state: drift — on %s, whose work is integrated into origin/%s (ancestry or patch-equivalent)\n' \
      "$current_branch" "$default_branch"
  else
    printf 'Branch state: drift — on %s; integration into origin/%s is not proven, review before cleanup\n' \
      "$current_branch" "$default_branch"
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

status_tmp_dir=""
for candidate_tmp_dir in "${TMPDIR:-/tmp}" /tmp /var/tmp; do
  [[ -d "$candidate_tmp_dir" ]] || continue
  resolved_tmp_dir="$(cd "$candidate_tmp_dir" && pwd -P)" || continue
  if [[ "$resolved_tmp_dir" == "$repo_root" || "$resolved_tmp_dir" == "$repo_root/"* ]]; then
    continue
  fi
  status_tmp_dir="$resolved_tmp_dir"
  break
done
[[ -n "$status_tmp_dir" ]] || fail "cannot find a temporary directory outside the checkout"
status_file="$(mktemp "$status_tmp_dir/check-uncommitted-work.XXXXXX")" || fail "cannot create temporary status file"
desc_file=""
trap 'rm -f "$status_file" "${desc_file:-}"' EXIT
git status --porcelain=v1 --no-renames --untracked-files=all --ignored=matching -z > "$status_file" || fail "git status failed"
status_count=0

report_path() {
  local status="$1" path="$2" classification
  [[ -n "$path" ]] || return 0
  status_count=$((status_count + 1))
  if is_known_noise "$path"; then
    classification=KNOWN_NOISE
  else
    classification=REVIEW
  fi
  printf '  %s [%s] ' "$status" "$classification"
  printf '%q\n' "$path"
}

while IFS= read -r -d '' entry; do
  [[ -n "$entry" ]] || continue
  status="${entry:0:2}"
  path="${entry:3}"

  if [[ "$status" == '!!' && -d "$repo_root/$path" ]]; then
    desc_file="$(mktemp "$status_tmp_dir/check-uncommitted-work-paths.XXXXXX")" || fail "cannot create temporary path list"
    if ! find "$repo_root/$path" -mindepth 1 -print0 > "$desc_file"; then
      fail "cannot enumerate ignored directory: $path"
    fi
    found_descendant=0
    while IFS= read -r -d '' descendant; do
      found_descendant=1
      descendant_path="${descendant#"$repo_root"/}"
      report_path "$status" "$descendant_path"
    done < "$desc_file"
    rm -f "$desc_file"
    desc_file=""
    if [[ "$found_descendant" -eq 0 ]]; then
      report_path "$status" "$path"
    fi
  else
    report_path "$status" "$path"
  fi
done < "$status_file"
if [[ $status_count -eq 0 ]]; then
  printf 'Working tree: clean (no uncommitted, untracked, or ignored paths)\n'
else
  printf 'Working tree: %d path(s) reported; inspect every REVIEW item before classifying it as real work or ambiguous.\n' "$status_count"
fi

printf '\nWorktrees:\n'
worktree_listing="$(git worktree list --porcelain)" || fail "cannot list Git worktrees"
worktree_path=""
worktree_branch="(detached or unknown branch)"
worktree_locked=0
worktree_prunable=0
worktree_count=0

report_worktree() {
  [[ -n "$worktree_path" ]] || return 0
  local state status_output flags
  worktree_count=$((worktree_count + 1))
  flags=""
  [[ "$worktree_locked" -eq 0 ]] || flags+=" locked"
  [[ "$worktree_prunable" -eq 0 ]] || flags+=" prunable"
  if [[ ! -d "$worktree_path" ]]; then
    state="unavailable; review before cleanup"
  elif status_output="$(git -C "$worktree_path" status --porcelain=v1 --untracked-files=all --ignored=matching 2>/dev/null)"; then
    if [[ -n "$status_output" ]]; then
      state="has local or ignored state; review before cleanup"
    else
      state="clean"
    fi
  else
    state="status unavailable; review before cleanup"
  fi
  printf '  %s [%s%s] %s\n' "$worktree_path" "$worktree_branch" "$flags" "$state"
}

while IFS= read -r line; do
  case "$line" in
    'worktree '*)
      report_worktree
      worktree_path="${line#worktree }"
      worktree_branch="(detached or unknown branch)"
      worktree_locked=0
      worktree_prunable=0
      ;;
    'branch refs/heads/'*) worktree_branch="${line#branch refs/heads/}" ;;
    'locked'*) worktree_locked=1 ;;
    'prunable'*) worktree_prunable=1 ;;
    '') report_worktree; worktree_path="" ;;
  esac
done <<< "$worktree_listing"
report_worktree
if [[ "$worktree_count" -eq 0 ]]; then
  printf '  (none reported)\n'
fi
printf 'For worktree cleanup decisions, use git-branch-hygiene; this audit never removes worktrees.\n'
