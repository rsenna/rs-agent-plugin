# graphify-out merge conflicts: a regenerate-not-merge driver

## Context

`graphify-out/graph.json` and `graphify-out/GRAPH_REPORT.md` are committed
per the allowlist established in
[the gitignore standard design](2026-08-19-graphify-gitignore-standard-design.md),
because they're the real output a fresh clone or GitHub browse should have.
In practice, across every repo that adopted the standard, those two files
conflict on almost every merge/rebase that touches more than one branch:
two branches that each ran `graphify update .` on different code produce
textually different output even when nothing about the graph's *meaning*
diverged — the ordering, extraction metadata, and incremental state baked
into the file are all a function of exactly what each branch's checkout
looked like when the tool ran, not just the "real" content.

A plain 3-way text merge is the wrong operation here: it's trying to
reconcile two renderings of a derived artifact as if they were independent
edits. The actually-correct resolution is always the same — regenerate the
file from whatever the rest of the merge settled on — and that resolution
never depends on what either side's diff said.

## Decision

Route both files through a git **custom merge driver** (`.gitattributes` +
`merge.<name>.driver` config) that ignores the three-way diff entirely and
instead reruns `graphify update .` against the already-merged working tree,
using that output as the resolution. This generalizes the same principle
`fix-mapped-issue`/`pull-request-process` already apply to the committed
graph via the mandatory pre-push `graphify update .` gate step: the graph is
never hand-edited, so neither is its merge.

Implementation lives in this repo (`rs-agent-plugin`), same as the
`.gitignore` standard, because `repo-standard` is this repo's
cross-repo-shipping mechanism:

- `skills/repo-standard/graphify-merge-driver.sh` — the driver script.
- `.gitattributes` added as a new `repo-standard` required path, same
  four-stage tier as `.gitignore`, scaffolded with the `merge=graphify`
  lines for both paths.
- `repo-standard audit` verifies the attribute *declares* the driver
  (`git check-attr merge -- <path>` reports `graphify` for both files) —
  behavioral, not textual, same reasoning as the existing `.gitignore`
  check (a commented-out line or an overriding rule further down the file
  would pass a grep while being non-functional).

### Why a driver, not `-X ours`/`-X theirs`

`-X ours`/`-X theirs` are whole-merge strategy options, not per-path. The
moment the same merge/rebase also touches a real, unrelated conflict
elsewhere, they'd silently resolve that one too by just picking a side —
unacceptable. `.gitattributes`' `merge=<driver>` is the only git mechanism
that's scoped to specific paths.

### Why regenerate rather than just picking a side

