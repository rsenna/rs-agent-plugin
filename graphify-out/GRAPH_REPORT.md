# Graph Report - cubic-ignore-graphify  (2026-10-23)

## Corpus Check
- 33 files · ~33,363 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 8 file(s) not represented in the graph (top: (none) 4, .fish 3, .toml 1)

## Summary
- 154 nodes · 241 edges · 18 communities (13 shown, 5 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3ad77eca`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- pr.sh
- Issue #3 - Design: cross-repo doc/folder standard (repo.toml stage tiers) + repo-standard skill
- issue.sh
- `hindsight-homelab-agents` skill: design proposal (not yet implemented)
- pull-request-process SKILL.md
- doppler-secrets SKILL.md
- Git Branch Hygiene
- audit.sh
- obsidian-official-cli skill-card (top-level)
- Obsidian Bases Functions Reference
- opn-api.sh
- patchmon-api.sh
- opencode GitHub Action workflow
- repo-standard.sh
- graphify as a standard dev-process artifact: `.gitignore` requirement design
- test-repo-standard.sh
- Agent Operations Guide

## God Nodes (most connected - your core abstractions)
1. `pr.sh script` - 14 edges
2. `log()` - 11 edges
3. `issue.sh script` - 10 edges
4. `create_required_path()` - 10 edges
5. `repo-standard.sh script` - 9 edges
6. `Issue #3 - Design: cross-repo doc/folder standard (repo.toml stage tiers) + repo-standard skill` - 8 edges
7. `die()` - 7 edges
8. `cmd_cleanup()` - 7 edges
9. `log()` - 7 edges
10. `run_audit()` - 7 edges

## Surprising Connections (you probably didn't know these)
- `repo-standard SKILL.md` --references--> `Cross-repo documentation/folder standard design doc`  [EXTRACTED]
  skills/repo-standard/SKILL.md → docs/superpowers/specs/2026-08-01-repo-standard-design.md
- `repo-standard audit mode (read-only compliance check)` --conceptually_related_to--> `Per-stage doc/folder tier table (prototype/in-progress/released/archived)`  [EXTRACTED]
  skills/repo-standard/SKILL.md → docs/superpowers/specs/2026-08-01-repo-standard-design.md
- `repo-standard scaffold mode (non-destructive creation)` --conceptually_related_to--> `Per-stage doc/folder tier table (prototype/in-progress/released/archived)`  [EXTRACTED]
  skills/repo-standard/SKILL.md → docs/superpowers/specs/2026-08-01-repo-standard-design.md
- `Sanctioned 'create' subcommand with bot-identity enforcement` --semantically_similar_to--> `Centralized worktree-root strategy (not sibling of main checkout)`  [INFERRED] [semantically similar]
  tasks/issue-10-issue-sh-pr-sh-no-sanctioned-way-to-create-a-new.md → tasks/issue-14-pr-sh-worktrees-should-not-live-alongside.md
- `rs-agent-plugin README` --references--> `fix-mapped-issue SKILL.md`  [EXTRACTED]
  README.md → skills/fix-mapped-issue/SKILL.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Shared Doppler-sourced credential injection pattern across admin skills** — skills_doppler_secrets_skill_document, skills_opnsense_admin_references_lessons_learned_document, skills_patchmon_admin_references_lessons_learned_document [EXTRACTED 1.00]
- **Issue -> tasks -> implementation -> PR skill pipeline** — readme_document, skills_map_issue_to_tasks_skill_document, skills_fix_mapped_issue_skill_document, skills_pull_request_process_skill_document [EXTRACTED 1.00]
- **repo.toml stage-tier design, enforcing skill, and rollout task** — docs_superpowers_specs_2026_08_01_repo_standard_design_document, skills_repo_standard_skill_document, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_issue [EXTRACTED 1.00]
- **Six external repos rolled out under repo-standard stage tiers via issue #3 task 3** — tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_issue, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_roset_sh, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_iklo, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_what_about, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_guiltty, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_obsidian_hivemind, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_wawk_js [EXTRACTED 1.00]
- **Repo-standard design doc and skill jointly amended by issues #3 and #9** — docs_superpowers_specs_2026_08_01_repo_standard_design_document, skills_repo_standard_skill_document, tasks_issue_3_design_cross_repo_doc_folder_standard_repo_toml_issue, tasks_issue_9_repo_standard_design_make_repos_agent_agnostic_by_issue [INFERRED 0.85]

## Communities (18 total, 5 thin omitted)

### Community 0 - "pr.sh"
Cohesion: 0.29
Nodes (19): _bot_secret(), cmd_checks(), cmd_cleanup(), cmd_close(), cmd_comment(), cmd_comment_delete(), cmd_open(), cmd_push() (+11 more)

### Community 1 - "Issue #3 - Design: cross-repo doc/folder standard (repo.toml stage tiers) + repo-standard skill"
Cohesion: 0.21
Nodes (10): docs/superpowers/specs/2026-08-01-repo-standard-design.md, skills/repo-standard/SKILL.md, guiltty (external repo), iklo (external repo, in-progress tier), Issue #3 - Design: cross-repo doc/folder standard (repo.toml stage tiers) + repo-standard skill, obsidian-hivemind (external repo), roset.sh (external repo, prototype tier), wawk.js (external repo) (+2 more)

### Community 2 - "issue.sh"
Cohesion: 0.22
Nodes (15): cmd_close(), cmd_comment(), cmd_create(), cmd_fetch(), cmd_json(), cmd_label(), cmd_slug(), cmd_unmapped() (+7 more)

### Community 3 - "`hindsight-homelab-agents` skill: design proposal (not yet implemented)"
Cohesion: 0.17
Nodes (11): Body outline, Context, Frontmatter (proposed), `hindsight-homelab-agents` skill: design proposal (not yet implemented), Open questions for review, Out of scope for this proposal, Proposal, Relationship to `entrement.es`'s `homelab/scripts/hindsight-agents/` (+3 more)

### Community 4 - "pull-request-process SKILL.md"
Cohesion: 0.36
Nodes (5): rs-agent-plugin README, fix-mapped-issue SKILL.md, map-issue-to-tasks SKILL.md, issue-enrichment.md template, pull-request-process SKILL.md

### Community 5 - "doppler-secrets SKILL.md"
Cohesion: 0.29
Nodes (5): doppler-secrets SKILL.md, OPNsense API lessons learned, opnsense-admin SKILL.md, PatchMon API lessons learned, patchmon-admin SKILL.md

### Community 6 - "Git Branch Hygiene"
Cohesion: 0.29
Nodes (6): Common rationalizations, Core principle, Git Branch Hygiene, Step 1: Run the audit, Step 2: Resolve every NEEDS A DECISION and DIRTY WORKTREE item first, Step 3: Execute

### Community 7 - "audit.sh"
Cohesion: 0.40
Nodes (4): DIRTY, NEEDS_DECISION, SAFE, audit.sh script

### Community 9 - "Obsidian Bases Functions Reference"
Cohesion: 1.00
Nodes (3): Obsidian Bases Functions Reference, obsidian-bases skill-card, obsidian-bases SKILL.md

### Community 13 - "repo-standard.sh"
Cohesion: 0.28
Nodes (19): check_graphify_gitignore_behavior(), copy_specify_from_reference(), create_agents(), create_changelog(), create_dir_with_gitkeep_if_missing(), create_dot_gitignore(), create_readme(), create_required_path() (+11 more)

### Community 14 - "graphify as a standard dev-process artifact: `.gitignore` requirement design"
Cohesion: 0.11
Nodes (16): Cross-repo documentation/folder standard design doc, Per-stage doc/folder tier table (prototype/in-progress/released/archived), Audit behavior, Change to `repo-standard`, Context, Denylist vs allowlist, graphify as a standard dev-process artifact: `.gitignore` requirement design, Out of scope (+8 more)

### Community 16 - "test-repo-standard.sh"
Cohesion: 0.73
Nodes (5): assert_contains(), fail(), run_expect_fail(), run_expect_ok(), test-repo-standard.sh script

### Community 17 - "Agent Operations Guide"
Cohesion: 0.25
Nodes (7): Agent Operations Guide, Branch, Code Review Workflow, Documentation Expectations, Identity & Secrets, Quality Gate, Repo Notes

## Knowledge Gaps
- **16 isolated node(s):** `SAFE`, `NEEDS_DECISION`, `DIRTY`, `guiltty (external repo)`, `iklo (external repo, in-progress tier)` (+11 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 59 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Centralized worktree-root strategy (not sibling of main checkout)` connect `issue.sh` to `pr.sh`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **What connects `SAFE`, `NEEDS_DECISION`, `DIRTY` to the rest of the system?**
  _16 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `graphify as a standard dev-process artifact: `.gitignore` requirement design` be split into smaller, more focused modules?**
  _Cohesion score 0.10526315789473684 - nodes in this community are weakly interconnected._