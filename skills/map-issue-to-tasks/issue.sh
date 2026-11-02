#!/usr/bin/env bash
# issue.sh — GitHub issue plumbing for the map-issue-to-tasks / fix-mapped-issue skills.
#
# Subcommands:
#   create <repo> <title> <file>  open a new issue in <repo> (owner/name — so an agent
#                                  can file a follow-up in a DIFFERENT repo than the one
#                                  it's sitting in, e.g. a rs-agent-plugin tooling gap
#                                  found while working in another repo): <title> + <file>
#                                  as the body (DRY_RUN=1 prints instead of posting)
#   fetch <n>                     print a readable digest of issue #n (title, state, labels, body, comments)
#   json <n>                      raw JSON (number,title,state,labels,body,comments,url) for parsing
#   slug <n>                      print "<n>-<slugified-title>" (used for tasks/issue-<n>-<slug>.md)
#   comment <n> <file>            post <file> as a comment on #n   (DRY_RUN=1 prints instead of posting)
#   close <n> <file>              post <file> as a comment on #n, then close it (DRY_RUN=1 prints, no close)
#   label <n> [--clear-remap]     ensure mapped label on #n; with --clear-remap also remove MUST_REMAP_LABEL
#   unlabel <n>                   remove LABEL from #n
#   reset-mapping <n> [path]      archive prior mapping task file; default auto-detects tasks/issue-<n>-*.md
#   unmapped                      list open issues still requiring mapping (missing LABEL OR flagged MUST_REMAP_LABEL)
#
# Env:
#   DRY_RUN=1   never write to GitHub; print what would be posted.
#   ISSUE_COMMENT_UPSERT_LAST=1  use gh --edit-last/--create-if-none in `comment`
#               to avoid duplicate enrichment comments on remap retries.
#   ISSUE_COMMENT_MARKER marker string used by upsert mode to identify the
#               enrichment comment to edit (default: <!-- map-issue-to-tasks:enrichment -->).
#   LABEL       label used to mark a mapped issue (default: mapped)
#   MUST_REMAP_LABEL  label that forces remapping even when LABEL exists (default: must-remap)
#   PR_BOT_DOPPLER_PROJECT / PR_BOT_DOPPLER_CONFIG  Doppler project/config holding
#               GHUB_AGENT_PATC (default: homelab/dev) — every gh call this script
#               makes uses that identity, never whatever personal `gh auth` account
#               happens to be ambient. Fetched fresh on every invocation; dies loudly
#               if unreachable rather than silently falling back. Same convention as
#               the pull-request-process skill's pr.sh.
set -euo pipefail

LABEL="${LABEL:-mapped}"
MUST_REMAP_LABEL="${MUST_REMAP_LABEL:-must-remap}"

log() { printf '\033[1;34m[issue]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[issue] %s\033[0m\n' "$*" >&2
  exit 1
}

# --- Agent identity enforcement -----------------------------------------
# GH_TOKEN, once exported, overrides gh's own ambient `gh auth` active
# account for every `gh` call this script makes — without touching the
# user's own global `gh auth` state at all.
PR_BOT_DOPPLER_PROJECT="${PR_BOT_DOPPLER_PROJECT:-homelab}"
PR_BOT_DOPPLER_CONFIG="${PR_BOT_DOPPLER_CONFIG:-dev}"
# `|| true`: under `set -e`, a failed command substitution here would otherwise
# kill the script silently, before the `[ -n "$GH_TOKEN" ] || die ...` check below
# ever runs.
GH_TOKEN="$(doppler secrets get GHUB_AGENT_PATC --plain --project "$PR_BOT_DOPPLER_PROJECT" --config "$PR_BOT_DOPPLER_CONFIG" 2>/dev/null || true)"
[ -n "$GH_TOKEN" ] || die "could not fetch GHUB_AGENT_PATC from Doppler ($PR_BOT_DOPPLER_PROJECT/$PR_BOT_DOPPLER_CONFIG) — refusing to fall back to the ambient 'gh auth' identity. Check Doppler access, or override PR_BOT_DOPPLER_PROJECT/PR_BOT_DOPPLER_CONFIG."
export GH_TOKEN