Picking "ours" or "theirs" outright (e.g. via the builtin `merge=ours`
driver) would be cheaper to set up, but it's answering a different
question: it keeps *a* valid graph, not *the correct* one for the code that
actually resulted from the merge. Since the generation cost
(`graphify update .`, AST-only, no LLM calls per
[the gitignore design doc](2026-08-19-graphify-gitignore-standard-design.md#what-is-committed-vs-ignored-in-graphify-out))
is cheap, there's no reason to settle for "a side" when "the right answer"
costs the same to produce.

### Known limitation: driver registration is local, not shippable

Same constraint already called out for graphify's own post-commit hook in
the gitignore design doc's "Out of scope" section: `git config
merge.graphify.driver '...'` is local repository config, not something a
commit can carry to every clone. `.gitattributes` can declare *that* a path
uses the `graphify` driver; it can't make that driver exist on a machine
that hasn't registered it. Without registration, git falls back to its
default 3-way text merge for these paths — i.e. exactly the conflict this
design exists to remove — so the one-time setup command (documented in
`skills/repo-standard/SKILL.md` and this repo's `README.md`) is a real
prerequisite, not a nice-to-have. This is accepted for the same reason the
hook was: it's genuinely local machine state, and a PR can't install it on
someone else's clone.

### Safety: never produce a worse outcome than before

The driver always exits `0` — a merge driver that exits non-zero leaves the
path conflicted, and this design never wants to introduce a *new* way for a
merge to fail. If `%P` isn't exactly one of the two expected artifact paths,
`graphify` isn't on `PATH`, `graphify update .` itself fails, or some
*other* file in the same merge is still unresolved (which would mean
regenerating against a half-merged tree), the driver falls back to leaving
`ours` unchanged and prints a note to rerun `graphify update .` manually.
The mandatory pre-push gate step already requires that rerun before any PR
ships, so a deferred case here is never silently wrong for long — just not
auto-resolved in that one edge case.

Three further hardening details, each closing a gap found in review of the
first version of this driver:

- **`%P` is validated before use, not trusted.** It names the path git is
  resolving, which in an untrusted/malicious repository could be made
  option-shaped (e.g. `--target-directory=...`) instead of one of the two
  real artifact paths. The driver rejects anything else outright, before it
  ever reaches `cp`/`mv`, rather than relying on those commands' own
  argument parsing to do the right thing with attacker-influenced input.
- **Writing `%A` is atomic.** The first version copied the regenerated file
  directly over `%A` (`cp -- "$path" "$ours"`), which truncates `%A` in
  place as it writes — a failure partway through (disk full, permissions)
  would leave git reading a partial file back as a "successful" resolution.
  The driver now copies to a temp file next to `%A` and renames over it, so
  `%A` is either the old content or the new content, never a partial write.
- **Both generated artifacts are backed up before regenerating, and
  restored together on any failure.** `graphify update .` can write one of
  `graph.json`/`GRAPH_REPORT.md` and then fail before writing the other —
  without a backup, that would leave a mismatched pair on disk even though
  the driver only reports success or failure for the single path git asked
  it to resolve.

**What this driver does *not* fully guarantee, and why:** it runs mid-merge
— before `HEAD` has advanced to the eventual merge commit, and without a
documented git-internal guarantee that invocation order across multiple
custom-merge-driver paths in the same merge always reflects the fully
finalized conflict set at the moment any single one of them runs. The
"other conflicts still unresolved" guard (checking for non-`graphify-out/`
paths still in conflict) covers the common case — a real source conflict
elsewhere in the same merge — but a per-path driver invocation cannot, by
construction, prove it is being run after every other path's resolution has
landed in every possible git-internal ordering. This is not treated as
fully solved here: the actual correctness backstop remains the mandatory
`graphify update .` gate step before push, which this design doesn't
replace, only reduces how often a human needs to invoke by hand.

A second, distinct gap in the same spirit: a merge driver only runs when
git considers a path **conflicted** — modified differently on both sides.
If only one branch touched `graph.json`/`GRAPH_REPORT.md` (because only
that branch's source changes happened to move the graph, or the other side
simply didn't run `graphify update .` before committing), git treats that
as a normal, non-conflicting change and takes it as-is — the driver never
fires, so it can't catch a graph that's now stale relative to the rest of
the *merged* tree (which may include source changes from the side that
never touched the graph file). This is inherent to how merge drivers work
(they resolve conflicts, they don't audit every merge for staleness) and
isn't something a per-path driver can address at all — a true fix would be
a `post-merge` hook that unconditionally reruns `graphify update .` after
*every* merge regardless of conflict status, which is exactly the kind of
local-machine-state hook this design already declines to auto-install (see
"Out of scope"). The mandatory pre-push gate step is, again, what actually
closes this gap in practice.

## Rollout in this repo

- `.gitattributes` added at repo root with the two `merge=graphify` lines.
- `skills/repo-standard/graphify-merge-driver.sh` added.
- `skills/repo-standard/SKILL.md`, `repo-standard.sh`, and
  `test-repo-standard.sh` updated for the new required path, its audit
  check (both the effective-attribute check via `git check-attr` *and* a
  direct read of the tracked `.gitattributes` file, since the former alone
  can be satisfied by a local, uncommitted `$GIT_DIR/info/attributes`
  override that masks a missing/wrong committed rule), and its scaffold
  starter content.
- `AGENTS.md`'s Quality Gate section gains the one-time driver-registration
  command (kept out of `README.md` per this repo's own documented
  convention — see "Documentation Expectations" in `AGENTS.md` — of
  keeping the README tool-agnostic and putting deeper operational detail
  here instead). The registration command resolves the install root the
  same way the README's own install recipe does (`AGENT_SKILLS_ROOT`, then
  a project-local `./.agents/skills`, then the global default) and quotes
  the resolved path, since git runs the registered command through a
  shell and an unquoted path with a space or metacharacter either fails to
  launch the driver or is interpreted as shell syntax.

## Out of scope

- No automated way to register the driver across existing clones — it's a
  one-time manual step per machine, same as graphify's own hook.
- This repo's own `repo-standard audit`/`scaffold` can't be exercised
  end-to-end here (no `stage` set in this repo's `repo.toml`, same
  pre-existing gap noted in the gitignore design doc) — `.gitattributes` was
  added by hand, verified with `git check-attr` directly rather than via
  `repo-standard.sh`.
- Conflicts on `graphify-out/wiki/`, `graphify-out/obsidian/`, or any other
  export tree are not addressed — those aren't committed at all per the
  existing allowlist, so they can't conflict in the first place.
