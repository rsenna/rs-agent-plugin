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

1. **Preflight profile check** (run every invocation, not a one-time
   setup step): don't test for the profile's *name* — a stale profile
   pointing at an old URL (e.g. `docker.iceking` renumbered) would pass
   a name-only check and silently send every later `-p homelab`
   operation to the wrong deployment. `profile create` overwrites
   unconditionally per its own `--help` text ("Create or overwrite a
   profile"), and (verified: `hindsight profile create --help`) it's a
   purely local write to `~/.hindsight/cli-profiles/homelab.toml` — no
   network round-trip to `docker.iceking` — so there's no per-invocation
   cost, network or otherwise, to just always (re)creating it. Skip the
   existence check entirely:
   ```bash
   hindsight profile create homelab --api-url http://docker.iceking.entrement.es:8888
   ```
2. **Bank & tag schema** — fixed: `homelab-agents` (never
   `prod-smoke-test`, the deployment's own smoke-test bank). Tags are
   identity scoping, not content-type labels: `repo:{name}`,
   `tool:{name}`, `host:{name}` — omit `repo:`/`host:` when not
   applicable, never omit `tool:` on a directive or failure-journal
   entry about a specific tool.
3. **Three kinds of content.** `/v1/default/...` below — `default` is a
   literal path segment in this Hindsight deployment (not a placeholder
   to fill in; verify against the live OpenAPI spec at
   `http://docker.iceking.entrement.es:8888/openapi.json` before
   implementing, in case that changes):
   - Semantic fact, untagged → `hindsight -p homelab memory retain homelab-agents "<content>" --context "<context>"` is fine (plain retain; tags not supported by the CLI, see the gap below). Semantic fact WITH tags → curl, same shape as the failure-journal example below, just without `"context": "tooling failure"`.
   - Procedure ("how we do things here") → a Hindsight **directive**, not
     a plain fact, so it's enforced, not just recallable (see the
     `hindsight-docs` skill for the full directive/reflect model). The
     CLI's `directive create` has no `--tags` option (same gap), so
     tagged directives go through curl:
     ```bash
     curl -sf -X POST http://docker.iceking.entrement.es:8888/v1/default/banks/homelab-agents/directives \
       -H "Content-Type: application/json" \
       -d '{"name": "<name>", "content": "<content>", "priority": 0, "tags": ["repo:...", "tool:..."]}'
     ```
   - Failure journal entry → `retain` with `context="tooling failure"`
     and tags, so Hindsight's own observation consolidation merges
     recurring issues under the same tag scope instead of piling up
     duplicates. The CLI's `memory retain` also has no `--tags` option,
     so this goes through curl too — the shape a future SKILL.md needs
     (retain's actual payload structure, confirmed against this bank
     during the `entrement.es` rollout):
     ```bash
     curl -sf -X POST http://docker.iceking.entrement.es:8888/v1/default/banks/homelab-agents/memories \
       -H "Content-Type: application/json" \
       -d '{"items": [{"content": "<content>", "context": "tooling failure", "tags": ["tool:...", "host:..."]}]}'
     ```
     (Same endpoint/shape, minus the `"context": "tooling failure"`, for
     a tagged semantic fact.)
4. **Read-before-write, always:** before creating a directive or failure
   entry, check what's already known on the same tags —
   ```bash
   hindsight -p homelab directive list homelab-agents -o json   # filter client-side by tag, CLI has no --tags on this subcommand
   hindsight -p homelab memory recall homelab-agents "<query>" --tags <tags> --tags-match any --max-tokens 5000
   ```
   `--tags` takes a single comma-separated string for multiple tags
   (e.g. `--tags repo:entrement.es,tool:gh`), not a repeated flag —
   confirm against `hindsight memory recall --help` on the machine
   implementing this, since CLI flag syntax can change between
   versions. This read-before-write step is the main mitigation for
   the rule-duplication problem this skill exists to solve — not
   agents remembering to check, but the skill always making them check
   first.

   **Known limitation, not eliminated:** this is check-then-write, not
   atomic — two agent sessions racing on the same tag scope can both
   observe "nothing exists yet" and both create an entry. At homelab
   scale (a handful of personal agent sessions, not concurrent
   production traffic) this is accepted as a low-probability residual
   risk rather than engineered away: for failure-journal entries,
   Hindsight's own observation consolidation already merges recurring
   duplicates under the same tag scope (see point 3); for directives,
   a rare duplicate is a manual cleanup, not a correctness failure (the
   read-before-write step still eliminates the common case — an agent
   that never checks). If this becomes an actual recurring problem,
   revisit with an API-level upsert/idempotency key if Hindsight adds
   one, or a serialization convention — not attempted here since
   neither exists in the current CLI/API.
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

   **Blast radius, stated explicitly (reviewers correctly flagged this
   needed more than one line):** any host that can reach
   `docker.iceking.entrement.es:8888` — not just a trusted agent
   session — can POST a directive, and a directive is *enforced*, not
   just recallable (point 3): every future `reflect` call across every
   session sharing this bank will treat an attacker- or
   malfunction-injected directive as a hard rule, not a fact to weigh.
   The *network* exposure (unauthenticated API, reachable from anywhere
   on the LAN/VPN) isn't new — that trust boundary already covers
   plenty of other homelab services. But this proposal does introduce a
   distinct, non-network risk worth naming on its own: today, only a
   session working inside the `entrement.es` checkout has the scripts
   to write to this bank. This skill's entire point is to hand that
   same write path — a documented, copy-pasteable `curl -X POST
   .../directives` recipe — to every agent session, in every repo, on
   any machine. A session working on some unrelated repo that ingests
   untrusted content (a malicious file, a poisoned dependency, a
   prompt-injection payload in an issue/PR/webpage it reads) now has a
   ready-made, in-scope-of-its-own-instructions path to inject a
   directive that every *other* session sharing the bank — including
   trusted ones — will subsequently treat as an enforced hard rule.
   That's an amplification this skill specifically causes by widening
   who can write, distinct from "a rogue host on the LAN" and not
   addressed by observing that the network boundary itself is
   unchanged. Accepted for now, same reasoning as the network point
   (auth on the deployment is out of scope here — see below), but
   worth a session author being aware of before pointing an
   untrusted-content-processing session at this skill. Not fixed in
   this proposal; if this bank's blast radius ever needs to shrink,
   the fix belongs on the `entrement.es` deployment
   (e.g. a shared secret or mTLS on the data-plane), not in this
   skill's client-side commands.

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
- ~~Worth adding a `hindsight profile show homelab` idempotency check
  before `create`~~ — resolved during review: dropped the existence
  check entirely and made step 1 always (re)create the profile
  unconditionally, since `create` already overwrites safely. See step 1
  above.

## Out of scope for this proposal

- Migrating or removing the generic `hindsight-local`/
  `hindsight-self-hosted`/`hindsight-cloud` skills — unrelated, separate
  concern.
- Fixing the CLI's missing `--tags` support upstream (this is Roger's
  plugin repo, not the `hindsight` CLI's own repo).
- Adding authentication to the Hindsight data-plane API itself (see the
  "Auth" note under Body outline point 8) — that's a change to the
  `entrement.es` deployment, not to this skill's client-side commands.
- Any change to `entrement.es` itself — that repo's PR #73 already ships
  the repo-local scripts and `AGENTS.md` update independently of whether
  this proposal is accepted.
