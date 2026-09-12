#!/usr/bin/env bash
# pr.sh — safe git/gh plumbing for the pull-request-process skill.
#
# Language-agnostic: it does NOT run any project quality gate. Run the gate
# yourself (per the project's AGENTS.md) BEFORE `pr.sh push`.
#
# Subcommands:
#   start <branch>        create <branch> in a FRESH git worktree under a centralized root
#                         (default: ~/.local/share/copilot-worktrees/<repo-name>/<branch>;
#                         override with PR_WORKTREE_ROOT=<dir>) and print its path —
#                         cd there for every remaining step.
#   push <branch>         requires REVIEWED=1 (run a requesting-code-review pass and fix what it
#                         flags first); then explicit-refspec push + verify branch landed &
#                         BASE didn't move
#   open <title> [body]   gh pr create --base BASE (body = path to a markdown file), print URL, STOP
#   threads <pr>          list UNRESOLVED review threads on a PR (work them one by one)
#   reviews <pr>           list PR-LEVEL review comments (the "Overall Comments" a bot leaves on
#                          the review itself, not on a line — these have no thread and can't be
#                          replied to with `reply`). Pulls out each bot's "Prompt for AI Agent(s)"
#                          block when present, since that's the actionable part.
#   checks <pr>            list CI check results (name, pass/fail/pending bucket, workflow,
#                          description, link) — this is how SonarQube/SonarCloud and any other
#                          third-party analyzer surface here: they post a check with a link to
#                          their own web UI rather than GitHub review comments, so `threads`/
#                          `reviews` alone would miss them entirely.
#   comment <pr> <body>   post a general/top-level PR comment, not tied to any review thread
#                         (body = inline string or path to a markdown file); use this to
#                         respond to PR-level reviews (from `reviews`) that have no thread.
#                         ALWAYS use quote-reply format so it is clear which part you address:
#                           pr.sh comment 27 "> quoted text from the review
#                           Your response here."
#   comment-delete <id>   delete a general/top-level PR comment by its numeric id (from the
#                         URL printed by `comment`, or an id you already have) — the correction
#                         path when a `comment` needs fixing, since GitHub comments can't be
#                         edited via `gh pr comment`
#   reply <pr> <id> <body> reply to a review thread comment (body = inline string or path to a markdown file)
#   cleanup               once a task is FULLY done (PR merged or abandoned — not right after
#                         opening; the review loop still needs this worktree): verify it's
#                         pristine, remove it, and print the main checkout's path to cd back
#                         into. Only ever removes a worktree under PR_WORKTREE_ROOT (or the
#                         default centralized root), plus backward-compat support for the
#                         legacy <repo>-worktrees sibling path. NON-DESTRUCTIVE — if dirty
#                         (including gitignored files the removal would otherwise silently
#                         take with it) it reports and stops (never discards).
#
# Env:
#   BASE                  base branch (default: main). The skill supplies this from the project's docs.
#   DRAFT                 set DRAFT=1 to open the PR as a draft (bots typically don't review drafts).
#   DRY_RUN               set DRY_RUN=1 so `open` prints the gh command instead of creating the PR.
#   FORCE_REMOVE_IGNORED  set to 1 to let `cleanup` remove a worktree that still has gitignored
#                         files in it (otherwise it refuses, since removal deletes the whole
#                         directory — build artifacts are fine to lose, a stray .env isn't).
#   PR_WORKTREE_ROOT      base directory under which `start` creates task worktrees; a
#                         subdirectory named after the repo is appended automatically
#                         (default: ~/.local/share/copilot-worktrees). Must be an
#                         absolute path. Override to put worktrees on a different disk or
#                         mount point. Never set this to a directory under ~/REPO/ME (or
#                         wherever your personal repo checkouts live) — that defeats the
#                         whole purpose of this default.
#   REVIEWED              set to 1 to confirm a requesting-code-review pass has been run on the
#                         changes and anything it flagged has been addressed. `push` refuses to
#                         run without it — self-review before push catches what bots would flag
#                         anyway, just before it's public on the PR instead of after.
#   PR_BOT_DOPPLER_PROJECT / PR_BOT_DOPPLER_CONFIG  Doppler project/config holding the agent
#                         identity secrets below (default: homelab/dev). Every gh call and every
#                         commit this script makes uses this identity, NEVER whatever personal
#                         `gh auth`/git identity happens to be ambient — that's what silently
#                         leaked a personal account into commits/PR comments before this existed.
#                         Requires GHUB_AGENT_PATC (a gh token), GHUB_AGENT_USERNAME, and
#                         GHUB_AGENT_EMAIL to exist in that Doppler config. Fetched fresh on
#                         every invocation (never cached to disk); if Doppler/the secrets aren't
#                         reachable, every subcommand dies loudly rather than falling back to
#                         the ambient identity.
set -euo pipefail

