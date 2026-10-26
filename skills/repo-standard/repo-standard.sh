#!/usr/bin/env bash
set -euo pipefail

log()  { printf '\033[1;34m[repo-standard]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[repo-standard]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[repo-standard]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  die "usage: repo-standard.sh {audit|scaffold}"
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
case "$cmd" in
  audit|scaffold) ;;
  *) usage ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
repo_name="$(basename "$repo_root")"

repo_toml="$repo_root/repo.toml"
[ -f "$repo_toml" ] || die "repo.toml missing at repo root; declare stage first (prototype|in-progress|released|archived)."

stage="$(
  sed -nE 's/^[[:space:]]*stage[[:space:]]*=[[:space:]]*"([^"]+)".*$/\1/p' "$repo_toml" \
    | head -n 1
)"
[ -n "$stage" ] || die "repo.toml exists but stage is missing; expected: stage = \"prototype|in-progress|released|archived\"."
case "$stage" in
  prototype|in-progress|released|archived) ;;
  *) die "invalid stage '$stage' in repo.toml; expected one of: prototype, in-progress, released, archived." ;;
esac

requirement_for() {
  local path="$1"
  case "$path" in
    repo.toml|.gitignore|.gitattributes) echo "required" ;;
    AGENTS.md|README.md)
      if [ "$stage" = "archived" ]; then echo "required-frozen"; else echo "required"; fi
      ;;
    SPEC.md)
      if [ "$stage" = "prototype" ]; then echo "required"; else echo "none"; fi
      ;;
    specs/|specs/decisions/|.specify/|.specify/memory/constitution.md|tasks/)
      case "$stage" in
        in-progress|released) echo "required" ;;
        *) echo "none" ;;
      esac
      ;;
    CHANGELOG.md)
      case "$stage" in
        released) echo "required" ;;
        in-progress) echo "optional" ;;
        *) echo "none" ;;
      esac
      ;;
    SECURITY.md)
      case "$stage" in
        in-progress|released) echo "optional" ;;
        *) echo "none" ;;
      esac
      ;;
    *)
      echo "none"
      ;;
  esac
}

path_exists() {
  local path="$1"
  case "$path" in
    */) [ -d "$path" ] ;;
    *) [ -e "$path" ] ;;
  esac
}

check_graphify_gitignore_behavior() {
  local mismatches=0
  local path expected
  while IFS='|' read -r path expected; do
    set +e
    git check-ignore --no-index -q "$path"
    local code=$?
    set -e
    if [ "$code" -eq 128 ]; then
      die "audit could not run .gitignore behavior check (git check-ignore returned 128 for '$path')."
    fi
    if [ "$code" -ne "$expected" ]; then
      warn ".gitignore non-compliant for '$path': expected exit $expected, got $code"
      mismatches=$((mismatches + 1))
    fi
  done <<'EOF'
graphify-out/graph.html|0
graphify-out/some-bookkeeping-file|0
graphify-out/wiki/index.md|0
graphify-out/graph.json|1
graphify-out/GRAPH_REPORT.md|1
EOF
  [ "$mismatches" -eq 0 ]
}

check_graphify_gitattributes_behavior() {
  local path value mismatches=0
  for path in "graphify-out/graph.json" "graphify-out/GRAPH_REPORT.md"; do
    value="$(git check-attr merge -- "$path" | sed -E 's/^.*: merge: //')"
    if [ "$value" != "graphify" ]; then
      warn ".gitattributes non-compliant for '$path': expected merge=graphify, got '$value'"
      mismatches=$((mismatches + 1))
    fi
  done
  [ "$mismatches" -eq 0 ]
}

required_paths=(
  "repo.toml"
  ".gitignore"
  ".gitattributes"
  "AGENTS.md"
  "README.md"
  "SPEC.md"
  "specs/"
  "specs/decisions/"
  ".specify/"
  ".specify/memory/constitution.md"
  "tasks/"
  "CHANGELOG.md"
  "SECURITY.md"
)