cmd_create() {
  local repo="${1:?usage: issue.sh create <repo> <title> <file>}"
  local title="${2:?usage: issue.sh create <repo> <title> <file>}"
  local f="${3:?usage: issue.sh create <repo> <title> <file>}"
  [ -f "$f" ] || die "file not found: $f"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "DRY_RUN — would create issue in '$repo' titled '$title':"
    echo "-----"
    cat "$f"
    echo "-----"
    return 0
  fi
  local url
  url="$(gh issue create --repo "$repo" --title "$title" --body-file "$f")"
  log "created: $url"
}

cmd_json() { gh issue view "${1:?usage: issue.sh json <n>}" \
  --json number,title,state,labels,body,comments,url; }

cmd_fetch() {
  local n="${1:?usage: issue.sh fetch <n>}"
  gh issue view "$n" --json number,title,state,labels,body,comments,url --jq '
    "#\(.number)  [\(.state)]  \(.title)\n\(.url)\n" +
    "labels: " + ((.labels|map(.name))|join(", ")) + "\n\n" +
    "── body ──\n" + (.body // "(empty)") + "\n" +
    (if (.comments|length)>0
     then "\n── comments ──\n" + ([.comments[] | "@\(.author.login): \(.body)"]|join("\n\n"))
     else "" end)'
}

cmd_slug() {
  local n="${1:?usage: issue.sh slug <n>}"
  local title
  title="$(gh issue view "$n" --json title --jq .title)"
  local slug
  slug="$(printf '%s' "$title" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  # Cap length without cutting a word in half: if truncating, drop the last token.
  if [ "${#slug}" -gt 50 ]; then slug="$(printf '%s' "$slug" | cut -c1-50 | sed -E 's/-[^-]*$//')"; fi
  printf '%s-%s\n' "$n" "$slug"
}

issue_has_label() {
  local n="${1:?issue number required}"
  local label="${2:?label required}"
  local labels
  labels="$(gh issue view "$n" --json labels --jq '.labels[].name')" ||
    die "failed to read labels for issue #$n"
  printf '%s\n' "$labels" | grep -Fxq "$label"
}

is_valid_issue_tasks_file() {
  local n="${1:?issue number required}"
  local p="${2:?path required}"
  # Limit explicit deletions to this issue's own mapping file under tasks/.
  printf '%s\n' "$p" | grep -Eq "^(\./)?tasks/issue-${n}-[a-z0-9._-]+\\.md$"
}

find_issue_mapping_files() {
  local n="${1:?issue number required}"
  [ -d tasks ] || return 0
  find tasks -maxdepth 1 -type f -name "issue-${n}-*.md" | LC_ALL=C sort
}

assert_issue_number() {
  local n="${1:?issue number required}"
  printf '%s\n' "$n" | grep -Eq '^[0-9]+$' || die "issue number must be numeric (got: $n)"
}

cmd_comment() {
  local n="${1:?usage: issue.sh comment <n> <file>}"
  local f="${2:?usage: issue.sh comment <n> <file>}"
  [ -f "$f" ] || die "file not found: $f"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "DRY_RUN — would post to #$n:"
    echo "-----"
    cat "$f"
    echo "-----"
    return 0
  fi
  if [ "${ISSUE_COMMENT_UPSERT_LAST:-0}" = "1" ]; then
    local bot_name
    bot_name="$(doppler secrets get GHUB_AGENT_USERNAME --plain --project "$PR_BOT_DOPPLER_PROJECT" --config "$PR_BOT_DOPPLER_CONFIG" 2>/dev/null || true)"
    [ -n "$bot_name" ] || die "could not fetch GHUB_AGENT_USERNAME from Doppler ($PR_BOT_DOPPLER_PROJECT/$PR_BOT_DOPPLER_CONFIG)"
    local marker body_file
    marker="${ISSUE_COMMENT_MARKER:-<!-- map-issue-to-tasks:enrichment -->}"
    body_file="$f"
    if ! grep -Fq "$marker" "$f"; then
      body_file="$(mktemp)"
      cat "$f" > "$body_file"
      printf '\n\n%s\n' "$marker" >> "$body_file"
    fi
    local last_body
    last_body="$(gh issue view "$n" --json comments --jq ".comments | map(select(.author.login==\"$bot_name\")) | last.body // \"\"")" ||
      die "failed to inspect prior comments for issue #$n"
    if [ -n "$last_body" ] && printf '%s\n' "$last_body" | grep -Fq "$marker"; then
      gh issue comment "$n" --edit-last --body-file "$body_file"
      log "updated existing enrichment comment on #$n"
    else
      gh issue comment "$n" --body-file "$body_file"
      log "posted enrichment comment on #$n"
    fi
    if [ "$body_file" != "$f" ]; then
      rm -f -- "$body_file"
    fi
  else
    gh issue comment "$n" --body-file "$f"
    log "commented on #$n"
  fi
}

cmd_close() {
  local n="${1:?usage: issue.sh close <n> <file>}"
  local f="${2:?usage: issue.sh close <n> <file>}"
  [ -f "$f" ] || die "file not found: $f"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "DRY_RUN — would comment then close #$n:"
    echo "-----"
    cat "$f"
    echo "-----"
    return 0
  fi
  gh issue comment "$n" --body-file "$f"
  gh issue close "$n"
  log "commented on and closed #$n"
}

cmd_label() {
  local n="${1:?usage: issue.sh label <n>}"
  assert_issue_number "$n"
  local clear_remap="${2:-}"
  local lock_dir
  lock_dir=".git/map-issue-to-tasks/remap-${n}.lock.d"
  if [ -n "$clear_remap" ] && [ "$clear_remap" != "--clear-remap" ]; then
    die "usage: issue.sh label <n> [--clear-remap]"
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    if [ "$clear_remap" = "--clear-remap" ]; then
      log "DRY_RUN — would ensure label '$LABEL' exists, apply it to #$n, and remove '$MUST_REMAP_LABEL' if present"
    else
      log "DRY_RUN — would ensure label '$LABEL' exists and apply it to #$n"
    fi
    return 0
  fi
  # Idempotent: create-if-missing (--force updates color/description if it already
  # exists rather than failing), then add — gh issue edit --add-label is a no-op
  # if the issue already has it.
  gh label create "$LABEL" --color "0E8A16" --description "Analysed and broken into tasks by map-issue-to-tasks" --force >/dev/null
  gh issue edit "$n" --add-label "$LABEL"
  if issue_has_label "$n" "$MUST_REMAP_LABEL"; then
    if [ "$clear_remap" = "--clear-remap" ]; then
      local -a active_mappings=()
      while IFS= read -r f; do
        active_mappings+=("$f")
      done < <(find_issue_mapping_files "$n")
      [ "${#active_mappings[@]}" -eq 1 ] ||
        die "cannot clear '$MUST_REMAP_LABEL' for #$n without exactly one active tasks/issue-${n}-*.md mapping file"
      [ -d "$lock_dir" ] || die "cannot clear '$MUST_REMAP_LABEL' for #$n without an active remap lock (run reset-mapping first)"
      gh issue edit "$n" --remove-label "$MUST_REMAP_LABEL"
      rm -rf -- "$lock_dir"
      log "labeled #$n with '$LABEL' and removed '$MUST_REMAP_LABEL'"
    else
      log "labeled #$n with '$LABEL' (left '$MUST_REMAP_LABEL' in place; pass --clear-remap after remap completion)"
    fi
    return 0
  fi
  if [ "$clear_remap" = "--clear-remap" ] && [ -d "$lock_dir" ]; then
    rm -rf -- "$lock_dir"
    log "labeled #$n with '$LABEL' and cleared stale remap lock (no '$MUST_REMAP_LABEL' present)"
    return 0
  fi
  log "labeled #$n with '$LABEL'"
}

cmd_unlabel() {
  local n="${1:?usage: issue.sh unlabel <n>}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "DRY_RUN — would remove label '$LABEL' from #$n"
    return 0
  fi
  gh issue edit "$n" --remove-label "$LABEL"
  log "removed '$LABEL' from #$n"
}

cmd_reset_mapping() {
  local n="${1:?usage: issue.sh reset-mapping <n> [tasks-file]}"
  assert_issue_number "$n"
  local tasks_file="${2:-}"
  local resolved=""
  local has_existing_file="0"
  if [ -z "$tasks_file" ]; then
    local -a candidates=()
    while IFS= read -r f; do
      candidates+=("$f")
    done < <(find_issue_mapping_files "$n")
    case "${#candidates[@]}" in
      0)
        resolved=""
        ;;
      1)
        resolved="${candidates[0]}"
        has_existing_file="1"
        ;;
      *)
        die "found multiple mapping files for issue #$n (${candidates[*]}). Re-run with explicit tasks-file."
        ;;
    esac
  else
    is_valid_issue_tasks_file "$n" "$tasks_file" ||
      die "explicit tasks-file must match tasks/issue-${n}-*.md (got: $tasks_file)"
    resolved="${tasks_file#./}"
    has_existing_file="1"
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    if [ "$has_existing_file" = "1" ] && [ -e "$resolved" ]; then
      log "DRY_RUN — would archive previous mapping file: $resolved"
    else
      log "DRY_RUN — no previous mapping file to archive for issue #$n (would still establish remap lock)"
    fi
    return 0
  fi
  if [ "$has_existing_file" = "1" ] && [ ! -e "$resolved" ]; then
    die "mapping file not found: $resolved"
  fi
  local lock_root lock_dir keep_lock
  lock_root=".git/map-issue-to-tasks"
  lock_dir="$lock_root/remap-${n}.lock.d"
  mkdir -p "$lock_root"
  mkdir "$lock_dir" 2>/dev/null || die "remap already in progress for issue #$n (lock exists: $lock_dir)"
  keep_lock="0"
  cleanup_remap_lock() {
    if [ "$keep_lock" != "1" ] && [ -d "$lock_dir" ]; then
      rm -rf -- "$lock_dir"
    fi
  }
  trap cleanup_remap_lock EXIT INT TERM
  printf 'pid=%s started=%s source=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$resolved" > "$lock_dir/meta.txt"
  local backup_dir backup
  if [ "$has_existing_file" = "1" ]; then
    backup_dir="tasks/.remap-backups/issue-$n"
    mkdir -p "$backup_dir"
    backup="$backup_dir/$(basename "$resolved").$(date -u +%Y%m%dT%H%M%SZ).bak"
    mv -- "$resolved" "$backup"
  fi
  keep_lock="1"
  trap - EXIT INT TERM
  if [ "$has_existing_file" = "1" ]; then
    log "archived previous mapping file: $resolved -> $backup (lock: $lock_dir)"
  else
    log "no prior mapping file found for issue #$n; established remap lock: $lock_dir"
  fi
}

cmd_unmapped() {
  gh issue list --state open --limit 1000 --search "(-label:\"$LABEL\") OR label:\"$MUST_REMAP_LABEL\"" \
    --json number,title,url --jq '.[] | "#\(.number)\t\(.title)\t\(.url)"'
}

case "${1:-}" in
create)
  shift
  cmd_create "$@"
  ;;
fetch)
  shift
  cmd_fetch "$@"
  ;;
json)
  shift
  cmd_json "$@"
  ;;
slug)
  shift
  cmd_slug "$@"
  ;;
comment)
  shift
  cmd_comment "$@"
  ;;
close)
  shift
  cmd_close "$@"
  ;;
label)
  shift
  cmd_label "$@"
  ;;
unlabel)
  shift
  cmd_unlabel "$@"
  ;;
reset-mapping)
  shift
  cmd_reset_mapping "$@"
  ;;
unmapped)
  shift
  cmd_unmapped "$@"
  ;;
*) die "usage: issue.sh {create|fetch|json|slug|comment|close|label|unlabel|reset-mapping|unmapped} ..." ;;
esac
