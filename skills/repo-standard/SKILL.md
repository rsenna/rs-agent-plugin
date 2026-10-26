---
name: repo-standard
description: Audit or scaffold a repo's documentation/folder layout against its declared repo.toml stage tier. Use when asked to audit, check, scaffold, or bring a repo up to standard. Triggered on demand only — not a pre-PR gate.
---

# repo-standard

Checks (or creates) the documentation and folder artifacts required for a repo's declared `stage` tier, as defined in the [cross-repo standard design doc](../../docs/superpowers/specs/2026-08-01-repo-standard-design.md).

Two modes — **`audit`** (read-only) and **`scaffold`** (non-destructive write).
The command plumbing is implemented in `skills/repo-standard/repo-standard.sh`.

Both fail closed if `repo.toml` is absent or `stage` is missing/invalid.

## Prerequisites

- You must be inside a git repo with a `repo.toml` that has a valid `stage` field. **Both `audit` and `scaffold` fail closed** — they stop with a clear error if `repo.toml` is absent or `stage` is missing or not one of the four valid values. No default is inferred.
- Valid `stage` values: `prototype`, `in-progress`, `released`, `archived`.
- `scaffold` never overwrites existing content — only creates what is absent.

## Workflow

### `audit` — read-only compliance check

1. **Verify bootstrap:** confirm `repo.toml` exists and `stage` is a valid value. If not, stop with a clear error — do not infer a default.
2. **Read the stage** from `repo.toml`.
3. **Diff against the required-paths table** (see below). For each required path: check whether it exists. For `repo.toml` itself, also confirm the `stage=` line is present and valid. For `.gitignore`, existence isn't enough — verify the graphify block *works*, not that it merely contains certain text (see the `### .gitignore` starter-content section below, "Audit behavior"). This is the one required path with a behavioral check, everywhere else stays presence-only.
4. **Report** missing required paths, note optional paths that are absent (for information only), and confirm what is already present. Output is human-readable; no files are created or modified.

### `scaffold` — non-destructive creation

1. Run the full `audit` check first. Same bootstrap rules apply — fail closed on missing/invalid `stage`.
2. For each **missing required** path, offer to create it with minimal starter content (see starters below). **Never overwrite** a path that already exists, even if its content looks wrong — report it and move on.
3. After creating files, print a summary of what was created vs what was skipped (already existed).

## Required paths by stage (authoritative)

This table is the single source of truth. `audit` reports anything in the "required" column that is absent. `scaffold` creates it.

| Path | `prototype` | `in-progress` | `released` | `archived` |
|---|---|---|---|---|
| `repo.toml` (with `stage=`) | required | required | required | required |
| `.gitignore` (graphify block, behavior-verified) | required | required | required | required |
| `.gitattributes` (graphify merge driver, behavior-verified) | required | required | required | required |
| `AGENTS.md` | required | required | required | required (frozen) |
| `README.md` | required | required | required | required (frozen) |
| `SPEC.md` | required | — | — | — |
| `specs/` | — | required | required | — |
| `specs/decisions/` | — | required | required | — |
| `.specify/` (full spec-kit) | — | required | required | — |
| `.specify/memory/constitution.md` | — | required | required | — |
| `tasks/` | — | required | required | — |
| `CHANGELOG.md` | — | *(optional)* | required | — |
| `SECURITY.md` | — | *(optional)* | *(optional)* | — |

**`archived` notes:**
- `AGENTS.md` and `README.md` are marked `required (frozen)` — audit checks they exist; scaffold does **not** create them (they should already exist from a prior stage). If they are somehow absent, that is reported but not auto-fixed.
- All spec/tasks/changelog artifacts are not required and not scaffolded.

## Starter content for `scaffold`

When creating a missing required file, use the minimal content below. Most starters include a `# TODO` marker so the maintainer knows what to fill in — `.gitignore` is the exception, since there's nothing project-specific to fill in.

> **Note:** `repo.toml` is never created by scaffold — both modes require it to already exist with a valid `stage`. If it is absent, stop and tell the user to create it manually first.

