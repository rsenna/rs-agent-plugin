# Issue #33 — Cross-project skill management

https://github.com/rsenna/rs-agent-plugin/issues/33

## Tasks

Dependency order: Task 1 confirms the interface and safety contract; Tasks 2–4 build the inventory, update, and parity capabilities; Task 5 documents and validates the complete workflow. Keep the tool generic: do not depend on Guiltty-specific paths or names.

- [ ] **1 — Confirm the skill-fleet tool and safe-update contract** 🔒ask-first
  - Acceptance: agree whether the deliverable is one reusable skill/CLI (recommended) and settle the default behavior for modified installs, backup retention, and declared patch overlays before implementation. Record the three states—upstream, re-published/adapted, and metadata-less/local—and the chosen interface in a design note.
  - Verify: review the proposed behavior against all issue acceptance criteria and confirm no Guiltty-specific assumptions or new dependencies are required without approval.
  - Files: `docs/superpowers/specs/2026-10-21-cross-project-skill-management-design.md`

- [ ] **2 — Add installed-skill inventory and drift reporting**
  - Acceptance: tooling reads the installed inventory from `gh skill list --json skillName,sourceURL,agentHosts,scope,version`, groups duplicate per-agent rows by skill, and reports upstream/re-published/local state. For metadata-backed installs, it distinguishes clean from locally modified content against the recorded `github-tree-sha` while accounting for installer-injected `SKILL.md` metadata and relevant normalization; metadata-less skills are explicitly reported. Extra untracked files are not falsely reported as upstream drift.
  - Verify: add fixture-driven tests covering clean and edited installs, injected metadata, line endings/normalization, duplicate host rows, and metadata-less skills; run the tests, `find skills -name '*.sh' -print0 | xargs -0 shellcheck`, and `graphify update .`.
  - Files: `skills/skill-fleet-management/SKILL.md`, `skills/skill-fleet-management/skill-fleet.sh`, `skills/skill-fleet-management/test-skill-fleet.sh`

- [ ] **3 — Add a safe skill-update workflow**
  - Acceptance: the update command uses drift detection before invoking `gh skill update`; it never overwrites a locally modified skill without first preserving a recoverable backup and reporting what will be replaced and where the backup is. Default behavior for modified skills is the contract agreed in Task 1. If declared overlays are in scope, reapply them after update and report conflicts rather than silently dropping edits. Clean skills can use the normal update path.
  - Verify: fixture/mock tests prove clean installs update, modified installs are protected by default, and any explicit update path leaves a backup and reports its location; test failure paths (update failure, backup failure, and overlay conflict if supported). Run the tests, `find skills -name '*.sh' -print0 | xargs -0 shellcheck`, and `graphify update .`.
  - Files: `skills/skill-fleet-management/skill-fleet.sh`, `skills/skill-fleet-management/test-skill-fleet.sh`

- [ ] **4 — Add idempotent agent-parity installation**
  - Acceptance: given a reference agent and target agent, the tool groups the `gh skill list` rows by skill, unions their agent hosts, and installs only missing reference skills from each recorded `sourceURL`/skill name. It does not install unrelated skills merely because they exist in a source repository. Running twice makes no further changes; metadata-less skills are surfaced with an actionable warning rather than silently treated as installable.
  - Verify: mock `gh skill list` and install responses for multiple hosts, duplicate rows, missing target skills, unrelated source-repo skills, and metadata-less skills; assert a second run is a no-op. Run the tests, `find skills -name '*.sh' -print0 | xargs -0 shellcheck`, and `graphify update .`.
  - Files: `skills/skill-fleet-management/skill-fleet.sh`, `skills/skill-fleet-management/test-skill-fleet.sh`

- [ ] **5 — Document the skill lifecycle and validate the end-to-end interface**
  - Acceptance: the new skill documentation explains upstream, re-published/adapted, and local skills; recommends upstreaming changes first, re-publishing when appropriate, and patch overlays only as a last resort; documents drift reporting, safe update, parity usage, backup behavior, and limitations. The README links to the capability without adding a separately maintained skill manifest. All acceptance criteria from issue #33 are covered by tests.
  - Verify: exercise documented commands with fixtures or dry-run mode; review README/install wording for consistency with existing `skills/<name>/SKILL.md` discovery and both documented installation paths. Run the full script tests, `find skills -name '*.sh' -print0 | xargs -0 shellcheck`, and `graphify update .`.
  - Files: `skills/skill-fleet-management/SKILL.md`, `skills/skill-fleet-management/skill-fleet.sh`, `skills/skill-fleet-management/test-skill-fleet.sh`, `README.md`
