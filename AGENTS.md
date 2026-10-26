# Agent Operations Guide

## Branch
- **Base branch:** `main`
- Always create feature branches via `skills/pull-request-process/pr.sh start <branch>` (never reuse the shared checkout).

## Quality Gate
Run these before every push:
1. `find skills -name '*.sh' -print0 | xargs -0 shellcheck` — keep shell scripts lint-clean.
2. `graphify update .` (external skill, not shipped in this repo — see `docs/superpowers/specs/2026-08-19-graphify-gitignore-standard-design.md`) — refresh the committed graph artifacts (`graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`).
   - If doc-only changes skipped topology updates, the tool reports that it left the outputs untouched; commit the log-friendly message alongside source edits.

If a new language/tooling shows up, extend this list rather than skipping the gate.

### One-time setup: graphify merge driver

`graphify-out/graph.json`/`GRAPH_REPORT.md` are generated, so a textual 3-way merge between branches that each regenerated them conflicts even when nothing meaningful diverged. `.gitattributes` routes both through a custom merge driver (`skills/repo-standard/graphify-merge-driver.sh`) that regenerates instead of diffing — see [the design doc](docs/superpowers/specs/2026-10-26-graphify-merge-driver-design.md). Registration is local git config, not something a commit can ship — run once per clone, resolving the install root the same way the README's install recipe does, and quoting the resolved path (git runs the registered command through a shell, so an unquoted path with a space or shell metacharacter either fails to launch or gets interpreted as shell syntax):

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

The driver is best-effort, not a substitute for the gate: always rerun `graphify update .` after any merge, same as step 2 above.

## Identity & Secrets
`pr.sh` fetches the agent's git/gh identity fresh from Doppler on every invocation (`doppler secrets get GHUB_AGENT_PATC`/`GHUB_AGENT_USERNAME`/`GHUB_AGENT_EMAIL`, project/config from `PR_BOT_DOPPLER_PROJECT`/`PR_BOT_DOPPLER_CONFIG`, default `homelab`/`dev`) — never the ambient `gh auth`/git identity. Authenticate the `doppler` CLI in your environment (e.g. `doppler login`, or a configured service token) so those secrets are reachable; `pr.sh` dies loudly rather than falling back if they aren't.

## Code Review Workflow
1. Branch: `BASE=main pr.sh start feature/<slug>` — cd into printed path.
2. Implement + lint.
3. Gate: run the quality gate steps above.
4. Self-review: invoke the `requesting-code-review` skill (external skill, not shipped in this repo) with `BASE_SHA=$(git merge-base HEAD origin/main)` and current `HEAD_SHA`.
5. Push: `BASE=main REVIEWED=1 pr.sh push feature/<slug>`.
6. Open PR: `BASE=main pr.sh open "<title>" body.md` — stop after opening.
7. Address review threads via `pr.sh threads` + `pr.sh reply`, re-running the gate and self-review before every push.
8. Cleanup once merged/abandoned: run `pr.sh cleanup` from the worktree.

## Repo Notes
- No manifest file: README's install recipe scans `skills/*/SKILL.md` directly (default root `$HOME/.agents/skills`, override via `AGENT_SKILLS_ROOT`) rather than reading a separately-maintained list — one fewer thing that can drift out of sync. A skill only needs a `SKILL.md` in `skills/<name>/` to be picked up.
- Also installable via [vercel-labs/skills](https://github.com/vercel-labs/skills) (`bunx skills add rsenna/rs-agent-plugin ...`, or `npx skills` without Bun) — verified against the real repo: it discovers all skills correctly, and a global install already de-duplicates via symlinks back to `~/.agents/skills` (project-local installs root at `./.agents/skills` instead). Each `SKILL.md` resolves its own plumbing scripts relative to wherever it was actually loaded from, rather than hardcoding an install root, so both installers (and any other that follows the same `skills/<name>/SKILL.md` layout) work without edits.

## Documentation Expectations
- README stays tool-agnostic; for deeper operational detail update this file.
- Specs under `docs/superpowers/specs/` capture historical design decisions; update them if renames change recorded identifiers.