missing_required=()
missing_required_frozen=()
noncompliant_required=()
missing_optional=()

run_audit() {
  log "stage: $stage"
  local path req
  for path in "${required_paths[@]}"; do
    req="$(requirement_for "$path")"
    [ "$req" != "none" ] || continue
    if ! path_exists "$path"; then
      case "$req" in
        required)
          missing_required+=("$path")
          warn "✗ $path [MISSING — required]"
          ;;
        required-frozen)
          missing_required_frozen+=("$path")
          warn "✗ $path [MISSING — required (frozen, scaffold will not create)]"
          ;;
        optional)
          missing_optional+=("$path")
          log "• $path [optional and absent]"
          ;;
      esac
      continue
    fi

    if [ "$path" = ".gitignore" ]; then
      if check_graphify_gitignore_behavior; then
        log "✓ $path [behavior-compliant]"
      else
        noncompliant_required+=("$path")
        warn "✗ $path [NON-COMPLIANT — graphify allowlist behavior mismatch]"
      fi
    elif [ "$path" = ".gitattributes" ]; then
      if check_graphify_gitattributes_behavior; then
        log "✓ $path [behavior-compliant]"
      else
        noncompliant_required+=("$path")
        warn "✗ $path [NON-COMPLIANT — graphify merge-driver attribute mismatch]"
      fi
    else
      log "✓ $path"
    fi
  done
}

write_file_if_missing() {
  local path="$1"
  local content="$2"
  if [ -e "$path" ]; then
    log "skipped (exists): $path"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$path"
  log "created: $path"
}