BASE="${BASE:-main}"
log()  { printf '\033[1;34m[pr]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pr] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[pr] %s\033[0m\n' "$*" >&2; exit 1; }

# --- Agent identity enforcement -----------------------------------------
# GH_TOKEN, once exported, overrides gh's own ambient `gh auth` active
# account for every `gh` call this script (and anything it spawns) makes —
# without touching the user's own global `gh auth` state at all. Git commit
# identity is handled separately in cmd_start, scoped to just that worktree.
PR_BOT_DOPPLER_PROJECT="${PR_BOT_DOPPLER_PROJECT:-homelab}"
PR_BOT_DOPPLER_CONFIG="${PR_BOT_DOPPLER_CONFIG:-dev}"

_bot_secret() {
  # `|| true`: under `set -e`, a failed command substitution in an assignment
  # (e.g. `x="$(_bot_secret ...)"`) would otherwise kill the script right here,
  # silently, before the caller's own `[ -n "$x" ] || die ...` check ever runs.
  doppler secrets get "$1" --plain --project "$PR_BOT_DOPPLER_PROJECT" --config "$PR_BOT_DOPPLER_CONFIG" 2>/dev/null || true
}

GH_TOKEN="$(_bot_secret GHUB_AGENT_PATC)"
[ -n "$GH_TOKEN" ] || die "could not fetch GHUB_AGENT_PATC from Doppler ($PR_BOT_DOPPLER_PROJECT/$PR_BOT_DOPPLER_CONFIG) — refusing to fall back to the ambient 'gh auth' identity. Check Doppler access, or override PR_BOT_DOPPLER_PROJECT/PR_BOT_DOPPLER_CONFIG."
export GH_TOKEN
BOT_NAME="$(_bot_secret GHUB_AGENT_USERNAME)"
BOT_EMAIL="$(_bot_secret GHUB_AGENT_EMAIL)"
[ -n "$BOT_NAME" ] && [ -n "$BOT_EMAIL" ] || die "could not fetch GHUB_AGENT_USERNAME/GHUB_AGENT_EMAIL from Doppler ($PR_BOT_DOPPLER_PROJECT/$PR_BOT_DOPPLER_CONFIG) — refusing to guess a commit identity."

remote_sha() { git ls-remote --heads origin "$1" 2>/dev/null | awk '{print $1}'; }

# Resolves the TRUE main checkout's root, regardless of which worktree (if any)
# we're currently invoked from. The common git dir is shared across every
# worktree of a repo and always resolves to <main-checkout>/.git in a standard
# (non-bare) setup — unlike scanning `git worktree list` for a worktree with a
# particular branch checked out, this doesn't break the moment nothing has
# $BASE checked out (e.g. the shared checkout is on some other branch).
main_checkout_root() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir)"
  common_dir="$(cd "$common_dir" && pwd)" # normalize to an absolute path
  dirname "$common_dir"
}

