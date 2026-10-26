#!/usr/bin/env bash
# Git merge driver for graphify-out/{graph.json,GRAPH_REPORT.md}.
#
# Those two files are generated output of `graphify update .` over the rest
# of the repo, not hand-authored content. A textual 3-way merge answers the
# wrong question for them — two branches that each regenerated the graph
# from different code will produce a textual diff even when nothing about
# the graph's meaning actually conflicts. This driver regenerates the file
# from the already-merged working tree instead of diffing %O/%A/%B, which is
# the only resolution that's ever semantically correct for a derived
# artifact.
#
# Registration is local git config, not something a commit can ship (same
# reason graphify's own post-commit hook is documented, not auto-installed —
# see docs/superpowers/specs/2026-08-19-graphify-gitignore-standard-design.md).
# One-time per clone:
#   git config merge.graphify.driver "'<path-to-this-script>' %O %A %B %P"
# then reference it from .gitattributes via `merge=graphify` on the two
# paths (repo-standard scaffolds that part). See skills/repo-standard/SKILL.md
# for the exact command, including how to resolve <path-to-this-script> when
# this skill is installed under ~/.agents/skills/ rather than this checkout,
# and why the path itself must be quoted in the registered command.
#
# Invoked by git as: graphify-merge-driver.sh %O %A %B %P
#   %O - ancestor's blob (temp file, unused)
#   %A - "ours" blob (temp file; git reads the resolution back from here)
#   %B - "theirs" blob (temp file, unused)
#   %P - path in the working tree, e.g. graphify-out/graph.json
#
# Residual limitation (documented, not silently claimed away): this driver
# runs mid-merge, before `HEAD` has advanced to the eventual merge commit and
# without a documented guarantee that every *other* conflicting path (not
# just non-graphify ones, see below) has already been resolved by the time
# it's invoked for a given path. The guard below defers whenever another
# non-graphify path is still conflicted, which covers the common case (a
# real source conflict elsewhere in the same merge). It does not — and
# cannot, from inside a single per-path driver invocation — guarantee
# regeneration always happens against the fully-finalized merge result in
# every possible git-internal invocation order. The mandatory `graphify
# update .` gate step before push (see AGENTS.md) is the actual correctness
# backstop: run it again after any merge this driver touched, same as always.

set -euo pipefail

ours="$2"
path="$4"

# %P is attacker-influenced in a malicious/untrusted repo (it comes from the
# conflicted path git is resolving) — refuse anything that isn't exactly one
# of the two paths this driver is meant for, before it's used in any command.
# This also rules out an option-shaped value (e.g. `--target-directory=...`)
# reaching `cp`/`mv` as a flag instead of an operand.
case "$path" in
  graphify-out/graph.json | graphify-out/GRAPH_REPORT.md) ;;
  *)
    echo "[graphify-merge-driver] refusing unexpected path '$path' (not one of the two graphify-out artifacts); keeping 'ours' as-is." >&2
    exit 0
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# If some other (non-graphify) file in this merge still has unresolved
# conflict markers, regenerating against a half-merged tree would bake
# garbage into the graph. Defer to "ours" instead and leave a note — the
# mandatory `graphify update .` gate step before push produces the correct
# file once the rest of the merge is actually resolved.
#
# Capture the full `git diff` output into a variable first, then grep it
# (no -q) rather than piping straight into an early-exiting `grep -qv`: under
# `set -o pipefail`, `grep -qv` can close its end of the pipe as soon as it
# finds one match, sending `git diff` a SIGPIPE; pipefail then reports that
# non-zero (SIGPIPE-killed) exit instead of grep's own successful 0, which
# would flip this check to "no other conflicts" even when one exists.
unresolved="$(git diff --name-only --diff-filter=U -- .)"
if printf '%s\n' "$unresolved" | grep -v '^graphify-out/' | grep -q .; then
  echo "[graphify-merge-driver] other conflicts still unresolved; keeping 'ours' as-is for $path — rerun 'graphify update .' once they're fixed." >&2
  exit 0
fi

if ! command -v graphify >/dev/null 2>&1; then
  echo "[graphify-merge-driver] graphify not on PATH; keeping 'ours' as-is for $path — rerun 'graphify update .' manually." >&2
  exit 0
fi

# Back up both generated artifacts before regenerating: `graphify update .`
# can write one of the pair and then fail (or get killed) before writing the
# other, which would otherwise leave a mismatched graph/report pair on disk
# even though this driver reports success for `path` alone.
backup_dir="$(mktemp -d)"
trap 'rm -rf "$backup_dir"' EXIT
for f in graphify-out/graph.json graphify-out/GRAPH_REPORT.md; do
  [ -f "$f" ] && cp -- "$f" "$backup_dir/$(basename -- "$f")"
done

restore_backup() {
  for f in graphify-out/graph.json graphify-out/GRAPH_REPORT.md; do
    if [ -f "$backup_dir/$(basename -- "$f")" ]; then
      cp -- "$backup_dir/$(basename -- "$f")" "$f"
    fi
  done
}

if ! graphify update . >/dev/null 2>&1; then
  echo "[graphify-merge-driver] 'graphify update .' failed; restoring both artifacts and keeping 'ours' as-is for $path." >&2
  restore_backup
  exit 0
fi

if [ ! -f "$path" ]; then
  echo "[graphify-merge-driver] 'graphify update .' did not produce '$path'; restoring both artifacts and keeping 'ours' as-is." >&2
  restore_backup
  exit 0
fi

# Write %A atomically: copy the regenerated file to a temp file in the same
# directory as %A, then rename over it. A plain `cp -- "$path" "$ours"`
# truncates %A in place as it writes — if that copy is interrupted or fails
# partway, git would be left reading a truncated/partial file from %A and
# still treat this as a successful merge resolution.
ours_dir="$(dirname -- "$ours")"
tmp_ours="$(mktemp "$ours_dir/.graphify-merge-driver.XXXXXX")"
if ! cp -- "$path" "$tmp_ours"; then
  echo "[graphify-merge-driver] failed to stage regenerated $path; keeping 'ours' as-is." >&2
  rm -f -- "$tmp_ours"
  exit 0
fi
if ! mv -f -- "$tmp_ours" "$ours"; then
  echo "[graphify-merge-driver] failed to install regenerated $path into place; keeping 'ours' as-is." >&2
  rm -f -- "$tmp_ours"
  exit 0
fi
echo "[graphify-merge-driver] regenerated $path from the merged tree." >&2