### `.gitignore`
Same graphify block in every repo, regardless of whether `/graphify` has been run yet — the goal is one standard template, not a conditional one. If `.gitignore` already exists but is missing the graphify block, scaffold does **not** auto-append (never overwrite existing content, even if it looks incomplete) — it reports the gap and moves on, same as any other required path.
```gitignore
# OS / editor
.DS_Store
*.swp

# graphify (knowledge graph) — allowlist: commit only graph.json + GRAPH_REPORT.md,
# ignore everything else graphify-out/ produces (exports, caches, bookkeeping)
graphify-out/*
!graphify-out/graph.json
!graphify-out/GRAPH_REPORT.md
```

**Audit behavior:** don't text-match the lines above — a grep-based check (marker comment present, `graphify-out/*` string present) can be satisfied by a commented-out pattern, a block missing one or both `!` negations, or a later unrelated rule in the file overriding the allowlist, while still looking "present." Instead verify what the rules actually *do*: from the repo root, run

```shell
git check-ignore --no-index -q <path>
```

against five representative paths, and read the **exit code**, not any printed output (`-q` suppresses output; the two "not ignored" paths print nothing either way):

| Path | Expected exit code | Meaning |
|---|---|---|
| `graphify-out/graph.html` | `0` | ignored |
| `graphify-out/some-bookkeeping-file` | `0` | ignored |
| `graphify-out/wiki/index.md` | `0` | ignored (nested export tree — a pattern that only matches flat files under `graphify-out/` would wrongly leave this committable) |
| `graphify-out/graph.json` | `1` | **not** ignored |
| `graphify-out/GRAPH_REPORT.md` | `1` | **not** ignored |

**`--no-index` is required, not optional.** Without it, `git check-ignore` answers from the index for any path already tracked — and `graph.json`/`GRAPH_REPORT.md` are tracked by design (that's the whole point of the allowlist), so those two probes always report "not ignored" regardless of what `.gitignore` actually says. That would hide a missing-negation or overridden-rule failure on exactly the two files this allowlist exists to commit. `--no-index` forces git to evaluate the ignore rules instead, so a non-compliant block is caught there too.

**Exit code `128`** (not a git repo, bad flag, git version too old) is an audit error, not a verdict — report it as "audit could not run," never coerce it into "not ignored."

If any of the five doesn't match its expected verdict, `.gitignore` is reported non-compliant, even though the file exists. This catches the text-matching failure modes above (commented-out pattern, missing negation, overriding rule, comment-wording/whitespace drift) by asking git the same question audit ultimately cares about — would `git add -A` actually pick up `graph.json`/`GRAPH_REPORT.md` and skip everything else — instead of a text proxy for it. The five paths are representative, not exhaustive: extend the table if `graphify-out/`'s output layout grows a new top-level shape worth probing.

Non-git repos: report the `.gitignore` row as not applicable rather than attempting an equivalent check — `repo-standard`'s starter content and this audit are git-specific by design.

### `.gitattributes`

`graph.json` and `GRAPH_REPORT.md` are generated by `graphify update .`, not
hand-authored — a textual 3-way merge between two branches that each
regenerated the graph answers the wrong question and conflicts even when
nothing about the graph's meaning actually diverged. `.gitattributes` routes
both paths through a custom merge driver that regenerates the file from the
already-merged tree instead of diffing it. See
[the merge-driver design doc](../../docs/superpowers/specs/2026-10-26-graphify-merge-driver-design.md)
for the full rationale.

```gitattributes
# graphify-out: generated knowledge-graph artifacts. A textual merge conflict
# here is meaningless — the files are a pure function of the rest of the repo —
# so route them through a custom merge driver that regenerates instead of
# diffing. One-time per clone, register the driver before this takes effect —
# see "One-time per-clone setup" in skills/repo-standard/SKILL.md.
graphify-out/graph.json merge=graphify
graphify-out/GRAPH_REPORT.md merge=graphify
```

**One-time per-clone setup** (this is local git config, not something a
commit can ship — same reason graphify's own post-commit hook is documented
rather than auto-installed): register the driver once per machine/clone,
pointing at wherever this skill actually resolves on disk (consistent with
this repo's own "no manifest" convention — each `SKILL.md` resolves its own
plumbing relative to wherever it was loaded from, see Repo Notes in
`AGENTS.md`). Resolve the install root the same way the README's install
recipe does — `AGENT_SKILLS_ROOT` if set, else the project-local
`./.agents/skills` if that's where this skill actually landed, else the
global `~/.agents/skills` default — and **quote the resolved path inside the
registered command**: git runs `merge.<name>.driver`'s value through a
shell, so an unquoted path containing a space or shell metacharacter either
fails to launch the driver or, worse, gets interpreted as shell syntax:

```bash
if [ -n "${AGENT_SKILLS_ROOT:-}" ]; then
  SKILLS_ROOT="$AGENT_SKILLS_ROOT"
elif [ -d "./.agents/skills/repo-standard" ]; then
  SKILLS_ROOT="$PWD/.agents/skills"
else
  SKILLS_ROOT="$HOME/.agents/skills"
fi
DRIVER="$SKILLS_ROOT/repo-standard/graphify-merge-driver.sh"
git config merge.graphify.driver "'$DRIVER' %O %A %B %P"
```

If `graphify` isn't on `PATH`, or some other file in the same merge still has
unresolved conflicts, the driver falls back to keeping `ours` unchanged and
prints a note to rerun `graphify update .` manually — it never blocks a merge
and never silently produces a stale graph without saying so. It also never
regenerates from a path it wasn't told to handle: `%P` is validated against
the two expected paths before touching any file, and the regenerated output
is written atomically rather than truncating `%A` in place, so a failure
partway through a merge can never leave a corrupted or partial file behind.

**Known residual limitation:** this driver runs mid-merge — before `HEAD`
has advanced to the eventual merge commit, and without a documented
git-internal guarantee about invocation order across multiple
custom-merge-driver paths in the same merge. The "other conflicts still
unresolved" guard above covers the common case (a real conflict elsewhere in
the same merge), but can't rule out every possible invocation ordering. The
actual correctness backstop is the mandatory `graphify update .` gate step
before push (see `AGENTS.md`) — run it again after any merge this driver
touched, same as always; don't treat the driver's own regeneration as the
final word.

