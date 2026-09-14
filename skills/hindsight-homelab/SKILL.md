---
name: hindsight-homelab
description: Shared cross-agent-session memory for Roger's homelab (entrement.es and beyond) via a self-hosted Hindsight instance at docker.iceking.entrement.es:8888, bank `homelab-agents`. Use before touching an unfamiliar homelab tool/host, before asserting a homelab convention, or after hitting a tooling failure. Distinct from the generic hindsight-* skills: this one is bound to one specific deployment and uses real directives for procedures, not just recallable facts.
---

# Hindsight Homelab Agents

Self-contained: every command below is inline, no dependency on the
`entrement.es` checkout being present. Works from any repo, on any
machine with network access to `docker.iceking.entrement.es:8888`
(homelab LAN/VPN only — see **Auth & transport** below).

This is deliberately **not** the generic `hindsight-local`/
`hindsight-self-hosted`/`hindsight-cloud` skills: those expect a bank
ID and server URL supplied each time and only cover
`retain`/`recall`/`reflect`. This skill is bound to one specific
deployment and bank, and uses real Hindsight **directives** (hard
rules injected into every `reflect`, not just recallable facts) for
"how we do things here" conventions — see the `hindsight-docs` skill
for the full directive/reflect model.

## 1. Preflight check (every invocation, not one-time setup)

