# Issue #30 — Add a check-uncommitted-work skill

https://github.com/rsenna/rs-agent-plugin/issues/30

## Tasks

- [ ] **1 — Add shared-checkout detection and state classification**
  - Acceptance: a new skill detects local default-branch drift (behind/ahead/diverged) and non-default branches already integrated by ancestry, cherry-pick, or squash-equivalent patch; inspects changed, untracked, and recursively ignored state per path; classifies known local-tool noise versus items requiring human review; and provides a read-only inventory of linked worktrees with their branch, lock, and dirty/ignored state. Worktree cleanup is handed off to `git-branch-hygiene`, never performed by this audit. The noise-pattern list is user-extensible.
  - Verify: fixture tests cover in-sync/behind/ahead default branches, ancestry and squash-integrated branches, nested ignored paths with configured patterns, a `TMPDIR` inside the checkout, and clean/dirty linked-worktree inventory; `find skills -name '*.sh' -print0 | xargs -0 shellcheck`; `graphify update .`.
  - Files: skills/check-uncommitted-work/

- [ ] **2 — Implement conservative triage, confirmed recovery, and branch restoration**
  - Acceptance: real work is routed to a fresh worktree on the current default branch and handed off to pull-request-process; tool noise is recommended for stashing (with a targeted .gitignore suggestion where appropriate); ambiguous state is surfaced for a person. Do not discard or overwrite user state. Restore/fast-forward the shared checkout only after recoverable work is extracted and the user explicitly confirms the checkout-changing action. Depends on Task 1.
  - Verify: focused manual scenario demonstrates recommendations for all three classifications, refusal to proceed without confirmation, and branch restoration only after extraction plus confirmation; find skills -name '*.sh' -print0 | xargs -0 shellcheck; graphify update .
  - Files: skills/check-uncommitted-work/

- [ ] **3 — Document invocation and related-skill boundaries**
  - Acceptance: the skill documents its invocation, branch/path/worktree audit, triage and confirmation behavior, and handoff boundary; it sends stale-worktree classification and cleanup to `git-branch-hygiene` rather than duplicating removal logic. `git-branch-hygiene` cross-references the shared-checkout audit while retaining its distinct accumulated-branch/worktree scope. Document the noisy-pattern configuration. Treat GitHub path cross-referencing as optional/best-effort unless the open question is resolved otherwise. Depends on Tasks 1–2.
  - Verify: documentation self-review confirms examples and cross-references match the behavior from Tasks 1–2; find skills -name '*.sh' -print0 | xargs -0 shellcheck; graphify update .
  - Files: skills/check-uncommitted-work/SKILL.md, skills/git-branch-hygiene/SKILL.md