# Resolves (and validates) the centralized worktree base root.
# Normalizes the path so start/cleanup always compare canonical forms —
# trailing slashes and `..` components in PR_WORKTREE_ROOT would otherwise
# make cleanup reject a worktree that start just created.
# Validates:
#   1. Result is absolute (rejects relative PR_WORKTREE_ROOT).
#   2. Result is not under main_root (rejects dangerous overrides that place
#      task worktrees inside the personal checkout).
# The per-repo subdirectory (<repo-name>) is NOT appended here; callers do that
# themselves so the raw base_root can be validated against main_root independently.
_worktree_base_root() {
  local main_root="$1"
  local raw="${PR_WORKTREE_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/copilot-worktrees}"
  # Validate the raw value BEFORE resolving — a relative path looks absolute after
  # mkdir+cd since it's resolved relative to cwd, hiding the misconfiguration.
  case "$raw" in
    /*) ;;
    *) die "PR_WORKTREE_ROOT ('$raw') must be an absolute path; got a relative value" ;;
  esac
  # Normalize: resolve symlinks / redundant components so start and cleanup
  # always compare the same canonical form — trailing slashes or .. components
  # in PR_WORKTREE_ROOT would otherwise make cleanup reject a worktree start created.
  local resolved
  mkdir -p "$raw" 2>/dev/null || true
  if [ -d "$raw" ]; then
    resolved="$(cd "$raw" && pwd)"
  else
    resolved="$raw"
  fi
  # Must not be under (or equal to) main_root — that would put task worktrees
  # inside the personal checkout, defeating the purpose of this change.
  case "$resolved/" in
    "$main_root/"*) die "PR_WORKTREE_ROOT ('$resolved') is inside the main checkout ('$main_root'); choose a path outside your personal repo directory" ;;
  esac
  printf '%s' "$resolved"
}

cmd_start() {
  local br="${1:?usage: pr.sh start <branch>}"
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo"
  # Validate BEFORE deriving wt_path from it — a ref like `../evil` would
  # otherwise let `dirname`/`mkdir -p` escape $wt_root and create stray
  # directories before `git worktree add` itself ever gets a chance to
  # reject the ref.
  git check-ref-format --branch "$br" >/dev/null 2>&1 || die "'$br' is not a valid branch name"
  git show-ref --verify --quiet "refs/heads/$br" && die "branch '$br' already exists locally"
  log "fetching origin/$BASE"; git fetch origin "$BASE"
  local main_root wt_root wt_path
  main_root="$(main_checkout_root)"
  # Centralized worktree root: ~/.local/share/copilot-worktrees/<repo-name>
  # Override with PR_WORKTREE_ROOT. Validated (absolute, not under main_root) by helper.
  # See issue #14 — this avoids placing worktrees alongside personal repo checkouts.
  local base_root repo_name
  base_root="$(_worktree_base_root "$main_root")"
  repo_name="$(basename "$main_root")"
  wt_root="$base_root/$repo_name"
  wt_path="$wt_root/$br"
  [ -e "$wt_path" ] && die "worktree path '$wt_path' already exists"
  mkdir -p "$(dirname "$wt_path")"
  # --no-track: branch off origin/$BASE's tip WITHOUT setting up tracking against it.
  # Without this, `branch.autoSetupMerge` (on by default) would make the new branch
  # track origin/$BASE since the start point is a remote-tracking ref — then a bare
  # `git push` (push.default=upstream) would write straight to origin/$BASE, bypassing
  # the whole PR/review flow. This is also why we never touch the shared checkout's
  # own local $BASE branch here: a fresh worktree branching straight off origin/$BASE
  # needs no local $BASE ref update at all, and can't collide with whatever the shared
  # checkout (or another worktree) currently has checked out or uncommitted.
  git worktree add --no-track -b "$br" "$wt_path" "origin/$BASE" >/dev/null
  # Scope the agent's commit identity to JUST this task's worktree, via
  # `--worktree` config (needs extensions.worktreeConfig, a one-time,
  # harmless repo-level flag enabling per-worktree config to exist at all —
  # it does NOT move or overwrite anything already in the shared config).
  # This is deliberate: setting user.name/user.email the normal (shared) way
  # would silently change the identity for every OTHER worktree of this
  # repo too, including the main checkout the user does their own personal
  # commits from.
  git -C "$wt_path" config extensions.worktreeConfig true
  git -C "$wt_path" config --worktree user.name "$BOT_NAME"
  git -C "$wt_path" config --worktree user.email "$BOT_EMAIL"
  log "worktree created at '$wt_path' on new branch '$br' (off up-to-date origin/$BASE)."
  log "commit identity set to '$BOT_NAME <$BOT_EMAIL>' for this worktree only."
  log "cd into it now — every remaining step (implement, gate, push, open, review loop) runs from there:"
  log "  cd '$wt_path'"
}

cmd_push() {
  local br="${1:?usage: pr.sh push <branch>}"
  [ "${REVIEWED:-0}" = "1" ] || die "REVIEWED=1 not set — run a requesting-code-review pass, fix what it flags, then: REVIEWED=1 pr.sh push $br"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "$br" ] || warn "HEAD is not '$br' (pushing HEAD anyway)"
  local base_before; base_before="$(remote_sha "$BASE")"
  log "pushing HEAD -> origin/$br (explicit refspec)"
  git push origin "HEAD:refs/heads/$br"
  # Verify: branch exists on remote, and BASE did NOT advance (the accident this guards against).
  [ -n "$(remote_sha "$br")" ] || die "branch '$br' not found on origin after push"
  local base_after; base_after="$(remote_sha "$BASE")"
  if [ "$base_before" != "$base_after" ]; then
    die "origin/$BASE moved during push ($base_before -> $base_after) — investigate immediately"
  fi
  log "ok: origin/$br updated; origin/$BASE unchanged ($base_after)"
}

cmd_open() {
  local title="${1:?usage: pr.sh open <title> [body-file]}"; local body="${2:-}"
  local br; br="$(git rev-parse --abbrev-ref HEAD)"
  local args=(pr create --base "$BASE" --head "$br" --title "$title")
  [ "${DRAFT:-0}" = "1" ] && args+=(--draft)
  if [ -n "$body" ]; then [ -f "$body" ] || die "body file not found: $body"; args+=(--body-file "$body"); else args+=(--body ""); fi
  if [ "${DRY_RUN:-0}" = "1" ]; then log "DRY_RUN — would run: gh ${args[*]}"; return 0; fi
  log "gh ${args[*]}"
  local url; url="$(gh "${args[@]}")"
  log "PR opened: $url"
  warn "STOP: do not merge or mark ready — bots/maintainer review and merge."
}

cmd_comment() {
  local pr="${1:?usage: pr.sh comment <pr-number> <body>}"
  local body="${2:?usage: pr.sh comment <pr-number> <body>}"
  # Accept body as a file path or inline string, matching cmd_reply's convention.
  local body_arg
  if [ -f "$body" ]; then
    body_arg="$(cat "$body")"
  else
    body_arg="$body"
  fi
  # GitHub Markdown: a line immediately after a blockquote (>) with no blank line
  # is rendered as part of the quote. Ensure every quote block is followed by a
  # blank line so the response text appears outside the quote.
  body_arg="$(printf '%s' "$body_arg" | awk '
    /^>/ { in_quote=1; print; next }
    in_quote && /^[^>]/ && !/^[[:space:]]*$/ { print ""; in_quote=0 }
    { in_quote=0; print }
  ')"
  local url
  url="$(gh pr comment "$pr" --body "$body_arg")"
  log "comment posted: $url"
}

cmd_close() {
  local pr="${1:?usage: pr.sh close <pr-number> [comment]}"
  local body="${2:-}"
  if [ -n "$body" ]; then
    local body_arg
    if [ -f "$body" ]; then body_arg="$(cat "$body")"; else body_arg="$body"; fi
    gh pr comment "$pr" --body "$body_arg" > /dev/null
  fi
  gh pr close "$pr"
  log "PR #$pr closed"
}

cmd_comment_delete() {
  local id="${1:?usage: pr.sh comment-delete <comment-id>}"
  local nwo owner repo; nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  owner="${nwo%%/*}"; repo="${nwo##*/}"
  gh api -X DELETE "repos/$owner/$repo/issues/comments/$id"
  log "comment $id deleted"
}

