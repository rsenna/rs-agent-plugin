# Issue #30 — Add a check-uncommitted-work skill

https://github.com/rsenna/rs-agent-plugin/issues/30

## Tasks

- [ ] **1 — Add shared-checkout detection and state classification**
  - Acceptance: a new skill detects default-branch drift (including an already-merged current branch), inspects uncommitted/untracked state per path, and classifies items as real work, configured local-tool noise, or ambiguous without guessing. The noise-pattern list is user-extensible; settle its configuration mechanism against the open question before implementation.
  - Verify: focused manual scenario covers clean/default-branch, merged-branch drift, and mixed tracked/untracked paths with known-noise and ambiguous examples; find skills -name '*.sh' -print0 | xargs -0 shellcheck; graphify update .
  - Files: skills/check-uncommitted-work/

- [ ] **2 — Implement conservative triage, confirmed recovery, and branch restoration**
  - Acceptance: real work is routed to a fresh worktree on the current default branch and handed off to pull-request-process; tool noise is recommended for stashing (with a targeted .gitignore suggestion where appropriate); ambiguous state is surfaced for a person. Do not discard or overwrite user state. Restore/fast-forward the shared checkout only after recoverable work is extracted and the user explicitly confirms the checkout-changing action. Depends on Task 1.
  - Verify: focused manual scenario demonstrates recommendations for all three classifications, refusal to proceed without confirmation, and branch restoration only after extraction plus confirmation; find skills -name '*.sh' -print0 | xargs -0 shellcheck; graphify update .
  - Files: skills/check-uncommitted-work/

- [ ] **3 — Document invocation and related-skill boundaries**
  - Acceptance: the skill documents its invocation, default-branch/state audit, triage and confirmation behavior, and handoff boundary; git-branch-hygiene cross-references this shared-checkout audit while retaining its distinct accumulated-branch/worktree scope. Document the chosen noisy-pattern configuration. Treat GitHub path cross-referencing as optional/best-effort unless the open question is resolved otherwise. Depends on Tasks 1–2.
  - Verify: documentation self-review confirms examples and cross-references match the behavior from Tasks 1–2; find skills -name '*.sh' -print0 | xargs -0 shellcheck; graphify update .
  - Files: skills/check-uncommitted-work/SKILL.md, skills/git-branch-hygiene/SKILL.md
