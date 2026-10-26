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
#   git config merge.graphify.driver '<path-to-this-script> %O %A %B %P'
# then reference it from .gitattributes via `merge=graphify` on the two
# paths (repo-standard scaffolds that part). See skills/repo-standard/SKILL.md
# for the exact command, including how to resolve <path-to-this-script> when
# this skill is installed under ~/.agents/skills/ rather than this checkout.
#
# Invoked by git as: graphify-merge-driver.sh %O %A %B %P
#   %O - ancestor's blob (temp file, unused)
#   %A - "ours" blob (temp file; git reads the resolution back from here)
#   %B - "theirs" blob (temp file, unused)
#   %P - path in the working tree, e.g. graphify-out/graph.json

set -euo pipefail

ours="$2"
path="$4"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# If some other file in this merge still has unresolved conflict markers,
# regenerating against a half-merged tree would bake garbage into the graph.
# Defer to "ours" instead and leave a note — the mandatory `graphify update .`
# gate step before push (see AGENTS.md) produces the correct file once the
# rest of the merge is actually resolved.
if git diff --name-only --diff-filter=U -- . | grep -qv '^graphify-out/'; then
  echo "[graphify-merge-driver] other conflicts still unresolved; keeping 'ours' as-is for $path — rerun 'graphify update .' once they're fixed." >&2
  exit 0
fi

if ! command -v graphify >/dev/null 2>&1; then
  echo "[graphify-merge-driver] graphify not on PATH; keeping 'ours' as-is for $path — rerun 'graphify update .' manually." >&2
  exit 0
fi

if ! graphify update . >/dev/null 2>&1; then
  echo "[graphify-merge-driver] 'graphify update .' failed; keeping 'ours' as-is for $path." >&2
  exit 0
fi

cp "$path" "$ours"
echo "[graphify-merge-driver] regenerated $path from the merged tree." >&2