cmd_reply() {
  local pr="${1:?usage: pr.sh reply <pr-number> <comment-id> <body>}"
  local comment_id="${2:?usage: pr.sh reply <pr-number> <comment-id> <body>}"
  local body="${3:?usage: pr.sh reply <pr-number> <comment-id> <body>}"
  local nwo owner repo; nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  owner="${nwo%%/*}"; repo="${nwo##*/}"
  # Accept body as a file path or inline string.
  local body_arg
  if [ -f "$body" ]; then
    body_arg="$(cat "$body")"
  else
    body_arg="$body"
  fi
  local url
  url="$(gh api "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
    -f body="$body_arg" | jq -r '.html_url')"
  log "reply posted: $url"
}

cmd_threads() {
  local pr="${1:?usage: pr.sh threads <pr-number>}"
  local nwo owner repo; nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  owner="${nwo%%/*}"; repo="${nwo##*/}"
  gh api graphql -F owner="$owner" -F repo="$repo" -F pr="$pr" -f query='
    query($owner:String!,$repo:String!,$pr:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$pr){
          reviewThreads(first:100){ nodes{
            isResolved isOutdated path line
            comments(first:1){ nodes{ databaseId author{login} body } }
          } }
        }
      }
    }' --jq '
      .data.repository.pullRequest.reviewThreads.nodes
      | map(select(.isResolved==false))
      | if length==0 then "No unresolved review threads."
        else (.[] | "── \(.path):\(.line // "?") \(if .isOutdated then "(outdated)" else "" end)\n   reply with: pr.sh reply '"$pr"' \(.comments.nodes[0].databaseId) \"<body>\"\n@\(.comments.nodes[0].author.login // "?"): \(.comments.nodes[0].body // "" | gsub("\n";" ") | .[0:280])")
        end'
}