Don't test whether a profile named `homelab` exists — a stale profile
pointing at an old URL would pass a name-only check and silently send
every later `-p homelab` operation to the wrong deployment.
`hindsight profile create` overwrites unconditionally (confirmed:
`hindsight profile create --help` says "Create or overwrite a
profile") and is a purely local write to
`~/.hindsight/cli-profiles/homelab.toml` — no network round-trip — so
there's no cost to just always (re)creating it:

```bash
hindsight profile create homelab --api-url http://docker.iceking.entrement.es:8888
```

Then confirm reachability before doing anything else, so a session
away from the homelab LAN/VPN gets a clear reason instead of a
cryptic connection failure on its first real command:

```bash
curl -sf --max-time 5 -o /dev/null http://docker.iceking.entrement.es:8888/health \
  || { echo "Can't reach docker.iceking.entrement.es:8888 — you're probably not on the homelab LAN/VPN. Skip this skill for now." >&2; exit 1; }
```

## 2. Bank & tag schema

Bank is fixed: **`homelab-agents`** — never `prod-smoke-test`, which
is the deployment's own smoke-test bank.

Tags are **identity scoping**, not content-type labels:
- `repo:{name}` — omit when the content isn't about a specific repo
- `tool:{name}` — never omit on a directive or failure-journal entry
  about a specific tool
- `host:{name}` — omit when not applicable

## 3. Three kinds of content

`/v1/default/...` below — `default` is a literal path segment in this
Hindsight deployment, not a placeholder (verified against the live
OpenAPI spec at `http://docker.iceking.entrement.es:8888/openapi.json`
— confirm again if this skill is ever revised, in case the deployment
changes).

**Semantic fact, untagged** — plain retain is fine:
```bash
hindsight -p homelab memory retain homelab-agents "<content>" --context "<context>"
```

**Semantic fact, tagged** — the CLI has no `--tags` on `memory retain`
(see the known gap below), so tagged facts go through curl, same
shape as the failure-journal example below minus
`"context": "tooling failure"`.

**Procedure ("how we do things here")** — a Hindsight **directive**,
so it's enforced, not just recallable. `directive create` also has no
`--tags` option, so tagged directives go through curl:
```bash
curl -sf -X POST http://docker.iceking.entrement.es:8888/v1/default/banks/homelab-agents/directives \
  -H "Content-Type: application/json" \
  -d '{"name": "<name>", "content": "<content>", "priority": 0, "tags": ["repo:...", "tool:..."]}'
```

**Failure journal entry** — `retain` with `context="tooling failure"`
and tags, so Hindsight's own observation consolidation merges
recurring issues under the same tag scope instead of piling up
duplicates:
```bash
curl -sf -X POST http://docker.iceking.entrement.es:8888/v1/default/banks/homelab-agents/memories \
  -H "Content-Type: application/json" \
  -d '{"items": [{"content": "<content>", "context": "tooling failure", "tags": ["tool:...", "host:..."]}]}'
```
(Same endpoint/shape, minus `"context": "tooling failure"`, for a
tagged semantic fact.)

## 4. Read-before-write, always

Before creating a directive or failure entry, check what's already
known on the same tags:

```bash
hindsight -p homelab directive list homelab-agents -o json   # filter client-side by tag, CLI has no --tags on this subcommand
hindsight -p homelab memory recall homelab-agents "<query>" --tags <tags> --tags-match any --max-tokens 5000
```

`--tags` takes a single comma-separated string for multiple tags
(e.g. `--tags repo:entrement.es,tool:gh`), not a repeated flag —
confirmed against `hindsight memory recall --help` (CLI `0.9.2`);
re-confirm if this skill is revised, since CLI flag syntax can change
between versions. This read-before-write step is the main mitigation
for the rule-duplication problem this skill exists to solve — not
agents remembering to check, but the skill always making them check
first.

**Known limitation, not eliminated:** this is check-then-write, not
atomic — two agent sessions racing on the same tag scope can both
observe "nothing exists yet" and both create an entry. At homelab
scale (a handful of personal agent sessions, not concurrent production
traffic) this is accepted as a low-probability residual risk rather
than engineered away: for failure-journal entries, observation
consolidation already merges recurring duplicates under the same tag
scope; for directives, a rare duplicate is a manual cleanup, not a
correctness failure. If this becomes an actual recurring problem,
revisit with an API-level upsert/idempotency key if Hindsight adds one
(as of this writing, `RetainRequest.operation_id` gives retry-safety
for a single client-supplied UUID, but doesn't solve cross-session
semantic-duplicate detection), or a serialization convention.

## 5. Known CLI/API version gap

Confirmed as of CLI `0.9.2` / this deployment's live OpenAPI spec:
`memory retain`, `retain-files`, and `directive create`/`update` have
no `--tags` option; only `memory recall` does (this is why steps 3
and 4 above use curl for anything tagged). Check `hindsight --version`
and `hindsight memory retain --help` / `hindsight directive create
--help` before assuming this is still true — once `--tags` shows up
there, switch the retain/directive snippets above from curl to the
CLI and delete this note.

## 6. Bank-split criterion

Already saved as a directive in the bank itself, restated here so
it's visible without a round-trip: split into a new bank only when a
group of memories needs genuinely different disposition
(skepticism/literalism/empathy) or reflect/consolidation behavior
than the rest — never because it's conceptually a different *kind* of
thing. One bank today.

## 7. Explicitly out of scope

Live communication between concurrently-running agent sessions. This
bank is durable, recalled-later knowledge, not a message queue — use
whatever agent-to-agent messaging the current harness provides for
that.

## 8. Auth & transport

None on the data-plane API today (LAN-only trust boundary,
deliberate). These commands only work from inside the homelab
LAN/VPN. **Transport is plain HTTP, not TLS** — every example above is
cleartext, so anything on the network path can observe or alter
memories/directives in transit, not just inject new ones from an
endpoint. This is a real, current limitation of the deployment, not
hypothetical — fixing it (TLS or an authenticated tunnel) is a change
to `docker.iceking` itself, out of scope for this skill's client-side
commands.

**Blast radius of the missing auth:** any host that can reach
`docker.iceking.entrement.es:8888` — not just a trusted agent session
— can POST a directive, and a directive is *enforced*, not just
recallable: every future `reflect` call across every session sharing
this bank will treat an attacker- or malfunction-injected directive as
a hard rule, not a fact to weigh. Reachability from the LAN/VPN is not
the same thing as authorization to write, and today this deployment
doesn't distinguish the two at all. Worth being deliberate about: a
session working on some unrelated repo that ingests untrusted content
(a malicious file, a poisoned dependency, a prompt-injection payload
in an issue/PR/webpage it reads) has, via this skill, a documented,
copy-pasteable path to inject a directive that every other session
sharing the bank — including trusted ones — will subsequently treat
as an enforced hard rule. Not fixed here; if this bank's blast radius
ever needs to shrink, the fix (a shared secret or mTLS on the
data-plane, which would also close the transport-cleartext gap above)
belongs on the `entrement.es` deployment, not in this skill's
client-side commands.

## Relationship to `entrement.es`'s `homelab/scripts/hindsight-agents/`

Not a replacement for those scripts — they stay as a convenience for
sessions actually working inside that checkout. This skill is the
portable version of the same logic, usable with zero dependency on
that repo being checked out anywhere. The two should stay consistent
(same bank, same tag schema, same CLI-gap caveat); if the CLI gap gets
fixed, both should be updated in the same pass.
