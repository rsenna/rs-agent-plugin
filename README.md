# rs-agent-plugin

_Personal AI agent plugin: a collection of agent-agnostic skills_.

- GitHub issue → PR workflow, factored into separate skills.
- Obsidian
- Graphify usage
- etc.

## Install

Download the repo (or add it as a git submodule) and wire the skills into your agent runtime:

```bash
git clone https://github.com/rsenna/rs-agent-plugin.git
cd rs-agent-plugin
# install under $HOME/.agents/skills by default
python3 - <<'PY'
import os, pathlib
root = pathlib.Path.cwd()
default_root = pathlib.Path.home() / ".agents" / "skills"
install_root = pathlib.Path(os.environ.get("AGENT_SKILLS_ROOT") or default_root)
install_root.mkdir(parents=True, exist_ok=True)
for skill_md in sorted((root / "skills").glob("*/SKILL.md")):
    skill_dir = skill_md.parent
    target = install_root / skill_dir.name
    if target.is_symlink():
        target.unlink()
    elif target.exists():
        raise SystemExit(f"Refusing to overwrite existing directory {target}")
    target.symlink_to(skill_dir)
PY
```

Override `AGENT_SKILLS_ROOT` if your agent looks elsewhere.

### Alternate install: vercel-labs/skills

This repo is also installable via [vercel-labs/skills](https://github.com/vercel-labs/skills)
(`bunx skills`, or `npx skills` if you don't have Bun), which discovers skills
the same way (`skills/<name>/SKILL.md` with `name`/`description` frontmatter)
and installs across dozens of agents:

```bash
bunx skills add rsenna/rs-agent-plugin --all -a claude-code -a opencode -g
```

A global install (`-g`) lands the "universal" copy at `~/.agents/skills/<name>/`
and symlinks it into each other target agent's own skills folder (e.g.
`~/.claude/skills/<name>` → `~/.agents/skills/<name>`) — no duplication, and the
`~/.agents/skills` root matches the python recipe above's own default. Note
`<name>` there is each `SKILL.md`'s **frontmatter** `name:`, not its directory
name — identical for 9 of these 11 skills, but `clawhub.obsidian-cli` and
`clawhub.obsidian-bases` install under `obsidian-official-cli` and
`obsidian-bases` respectively via `bunx`/`npx skills` (their frontmatter
names), vs. their directory names via the python recipe above. Either way
works standalone; installing the *same* skill through both methods just gets
you two separately-named copies for those two, not a conflict. A project-local
install (no `-g`) roots the same layout at `./.agents/skills/` instead. Either
way, every `SKILL.md` in this plugin resolves its own plumbing scripts relative to
wherever it was actually installed, so both install paths work.

## PR-related Skills

- **`map-issue-to-tasks`**:
  1. Analyse a GitHub issue.
  2. Enrich it against a template.
  3. Break it into a dependency-ordered task list (`tasks/issue-<n>-<slug>.md`).
- **`fix-mapped-issue`**:
  1. Implement the mapped tasks.
  2. Ship each through `pull-request-process`.
  3. Close the issue once everything is merged.
- **`pull-request-process`** — the safe way to ship a change:
  1. Create a feature branch in its own worktree.
  2. Run the project's quality gate.
  3. Push the branch to `origin`.
  4. Open a PR.
  5. Stop and wait for review.
  6. Fix each review thread through the same flow.

The `pull-request-process` skill is called by the other two skills, as a building block.

Each skill's `SKILL.md` documents its own commands and guardrails in full.

## Guardrails these skills share

- **ALWAYS use a _PR_ to send code changes**.
- **NEVER touch the `main`/`master` _branch_**.
- **NEVER _merge_ a PR or mark it ready**.
  - Instead, bots/maintainer will review and merge.
- **NEVER _resolve_ review threads**.
  - Reply, and let the maintainer resolve.
- **NEVER _push_, UNLESS the project's own quality gate is green**.
  - Make an explicit-refspec push to a feature branch instead.

## Development Remarks

### Graphify

#### Summary

This repo uses the `graphify` skill to build a queryable knowledge graph of its own codebase: god nodes, community structure, cross-file relationships.

After code changes, run `graphify update .` (or `/graphify . --update`) to keep the committed graph current, before it ships into a PR.

#### Queries

For codebase questions, run `graphify query "<question>"` before falling back to raw grep or file browsing (see `AGENTS.md`).

`graphify path "<A>" "<B>"` and `graphify explain "<concept>"` work the same way for narrower lookups.

#### Files

`graphify-out/graph.json` and `graphify-out/GRAPH_REPORT.md` are committed: the graph and its audit report are real outputs worth having on a fresh clone and worth tracking in history.

Everything else under `graphify-out/` (`graph.html`, `manifest.json`, `cost.json`, `cache/`, `.graphify_*`) is local bookkeeping and stays gitignored. Those artifacts can be regenerated, but semantic extraction from a fresh clone can redo non-trivial LLM work/cost.