cmd_reviews() {
  local pr="${1:?usage: pr.sh reviews <pr-number>}"
  local nwo owner repo; nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  owner="${nwo%%/*}"; repo="${nwo##*/}"
  local reviews_json
  reviews_json="$(gh api "repos/$owner/$repo/pulls/$pr/reviews" --paginate)"
  local count
  count="$(jq '[.[] | select((.body // "") != "")] | length' <<<"$reviews_json")"
  if [ "$count" = "0" ]; then
    log "no PR-level review comments with a body."
    return 0
  fi
  jq -c '.[] | select((.body // "") != "")' <<<"$reviews_json" | while IFS= read -r review; do
    local login state id body prompt
    login="$(jq -r '.user.login' <<<"$review")"
    state="$(jq -r '.state' <<<"$review")"
    id="$(jq -r '.id' <<<"$review")"
    body="$(jq -r '.body' <<<"$review")"
    echo "── $login [$state] (review $id)"
    # Extract the fenced block following any "Prompt for AI Agent(s)" mention. Bots vary fence
    # style (~~~markdown vs ```text) and casing, so match generically on both.
    prompt="$(awk '
      BEGIN{seen=0; infence=0}
      { line=$0; ltmp=tolower(line); if (ltmp ~ /prompt for ai agent/) { seen=1 } }
      seen && !infence && (line ~ /^(```+|~~~+)/) { infence=1; next }
      infence && (line ~ /^(```+|~~~+)[ \t]*$/) { infence=0; exit }
      infence { print }
    ' <<<"$body")"
    if [ -n "$prompt" ]; then
      echo "  prompt:"
      echo "$prompt" | sed 's/^/    /'
    else
      echo "  $(echo "$body" | tr '\n' ' ' | cut -c1-280)"
    fi
    echo
  done
  echo "[pr] reply to these with: pr.sh comment $pr '<body>'"
  echo "[pr] use quote-reply format so it's clear which part you're addressing:"
  echo "[pr]   pr.sh comment $pr '> quoted text from review"
  echo "[pr]   Your response here.'"
}

cmd_checks() {
  local pr="${1:?usage: pr.sh checks <pr-number>}"
  # `gh pr checks` exits non-zero for non-passing states (8 = pending,
  # nonzero on fail too) even though the JSON it printed is exactly what we
  # want — capture output and status separately so `set -e` doesn't kill
  # the script on a merely-informative "some checks failed/pending".
  local json rc
  json="$(gh pr checks "$pr" --json name,bucket,description,link,workflow 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 8 ]; then
    echo "$json"
    return "$rc"
  fi
  local count
  count="$(jq 'length' <<<"$json" 2>/dev/null || echo 0)"
  if [ "$count" = "0" ]; then
    log "no CI checks reported for PR $pr."
    return 0
  fi
  # SonarQube/SonarCloud (and most third-party analyzers) post their
  # findings on their own web UI, not as GitHub review comments — this
  # surfaces the check's own link (and any inline description GitHub does
  # have) instead of leaving those checks invisible to the review loop.
  jq -r '.[] | "── \(.name) [\(.bucket)] \(.workflow)\n   \(if (.description // "") != "" then .description else "(no inline description — see link)" end)\n   \(.link)\n"' <<<"$json"
}

