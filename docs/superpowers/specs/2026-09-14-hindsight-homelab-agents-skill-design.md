# `hindsight-homelab-agents` skill: design proposal (not yet implemented)

## Status

**Proposal only.** No skill code is added by this PR — see "Why this is a
design doc, not the skill" below.

## Context

`entrement.es` (Roger's homelab IaC/docs repo) deployed a shared Hindsight
memory bank, `homelab-agents`, on a self-hosted instance at
`docker.iceking.entrement.es:8888` — see that repo's `AGENTS.md` ("Memory &
context tools" → Hindsight) and `homelab/scripts/hindsight-agents/`. Purpose:
stop different Claude Code sessions from independently re-deriving (and
duplicating) the same homelab conventions, and give sessions a shared place
to leave known-tooling-failure notes.

That setup currently only helps a session working *inside* the
`entrement.es` checkout, because it's documented in that repo's own
`AGENTS.md` and the helper scripts live under that repo's `homelab/`. A
session working in an unrelated repo — even one that touches the same
homelab (OPNsense, Doppler, `gh`, Dokploy, etc.) — has no way to discover
any of this today.

Since `rs-agent-plugin` is the actual distribution point for skills meant
to be "agent-agnostic" and available regardless of which repo/`AGENTS.md`
a session happens to be in (see this repo's own `README.md` install
recipe — global install lands skills in `~/.agents/skills/` and symlinks
into every agent's own skills folder), this is where a *global* Hindsight-
homelab skill belongs, not another repo-local doc.

### Why not just use the generic `hindsight-local`/`hindsight-self-hosted`/
`hindsight-cloud` skills that already exist?

Those are generic, templated connectors (identical structure across all
three, installed 2026-09-11) that:
- expect the user to supply a bank ID and server URL each time (no fixed
  binding to `homelab-agents` / `docker.iceking`),
- only cover `retain`/`recall`/`reflect` with a `--context` label — they
  never mention Hindsight's `directive` API at all,
- have no tag-scoping convention.

The `entrement.es` design deliberately uses real **directives** (hard
rules injected into `reflect`, not just recallable facts) for "how we do
things here" conventions, plus a `repo:`/`tool:`/`host:` tag scheme so
scoped lookups work across many hosts/tools in one shared bank. That's a
capability gap the generic skills don't cover, not a preference — a
recalled fact can be missed by ranking; a global directive is always
loaded. Editing the generic skills in place was rejected: they're
reusable across *any* self-hosted Hindsight deployment, and hardcoding
one homelab's bank/URL into them would break that reusability (and risks
being clobbered by a future reinstall/update of those generic templates).

## Proposal

Add `skills/hindsight-homelab-agents/SKILL.md` to this repo: a **self-
contained** skill (no dependency on the `entrement.es` checkout being
present — all commands inline) that any agent, in any repo, on any
machine with network access to `docker.iceking.entrement.es:8888`, can
use directly.

### Frontmatter (proposed)

```yaml
---
name: hindsight-homelab-agents
description: Shared cross-agent-session memory for Roger's homelab (entrement.es and beyond) via a self-hosted Hindsight instance at docker.iceking.entrement.es:8888, bank `homelab-agents`. Use before touching an unfamiliar homelab tool/host, before asserting a homelab convention, or after hitting a tooling failure. Distinct from the generic hindsight-* skills: this one is bound to one specific deployment and uses real directives for procedures, not just recallable facts.
---
```

### Body outline

1. **Setup check** (idempotent, run once per machine): verify the CLI
   profile exists —
   ```bash
   hindsight profile list | grep -q '^\s*•\s*homelab$' || \
     hindsight profile create homelab --api-url http://docker.iceking.entrement.es:8888
   ```
2. **Bank & tag schema** — fixed: `homelab-agents` (never
   `prod-smoke-test`, the deployment's own smoke-test bank). Tags are
   identity scoping, not content-type labels: `repo:{name}`,
   `tool:{name}`, `host:{name}` — omit `repo:`/`host:` when not
   applicable, never omit `tool:` on a directive or failure-journal
   entry about a specific tool.
3. **Three kinds of content:**
   - Semantic fact → `hindsight -p homelab memory retain homelab-agents "<content>" --context "<context>"` (plain retain; tags not supported by the CLI, see the gap below — use curl if tagging matters).
   - Procedure ("how we do things here") → a Hindsight **directive**, not
     a plain fact, so it's enforced, not just recallable. The CLI's
     `directive create` has no `--tags` option (same gap), so tagged
     directives go through curl:
     ```bash
     curl -sf -X POST http://docker.iceking.entrement.es:8888/v1/default/banks/homelab-agents/directives \
       -H "Content-Type: application/json" \
       -d '{"name": "<name>", "content": "<content>", "priority": 0, "tags": ["repo:...", "tool:..."]}'
     ```
   - Failure journal entry → `retain` with `context="tooling failure"`
     and tags (again via curl for the tags), so Hindsight's own
     observation consolidation merges recurring issues under the same
     tag scope instead of piling up duplicates.
4. **Read-before-write, always:** before creating a directive or failure
   entry, check what's already known on the same tags —
   ```bash
   hindsight -p homelab directive list homelab-agents -o json   # filter client-side by tag, CLI has no --tags on this subcommand
   hindsight -p homelab memory recall homelab-agents "<query>" --tags <tags> --tags-match any --max-tokens 5000
   ```
   This is the actual fix for the rule-duplication problem this skill
   exists to solve — not agents remembering to check, but the skill
   always making them check first.
5. **Known CLI/API version gap** (stated as a fact to re-verify, not a
   permanent constraint): as of CLI `0.9.2` / API `0.10.0`, `memory
   retain`, `retain-files`, and `directive create`/`update` have no
   `--tags` option; only `memory recall` does. Check `hindsight --version`
   and `hindsight memory retain --help` / `hindsight directive create
   --help` — once `--tags` shows up there, switch the retain/directive
   snippets above from curl to the CLI and delete this note.
6. **Bank-split criterion** (already saved as a directive in the bank
   itself, restated here so it's visible without a round-trip): split
   into a new bank only when a group of memories needs genuinely
   different disposition (skepticism/literalism/empathy) or
   reflect/consolidation behavior than the rest — never because it's
   conceptually a different *kind* of thing. One bank today.
7. **Explicitly out of scope:** live communication between
   concurrently-running agent sessions. This bank is durable,
   recalled-later knowledge, not a message queue — use whatever
   agent-to-agent messaging the current harness provides for that.
8. **Auth:** none on the data-plane API today (LAN-only trust boundary,
   deliberate). These commands only work from inside the homelab
   LAN/VPN.

### Relationship to `entrement.es`'s `homelab/scripts/hindsight-agents/`

Not a replacement for those scripts — they stay as a convenience for
sessions actually working inside that checkout (already written, tested,
committed on that repo's PR #73). This skill is the portable version of
the same logic, usable with zero dependency on that repo being checked
out anywhere. The two should stay consistent (same bank, same tag
schema, same CLI-gap caveat); if the CLI gap gets fixed, both should be
updated in the same pass.

## Why this is a design doc, not the skill

Explicit instruction from Roger for this round: propose the approach and
implementation details here, but do not write `skills/hindsight-homelab-
agents/SKILL.md` itself in this PR. A follow-up (this same doc, revised
if review changes the shape) implements it once approved.

## Open questions for review

- Skill name: `hindsight-homelab-agents` vs. something shorter
  (`hindsight-homelab`)? Longer name is more specific/searchable, matches
  the "which deployment" framing; shorter is easier to type/recall.
- Should the setup-check step also probe reachability
  (`docker.iceking.entrement.es:8888/health`) and say something useful
  ("you're probably not on the homelab LAN/VPN") rather than just fail
  cryptically when a session runs this away from home? The remote-VPN-
  access ticket (`entrement.es` issue #74) is separately tracking
  whether that access path even works yet.
- Worth adding a `hindsight profile show homelab` idempotency check
  before `create` in case the URL ever changes (e.g. if `docker.iceking`
  gets renumbered) — `create` overwrites unconditionally per its own
  `--help` text ("Create or overwrite a profile"), so re-running the
  setup check is always safe, but a stale profile pointing at an old IP
  would fail silently different than "not set up at all."

## Out of scope for this proposal

- Migrating or removing the generic `hindsight-local`/
  `hindsight-self-hosted`/`hindsight-cloud` skills — unrelated, separate
  concern.
- Fixing the CLI's missing `--tags` support upstream (this is Roger's
  plugin repo, not the `hindsight` CLI's own repo).
- Any change to `entrement.es` itself — that repo's PR #73 already ships
  the repo-local scripts and `AGENTS.md` update independently of whether
  this proposal is accepted.
