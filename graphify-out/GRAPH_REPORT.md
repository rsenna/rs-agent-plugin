# Graph Report - rs-agent-plugin  (2026-10-26)

## Corpus Check
- 41 files · ~43,603 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 9 file(s) not represented in the graph (top: (none) 5, .fish 3, .toml 1)

## Summary
- 375 nodes · 451 edges · 39 communities (27 shown, 12 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `169adc9b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Obsidian CLI
- Obsidian Bases Skill
- Functions Reference
- Agent Operations Guide
- pr.sh
- repo-standard.sh
- Starter content for `scaffold`
- OPNsense API — lessons learned
- Hindsight homelab-agents skill: design proposal (implemented as `hindsight-homelab`)
- issue.sh
- Graphify
- Hindsight Homelab Agents
- Pull Request Process
- Cross-repo documentation/folder standard
- PatchMon API - lessons learned
- Doppler CLI - local access + secret injection
- Fix Mapped Issue
- Git Branch Hygiene
- issue-enrichment.md
- OPNsense administration via REST API
- Map Issue → Tasks
- test-repo-standard.sh
- audit.sh
- PatchMon administration via REST API
- Issue #10 — issue.sh/pr.sh: no sanctioned way to create a new issue under the bot identity
- Issue #14 — pr.sh worktrees should not live alongside personal repos under ~/REPO/ME
- Issue #33 — Cross-project skill management
- Issue #3 — Design: cross-repo doc/folder standard (repo.toml stage tiers) + repo-standard skill
- Issue #9 — repo-standard-design: make repos agent-agnostic by default (Claude, Copilot, others)
- opn-api.sh
- patchmon-api.sh
- graphify as a standard dev-process artifact: `.gitignore` requirement design
- graphify-merge-driver.sh
- check-uncommitted-work.sh
- test-check-uncommitted-work.sh
- Check Uncommitted Work
- Issue #30 — Add a check-uncommitted-work skill

## God Nodes (most connected - your core abstractions)
1. `pr.sh script` - 14 edges
2. `Obsidian Bases Skill` - 14 edges
3. `Functions Reference` - 13 edges
4. `OPNsense API — lessons learned` - 13 edges
5. `Obsidian CLI` - 12 edges
6. `log()` - 11 edges
7. `create_required_path()` - 11 edges
8. `issue.sh script` - 10 edges
9. `Hindsight Homelab Agents` - 10 edges
10. `Starter content for `scaffold`` - 10 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (39 total, 12 thin omitted)

### Community 0 - "Obsidian CLI"
Cohesion: 0.06
Nodes (32): Advanced Features, Basic File Management, Bookmarks, Command Palette, Command Structure, Core Patterns, Daily Notes, Daily Notes and Tasks (+24 more)

### Community 1 - "Obsidian Bases Skill"
Cohesion: 0.07
Nodes (30): Cards View, Common Formula Errors, Complete Examples, Daily Notes Index, Date Arithmetic, Default Summary Formulas, Duration Type, Embedding Bases (+22 more)

### Community 2 - "Functions Reference"
Cohesion: 0.08
Nodes (23): Any Type Functions, Date Arithmetic, Date Functions & Fields, Duration Type, File Functions, Functions Reference, Global Functions, Link Functions (+15 more)

### Community 3 - "Agent Operations Guide"
Cohesion: 0.09
Nodes (17): Agent Operations Guide, Branch, Code Review Workflow, Documentation Expectations, Identity & Secrets, One-time setup: graphify merge driver, Quality Gate, Repo Notes (+9 more)

### Community 4 - "pr.sh"
Cohesion: 0.29
Nodes (19): _bot_secret(), cmd_checks(), cmd_cleanup(), cmd_close(), cmd_comment(), cmd_comment_delete(), cmd_open(), cmd_push() (+11 more)

### Community 5 - "repo-standard.sh"
Cohesion: 0.26
Nodes (21): check_graphify_gitattributes_behavior(), check_graphify_gitignore_behavior(), copy_specify_from_reference(), create_agents(), create_changelog(), create_dir_with_gitkeep_if_missing(), create_dot_gitattributes(), create_dot_gitignore() (+13 more)

### Community 6 - "Starter content for `scaffold`"
Cohesion: 0.10
Nodes (21): `AGENTS.md`, `audit` — read-only compliance check, `CHANGELOG.md`, Example session, `.gitattributes`, `.gitignore`, Guardrails, in-progress / released style (+13 more)

### Community 7 - "OPNsense API — lessons learned"
Cohesion: 0.14
Nodes (13): Config backups are cheap insurance, Contents, Endpoint shape and discovery, Finding the API in the first place, OPNsense API — lessons learned, Reading and writing multi-select fields, Save vs. apply, Settings with no API at all (+5 more)

### Community 8 - "Hindsight homelab-agents skill: design proposal (implemented as `hindsight-homelab`)"
Cohesion: 0.15
Nodes (12): Body outline, Context, Frontmatter (proposed), Guaranteeing this happens on every deployment (added after review), Hindsight homelab-agents skill: design proposal (implemented as `hindsight-homelab`), Open questions for review, Out of scope for this proposal, Proposal (+4 more)

### Community 9 - "issue.sh"
Cohesion: 0.41
Nodes (11): cmd_close(), cmd_comment(), cmd_create(), cmd_fetch(), cmd_json(), cmd_label(), cmd_slug(), cmd_unmapped() (+3 more)

### Community 10 - "Graphify"
Cohesion: 0.18
Nodes (11): Alternate install: vercel-labs/skills, Development Remarks, Files, Graphify, Guardrails these skills share, Install, Merge conflicts on `graph.json`/`GRAPH_REPORT.md`, PR-related Skills (+3 more)

### Community 11 - "Hindsight Homelab Agents"
Cohesion: 0.18
Nodes (10): 1. Preflight check (every invocation, not one-time setup), 2. Bank & tag schema, 3. Three kinds of content, 4. Read-before-write, always, 5. Known CLI/API version gap, 6. Bank-split criterion, 7. Explicitly out of scope, 8. Auth & transport (+2 more)

### Community 12 - "Pull Request Process"
Cohesion: 0.20
Nodes (9): Agent identity, not the personal one, Commands (verified), Guardrails (never violate), Portability — read the project's specifics first, Pull Request Process, The process, TODO comments, Why the push is done this way (don't shortcut it) (+1 more)

### Community 13 - "Cross-repo documentation/folder standard"
Cohesion: 0.20
Nodes (10): 1. `repo.toml` gets a `stage` field, 2. Each stage maps to a doc/folder tier, 3. Enforcement: on-demand `repo-standard` skill, Cross-repo documentation/folder standard, Decision, Guardrails for agent-agnostic scaffolding (binding canonical rule), Non-goals, Open follow-ups (not blocking this spec) (+2 more)

### Community 14 - "PatchMon API - lessons learned"
Cohesion: 0.25
Nodes (7): Destination `config` field shapes (from Go source, not docs), Endpoints confirmed working (some undocumented), Patch policies don't schedule themselves, `/patching/trigger` request shape (undocumented, from `patching.go`), PatchMon API - lessons learned, Policy assignment coverage is easy to get wrong silently, Two unrelated auth schemes - don't mix them up

### Community 15 - "Doppler CLI - local access + secret injection"
Cohesion: 0.29
Nodes (6): Doppler CLI - local access + secret injection, Nested-shell quoting gotcha, Read-only vs read/write tokens, Reading secrets into a command, Scoping automation to less than "the whole project", Setting up local access from a token the user gives you

### Community 16 - "Fix Mapped Issue"
Cohesion: 0.29
Nodes (6): Close it (step 6), Close-out comment template, Do this (per task, until the issue is done), Fix Mapped Issue, Guardrails (never violate), Portability — read the project's specifics first

### Community 17 - "Git Branch Hygiene"
Cohesion: 0.29
Nodes (6): Common rationalizations, Core principle, Git Branch Hygiene, Step 1: Run the audit, Step 2: Resolve every NEEDS A DECISION and DIRTY WORKTREE item first, Step 3: Execute

### Community 18 - "issue-enrichment.md"
Cohesion: 0.29
Nodes (6): Acceptance criteria, Analysis, Context & affected areas, Non-goals / out of scope, Open questions, Task breakdown

### Community 19 - "OPNsense administration via REST API"
Cohesion: 0.29
Nodes (6): Before changing anything, Discovering the right endpoint, Getting access, OPNsense administration via REST API, Quick-reference gotchas (see references/lessons-learned.md for full detail), Working examples

### Community 20 - "Map Issue → Tasks"
Cohesion: 0.33
Nodes (5): Boundaries, Do this, Filing a follow-up issue, Map Issue → Tasks, Review before posting

### Community 21 - "test-repo-standard.sh"
Cohesion: 0.73
Nodes (5): assert_contains(), fail(), run_expect_fail(), run_expect_ok(), test-repo-standard.sh script

### Community 22 - "audit.sh"
Cohesion: 0.40
Nodes (4): DIRTY, NEEDS_DECISION, SAFE, audit.sh script

### Community 23 - "PatchMon administration via REST API"
Cohesion: 0.40
Nodes (4): Before wiring up anything automated, Getting access, PatchMon administration via REST API, The core model

### Community 33 - "graphify as a standard dev-process artifact: `.gitignore` requirement design"
Cohesion: 0.18
Nodes (11): Audit behavior, Change to `repo-standard`, Context, Denylist vs allowlist, graphify as a standard dev-process artifact: `.gitignore` requirement design, Out of scope, Required-paths table, Rollout in this repo (+3 more)

### Community 35 - "check-uncommitted-work.sh"
Cohesion: 0.52
Nodes (6): branch_is_integrated(), fail(), is_known_noise(), report_path(), report_worktree(), check-uncommitted-work.sh script

### Community 36 - "test-check-uncommitted-work.sh"
Cohesion: 0.67
Nodes (5): assert_contains(), fail(), init_repo(), run_audit(), test-check-uncommitted-work.sh script

## Knowledge Gaps
- **3 isolated node(s):** `SAFE`, `NEEDS_DECISION`, `DIRTY`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 228 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `repo-standard` connect `Starter content for `scaffold`` to `Agent Operations Guide`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **What connects `SAFE`, `NEEDS_DECISION`, `DIRTY` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Obsidian CLI` be split into smaller, more focused modules?**
  _Cohesion score 0.06060606060606061 - nodes in this community are weakly interconnected._
- **Why does `Obsidian Bases Skill` connect `Obsidian Bases Skill` to `Functions Reference`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Should `Obsidian Bases Skill` be split into smaller, more focused modules?**
  _Cohesion score 0.06666666666666667 - nodes in this community are weakly interconnected._
- **Should `Functions Reference` be split into smaller, more focused modules?**
  _Cohesion score 0.07692307692307693 - nodes in this community are weakly interconnected._
- **Should `Agent Operations Guide` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._