cmd_cleanup() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo"
  # git status ignores gitignored build artifacts, so a non-empty result is real
  # uncommitted/untracked work — surface it and STOP rather than discard anything.
  if [ -n "$(git status --porcelain)" ]; then
    warn "worktree NOT pristine — leaving '$(pwd)' (branch '$(git rev-parse --abbrev-ref HEAD)') as-is."
    warn "resolve these (commit, stash, or remove) then re-run 'pr.sh cleanup':"
    git status --short >&2
    return 1
  fi
  log "worktree pristine"
  local wt_path main_root wt_root legacy_wt_root
  wt_path="$(git rev-parse --show-toplevel)"
  main_root="$(main_checkout_root)"
  # Centralized root (matches cmd_start via shared helper).
  local base_root repo_name
  base_root="$(_worktree_base_root "$main_root")"
  repo_name="$(basename "$main_root")"
  wt_root="$base_root/$repo_name"
  # Legacy root: <main-checkout>-worktrees (pre-issue-14 layout). Accepted for
  # backward-compat so worktrees created before the new default still clean up safely.
  legacy_wt_root="${main_root}-worktrees"
  [ "$wt_path" != "$main_root" ] || die "refusing to remove '$wt_path' — it IS the main checkout, not a task worktree"
  # Only ever remove worktrees under a sanctioned root — never unrelated worktrees.
  case "$wt_path" in
    "$wt_root"/*)        ;;
    "$legacy_wt_root"/*) ;;
    *) die "refusing to remove '$wt_path' — it's not under '$wt_root' (or legacy '$legacy_wt_root'), so 'pr.sh start' didn't create it; if you're sure, remove it manually with 'git worktree remove'" ;;
  esac
  # `git worktree remove` deletes the WHOLE directory, including anything
  # gitignored — unlike the old git-switch-in-place cleanup, which left
  # ignored files sitting on disk untouched. A build-artifact directory
  # (target/, node_modules/) disappearing is fine; a stray .env or local DB
  # someone stashed there is not. Refuse by default if any ignored path is
  # present; FORCE_REMOVE_IGNORED=1 opts in explicitly.
  local ignored
  ignored="$(git status --porcelain --ignored=matching | sed -n 's/^!! //p')"
  if [ -n "$ignored" ] && [ "${FORCE_REMOVE_IGNORED:-0}" != "1" ]; then
    warn "worktree has gitignored files 'git worktree remove' would delete along with the directory:"
    echo "$ignored" | sed 's/^/  /' >&2
    warn "if these are disposable build artifacts, re-run with FORCE_REMOVE_IGNORED=1 to remove anyway."
    warn "if not, move/copy anything you need out first."
    return 1
  fi
  # Point --git-dir directly at the shared git directory rather than running
  # `git -C <some-other-worktree>` — this works with no OTHER worktree needing
  # to exist in any particular state (in particular, no worktree needs $BASE
  # checked out), and still works even though the invoking shell's cwd is
  # literally inside the directory being removed.
  local common_dir; common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
  git --git-dir="$common_dir" worktree remove "$wt_path" \
    || die "could not auto-remove worktree at '$wt_path' — remove manually: git --git-dir='$common_dir' worktree remove '$wt_path'"
  # Slash-named branches (e.g. feat/my-thing) leave a now-empty parent dir behind
  # under the worktrees root — prune upward while empty, stopping at wt_root (or
  # legacy_wt_root for old worktrees).
  local parent stop_at
  parent="$(dirname "$wt_path")"
  case "$wt_path" in
    "$wt_root"/*)        stop_at="$wt_root" ;;
    "$legacy_wt_root"/*) stop_at="$legacy_wt_root" ;;
    *) stop_at="$wt_root" ;;
  esac
  while [ "$parent" != "$stop_at" ] && [ -d "$parent" ] && [ -z "$(ls -A "$parent" 2>/dev/null)" ]; do
    rmdir "$parent"
    parent="$(dirname "$parent")"
  done
  log "worktree removed. cd back into the main checkout for the next task:"
  log "  cd '$main_root'"
}

case "${1:-}" in
  start)   shift; cmd_start "$@" ;;
  push)    shift; cmd_push "$@" ;;
  open)    shift; cmd_open "$@" ;;
  threads) shift; cmd_threads "$@" ;;
  reviews) shift; cmd_reviews "$@" ;;
  checks)  shift; cmd_checks "$@" ;;
  comment) shift; cmd_comment "$@" ;;
  close)   shift; cmd_close "$@" ;;
  comment-delete) shift; cmd_comment_delete "$@" ;;
  reply)   shift; cmd_reply "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *) die "usage: pr.sh {start|push|open|threads|reviews|checks|comment|close|comment-delete|reply|cleanup} ...  (BASE=$BASE)" ;;
esac