A second gap: the driver only fires when git considers the path
**conflicted** (modified on both sides). If only one branch touched the
graph file, git takes that side's version as-is with no conflict at
all — the driver never runs, so a graph that's now stale relative to the
rest of the merged tree goes uncaught. Fixing this fully would need a
`post-merge` hook that reruns `graphify update .` unconditionally after
every merge, which is the same kind of local-machine-state hook this
design already declines to auto-install. Same backstop applies: the
pre-push gate step catches it either way.

**Audit behavior:** same "behavioral, not textual" principle as
`.gitignore` above, plus one check textual matching can't substitute for.
First, ask git what it would actually do:

```shell
git check-attr merge -- graphify-out/graph.json graphify-out/GRAPH_REPORT.md
```

Both must report `merge: graphify`. But `check-attr` reports the *effective*
attribute — a local, uncommitted `$GIT_DIR/info/attributes` override can
satisfy this even though the tracked `.gitattributes` itself is missing or
wrong, which would pass audit here while every other clone (which doesn't
have that local override) falls back to a plain text merge and still
conflicts. So also confirm the declaration lives in the tracked file itself:

```shell
grep -E '^graphify-out/graph\.json[[:space:]]+merge=graphify([[:space:]]|$)' .gitattributes
grep -E '^graphify-out/GRAPH_REPORT\.md[[:space:]]+merge=graphify([[:space:]]|$)' .gitattributes
```

Both checks must pass; either failing makes `.gitattributes` non-compliant,
even though the file exists and even though `check-attr` alone might say
otherwise.

Both must report `merge: graphify`; anything else (`unspecified`, a
different driver name) is non-compliant. This only verifies the attribute
*declares* the driver — it can't verify the driver is actually *registered*
in a given clone's local git config, since that's intentionally not
something a repo can carry. The declaration is what scaffold/audit can own;
registration is the one-time manual step above.

Non-git repos: report the `.gitattributes` row as not applicable, same as
`.gitignore`.

### `AGENTS.md`

Use the **prototype style** for `stage = prototype`; use the **in-progress / released style** for `stage = in-progress` or `stage = released`. (`archived` repos are not scaffolded.)

#### prototype style
```markdown
# AGENTS.md

## Rules
<!-- TODO: key constraints for this repo (naming, architecture, non-goals) -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->

## Setup
<!-- TODO: how to get the repo running locally -->

## Validation
<!-- TODO: the quality gate command (tests, linter, formatter) -->
```

