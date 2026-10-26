#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/repo-standard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain '$needle', got: $haystack"
}

run_expect_fail() {
  local dir="$1"
  shift
  set +e
  local out
  out="$(cd "$dir" && "$SCRIPT" "$@" 2>&1)"
  local code=$?
  set -e
  [[ $code -ne 0 ]] || fail "expected command to fail: $*"
  printf '%s' "$out"
}

run_expect_ok() {
  local dir="$1"
  shift
  (cd "$dir" && "$SCRIPT" "$@")
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

[[ -x "$SCRIPT" ]] || fail "script not executable: $SCRIPT"

# Missing repo.toml fails closed.
repo1="$TMP_ROOT/no-repo-toml"
mkdir -p "$repo1"
git -C "$repo1" init -q
out="$(run_expect_fail "$repo1" audit)"
assert_contains "$out" "repo.toml"
assert_contains "$out" "missing"

# Invalid stage fails closed.
repo2="$TMP_ROOT/invalid-stage"
mkdir -p "$repo2"
git -C "$repo2" init -q
cat > "$repo2/repo.toml" <<'EOF'
stage = "unknown"
EOF
out="$(run_expect_fail "$repo2" audit)"
assert_contains "$out" "invalid stage"

# Scaffold for prototype creates required files non-destructively.
repo3="$TMP_ROOT/prototype"
mkdir -p "$repo3"
git -C "$repo3" init -q
cat > "$repo3/repo.toml" <<'EOF'
stage = "prototype"
EOF
cat > "$repo3/AGENTS.md" <<'EOF'
SENTINEL CONTENT
EOF
run_expect_ok "$repo3" scaffold >/dev/null
[[ -f "$repo3/AGENTS.md" ]] || fail "AGENTS.md missing"
[[ -f "$repo3/README.md" ]] || fail "README.md not created"
[[ -f "$repo3/SPEC.md" ]] || fail "SPEC.md not created"
[[ -f "$repo3/.gitattributes" ]] || fail ".gitattributes not created"
[[ "$(cat "$repo3/AGENTS.md")" = "SENTINEL CONTENT" ]] || fail "AGENTS.md should not be overwritten"
out="$(run_expect_ok "$repo3" audit 2>&1)"
assert_contains "$out" "audit complete: compliant"

# .gitattributes behavior check: present-but-wrong content is flagged, not just presence.
repo6="$TMP_ROOT/bad-gitattributes"
mkdir -p "$repo6"
git -C "$repo6" init -q
cat > "$repo6/repo.toml" <<'EOF'
stage = "prototype"
EOF
cat > "$repo6/.gitignore" <<'EOF'
graphify-out/*
!graphify-out/graph.json
!graphify-out/GRAPH_REPORT.md
EOF
cat > "$repo6/.gitattributes" <<'EOF'
# missing the merge=graphify lines entirely
EOF
out="$(run_expect_fail "$repo6" audit)"
assert_contains "$out" ".gitattributes"
assert_contains "$out" "NON-COMPLIANT"

# .gitattributes behavior check: a local info/attributes override can't mask
# a missing/wrong declaration in the tracked file itself.
repo7="$TMP_ROOT/masked-gitattributes"
mkdir -p "$repo7"
git -C "$repo7" init -q
cat > "$repo7/repo.toml" <<'EOF'
stage = "prototype"
EOF
cat > "$repo7/.gitignore" <<'EOF'
graphify-out/*
!graphify-out/graph.json
!graphify-out/GRAPH_REPORT.md
EOF
cat > "$repo7/.gitattributes" <<'EOF'
# missing the real merge=graphify rules
EOF
mkdir -p "$repo7/.git/info"
cat > "$repo7/.git/info/attributes" <<'EOF'
graphify-out/graph.json merge=graphify
graphify-out/GRAPH_REPORT.md merge=graphify
EOF
out="$(run_expect_fail "$repo7" audit)"
assert_contains "$out" "tracked .gitattributes file itself doesn't declare it"

# Archived scaffold does not create frozen files.
repo4="$TMP_ROOT/archived"
mkdir -p "$repo4"
git -C "$repo4" init -q
cat > "$repo4/repo.toml" <<'EOF'
stage = "archived"
EOF
run_expect_ok "$repo4" scaffold >/dev/null
[[ ! -f "$repo4/AGENTS.md" ]] || fail "AGENTS.md should not be scaffolded for archived"
[[ ! -f "$repo4/README.md" ]] || fail "README.md should not be scaffolded for archived"

# Existing .specify without constitution gets repaired from reference.
repo5="$TMP_ROOT/in-progress-missing-constitution"
mkdir -p "$repo5/.specify/memory"
git -C "$repo5" init -q
cat > "$repo5/repo.toml" <<'EOF'
stage = "in-progress"
EOF
cat > "$repo5/.gitignore" <<'EOF'
# OS / editor
.DS_Store
*.swp

# graphify (knowledge graph) — allowlist: commit only graph.json + GRAPH_REPORT.md,
# ignore everything else graphify-out/ produces (exports, caches, bookkeeping)
graphify-out/*
!graphify-out/graph.json
!graphify-out/GRAPH_REPORT.md
EOF
ref="$TMP_ROOT/ref-specify"
mkdir -p "$ref/memory"
cat > "$ref/memory/constitution.md" <<'EOF'
# Constitution — reference
EOF
REPO_STANDARD_SPECIFY_REF="$ref" run_expect_ok "$repo5" scaffold >/dev/null
[[ -f "$repo5/.specify/memory/constitution.md" ]] || fail "constitution.md not restored from reference"

echo "ok"
