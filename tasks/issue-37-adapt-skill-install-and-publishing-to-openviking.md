# Issue #37 — Adapt skill install and publishing to OpenViking

https://github.com/rsenna/rs-agent-plugin/issues/37

## Tasks

Dependency order: Task 1 unblocks the rest by confirming go/no-go and exact OpenViking import requirements. Tasks 2–4 implement packaging, provenance, and migration/docs. Task 5 retires superseded issue-33 planning artifacts only after the new path is documented.

- [ ] **1 — Confirm OpenViking go/no-go and import contract** 🔒ask-first
  - Acceptance: capture the outcome of rsenna/emacs-replicant#35 and the concrete ingest requirements this repo must satisfy (required metadata/files/commands). If #35 is not approved, stop this issue and explicitly point back to rsenna/emacs-replicant#25 as the fallback track.
  - Verify: link the exact decision source and requirement list in a tracked note; run `find skills -name '*.sh' -print0 | xargs -0 shellcheck` and `graphify update .`.
  - Files: `docs/superpowers/specs/2026-11-02-openviking-adoption-contract.md` (new or equivalent), `tasks/issue-37-adapt-skill-install-and-publishing-to-openviking.md`

- [ ] **2 — Add OpenViking packaging/metadata support without breaking current skill layout**
  - Acceptance: add the OpenViking-required packaging/metadata for all skills while preserving `skills/<name>/SKILL.md` compatibility unless the approved contract explicitly requires a layout change.
  - Verify: run the OpenViking ingestion/validation flow defined by Task 1; run `find skills -name '*.sh' -print0 | xargs -0 shellcheck` and `graphify update .`.
  - Files: packaging/metadata files introduced by the approved OpenViking contract, relevant `skills/*` metadata files

- [ ] **3 — Record third-party skill provenance and pinned source revision**
  - Acceptance: document upstream source and pinned revision for non-authored skills currently vendored here (`clawhub.obsidian-bases`, `clawhub.obsidian-cli`) so provenance survives migration.
  - Verify: provenance records include repo URL + revision/commit and are cross-checked against installed skill contents; run `find skills -name '*.sh' -print0 | xargs -0 shellcheck` and `graphify update .`.
  - Files: `README.md` and/or `docs/superpowers/specs/2026-11-02-openviking-adoption-contract.md` (or a dedicated provenance file if chosen)

- [ ] **4 — Update install and migration documentation for OpenViking + Replicant handoff**
  - Acceptance: update README install guidance to include the OpenViking path and clearly state what remains valid for other installers; update AGENTS operational guidance only where needed; document switchover handling for machines with `gh skill`-installed copies or explicitly delegate it to rsenna/emacs-replicant#34.
  - Verify: docs are internally consistent (README + AGENTS + skill docs), contain no stale `gh skill` migration claims, and include explicit migration ownership; run `find skills -name '*.sh' -print0 | xargs -0 shellcheck` and `graphify update .`.
  - Files: `README.md`, `AGENTS.md` (if needed), any affected `skills/*/SKILL.md`

- [ ] **5 — Retire superseded issue-33 planning artifact references**
  - Acceptance: remove or mark obsolete references that imply issue #33 is still active implementation scope, while preserving historical incident evidence in closed issue text as stated in #37.
  - Verify: links in tasks/spec/docs point to #37 as active track and do not direct implementers back to obsolete #33 execution plans; run `find skills -name '*.sh' -print0 | xargs -0 shellcheck` and `graphify update .`.
  - Files: `tasks/issue-33-cross-project-skill-management-safe-updates-drift.md` (status note or archive handling), any cross-references in docs/tasks