#### in-progress / released style
```markdown
# AGENTS.md

## What's implemented
<!-- TODO: honest map of what works vs what's aspirational -->

## Rules & decisions
<!-- TODO: decided conventions, architecture rules, non-goals -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->

## Dev commands
<!-- TODO: build, test, lint, run -->

## Where things live
<!-- TODO: module map — what's in which directory -->
```

### `README.md`
```markdown
# <repo name>

<!-- TODO: one-line description -->

## Status
<!-- TODO: current status, known limitations, next steps -->
```

### `SPEC.md` (prototype only)
```markdown
# Spec

<!-- TODO: what this thing is meant to do; key decisions; what it is NOT -->
```

### `specs/` and `specs/decisions/`
Create as empty directories (add a `.gitkeep` if needed).

### `.specify/` and `.specify/memory/constitution.md`
`.specify/` should be bootstrapped from iklo's reference implementation — do **not** create a hand-rolled imitation. The reference is in the `iklo` repo (sibling of the target repo under `~/REPO/ME/` by default — adjust the path to match your local layout). Copy the full `.specify/` tree from that reference and adapt only the project-specific references in `constitution.md`.

This standard is **agent-agnostic by default**: do not treat one integration
surface as exclusive. If a repo already contains Copilot/Claude/other-agent
integration files outside `.specify/` (for example `.github/agents/`,
`.github/prompts/`, `.vscode/settings.json`), scaffolding `.specify/` is
additive and must not prune those files just because a different agent is
running this session. The listed paths are examples, not exhaustive; follow
the canonical rule in the design doc section **"Guardrails for
agent-agnostic scaffolding (binding canonical rule)"**.

```markdown
# Constitution — <repo name>

<!-- TODO: governing principles, constraints, and architectural decisions for this project -->
<!-- Reference: copied from iklo/.specify/memory/constitution.md structure -->
<!-- TODO: preserve agent-agnostic integrations (Copilot/Claude/other) as additive; do not prune one surface when adding another -->
```

### `tasks/`
Create as an empty directory (add a `.gitkeep` if the repo won't have any tasks yet).

### `CHANGELOG.md`
```markdown
# Changelog

All notable changes to this project will be documented here.

<!-- TODO: follow Keep a Changelog format (https://keepachangelog.com) -->
```

## Invocation

This skill is a **GitHub Copilot CLI slash command** — invoke it by typing `/repo-standard` in the Copilot CLI chat, followed by the mode:

```
/repo-standard audit      # read-only compliance check
/repo-standard scaffold   # non-destructive creation of missing artifacts
```

Equivalent direct script usage (from this plugin repo checkout, not from the target repo):

```bash
PLUGIN_REPO=~/REPO/ME/rs-agent-plugin
"$PLUGIN_REPO"/skills/repo-standard/repo-standard.sh audit
"$PLUGIN_REPO"/skills/repo-standard/repo-standard.sh scaffold
```

If the target repo's iklo reference is not at `~/REPO/ME/iklo/.specify`, set `REPO_STANDARD_SPECIFY_REF=/path/to/iklo/.specify` before running `scaffold`.

Run from inside the **target repo's** directory (the script resolves that repo via `git rev-parse --show-toplevel`), while invoking the script by absolute path from the plugin repo as above.

## Example session

```
# Audit a repo
cd ~/REPO/ME/roset.sh
/repo-standard audit

# Output example:
# stage: prototype
# ✓  repo.toml (stage=prototype)
# ✓  AGENTS.md
# ✓  README.md
# ✗  SPEC.md  [MISSING — required for prototype]
# audit complete: 1 required artifact missing

# Scaffold the missing piece
/repo-standard scaffold
# → Creates SPEC.md with starter content
# → Prints: created SPEC.md
```

## Guardrails

- Never infer a default stage — fail closed if `repo.toml` or `stage` is absent/invalid.
- Never overwrite existing files in scaffold mode.
- Never run as an automatic pre-PR check — on-demand only.
- `.gitignore` and `.gitattributes` are audited behaviorally (`git check-ignore` / `git check-attr` respectively), not by text or presence — these are the two deliberate exceptions; every other required path stays presence-only.
- For `.specify/`: always bootstrap from iklo's reference, never hand-roll.
- Keep repos agent-agnostic: never delete/prune another agent's integration
  files as part of scaffold/audit; integrations are additive.
- For `archived` repos: audit reports that the repo is archived and skips all non-required checks; scaffold does nothing (archived repos are frozen).