create_dot_gitignore() {
  write_file_if_missing ".gitignore" "# OS / editor
.DS_Store
*.swp

# graphify (knowledge graph) — allowlist: commit only graph.json + GRAPH_REPORT.md,
# ignore everything else graphify-out/ produces (exports, caches, bookkeeping)
graphify-out/*
!graphify-out/graph.json
!graphify-out/GRAPH_REPORT.md
"
}

create_dot_gitattributes() {
  write_file_if_missing ".gitattributes" "# graphify-out: generated knowledge-graph artifacts. A textual merge conflict
# here is meaningless — the files are a pure function of the rest of the repo —
# so route them through a custom merge driver that regenerates instead of
# diffing. One-time per clone, register the driver before this takes effect:
#   git config merge.graphify.driver '<skills-root>/repo-standard/graphify-merge-driver.sh %O %A %B %P'
# (skills-root defaults to ~/.agents/skills; see skills/repo-standard/SKILL.md)
graphify-out/graph.json merge=graphify
graphify-out/GRAPH_REPORT.md merge=graphify
"
}

create_agents() {
  if [ "$stage" = "prototype" ]; then
    write_file_if_missing "AGENTS.md" "# AGENTS.md

## Rules
<!-- TODO: key constraints for this repo (naming, architecture, non-goals) -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->

## Setup
<!-- TODO: how to get the repo running locally -->

## Validation
<!-- TODO: the quality gate command (tests, linter, formatter) -->
"
  else
    write_file_if_missing "AGENTS.md" "# AGENTS.md

## What's implemented
<!-- TODO: honest map of what works vs what's aspirational -->

## Rules & decisions
<!-- TODO: decided conventions, architecture rules, non-goals -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->

## Dev commands
<!-- TODO: build, test, lint, run -->

## Where things live
<!-- TODO: module map — what's in which directory -->
"
  fi
}

create_readme() {
  write_file_if_missing "README.md" "# $repo_name

<!-- TODO: one-line description -->

## Status
<!-- TODO: current status, known limitations, next steps -->
"
}

create_spec() {
  write_file_if_missing "SPEC.md" "# Spec

<!-- TODO: what this thing is meant to do; key decisions; what it is NOT -->
"
}

create_dir_with_gitkeep_if_missing() {
  local path="$1"
  if [ -d "$path" ]; then
    log "skipped (exists): $path"
    return 0
  fi
  mkdir -p "$path"
  : > "$path/.gitkeep"
  log "created: $path (with .gitkeep)"
}

create_changelog() {
  write_file_if_missing "CHANGELOG.md" "# Changelog

All notable changes to this project will be documented here.

<!-- TODO: follow Keep a Changelog format (https://keepachangelog.com) -->
"
}

copy_specify_from_reference() {
  local default_ref="$HOME/REPO/ME/iklo/.specify"
  local source="${REPO_STANDARD_SPECIFY_REF:-$default_ref}"
  [ -d "$source" ] || die "required .specify reference not found at '$source'. Set REPO_STANDARD_SPECIFY_REF to a valid iklo .specify source."
  if [ -e ".specify" ]; then
    log "skipped (exists): .specify/"
    return 0
  fi
  cp -R "$source" ".specify"
  log "created: .specify/ (copied from $source)"
}

ensure_constitution_from_reference() {
  local default_ref="$HOME/REPO/ME/iklo/.specify"
  local source="${REPO_STANDARD_SPECIFY_REF:-$default_ref}"
  local ref_constitution="$source/memory/constitution.md"
  [ -f "$ref_constitution" ] || die "required reference constitution missing at '$ref_constitution'."
  mkdir -p ".specify/memory"
  if [ -f ".specify/memory/constitution.md" ]; then
    log "skipped (exists): .specify/memory/constitution.md"
    return 0
  fi
  cp "$ref_constitution" ".specify/memory/constitution.md"
  log "created: .specify/memory/constitution.md (copied from $ref_constitution)"
}

if [ "$cmd" = "audit" ]; then
  run_audit
  total_failures=$(( ${#missing_required[@]} + ${#missing_required_frozen[@]} + ${#noncompliant_required[@]} ))
  if [ "$total_failures" -eq 0 ]; then
    log "audit complete: compliant for stage '$stage'"
    exit 0
  fi
  die "audit complete: $total_failures required check(s) failed."
fi

run_audit

created_any=0
create_required_path() {
  local path="$1"
  case "$path" in
    repo.toml) ;;
    .gitignore) create_dot_gitignore; created_any=1 ;;
    .gitattributes) create_dot_gitattributes; created_any=1 ;;
    AGENTS.md)
      if [ "$stage" = "archived" ]; then
        warn "skipped (frozen archived repo): AGENTS.md"
      else
        create_agents; created_any=1
      fi
      ;;
    README.md)
      if [ "$stage" = "archived" ]; then
        warn "skipped (frozen archived repo): README.md"
      else
        create_readme; created_any=1
      fi
      ;;
    SPEC.md) create_spec; created_any=1 ;;
    specs/) create_dir_with_gitkeep_if_missing "specs"; created_any=1 ;;
    specs/decisions/) create_dir_with_gitkeep_if_missing "specs/decisions"; created_any=1 ;;
    .specify/) copy_specify_from_reference; created_any=1 ;;
    .specify/memory/constitution.md) ;;
    tasks/) create_dir_with_gitkeep_if_missing "tasks"; created_any=1 ;;
    CHANGELOG.md) create_changelog; created_any=1 ;;
  esac
}

for path in "${missing_required[@]}"; do
  create_required_path "$path"
done

if ! path_exists ".specify/memory/constitution.md" && [ "$(requirement_for ".specify/memory/constitution.md")" = "required" ]; then
  if [ -e ".specify/" ]; then
    ensure_constitution_from_reference
  fi
fi

if [ "${#noncompliant_required[@]}" -gt 0 ]; then
  warn "scaffold does not overwrite existing non-compliant required files: ${noncompliant_required[*]}"
  warn "fix these manually, then re-run audit."
fi

if ! path_exists ".specify/memory/constitution.md" && [ "$(requirement_for ".specify/memory/constitution.md")" = "required" ]; then
  die "required file still missing after scaffold: .specify/memory/constitution.md"
fi

log "scaffold complete for stage '$stage'."
if [ "$created_any" -eq 0 ]; then
  log "nothing created."
fi
