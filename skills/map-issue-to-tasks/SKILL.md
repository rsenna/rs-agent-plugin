---
name: map-issue-to-tasks
description: Turn a GitHub issue into an enriched analysis plus a concrete task breakdown. Use when asked to map/analyse/enrich/scope a GitHub issue, break an issue into tasks, or plan the work for an issue before implementing. Posts the enrichment as a non-destructive issue comment, labels the issue "mapped", and writes tasks to tasks/issue-<n>-<slug>.md.
---

# Map Issue → Tasks

Steps 1–3 of the issue lifecycle: **analyse an open issue, enrich it against a
template, and break it into a dependency-ordered task list.** Implementation is
a separate skill (`fix-mapped-issue`).

Plumbing is in **`issue.sh`**, next to this file (a sibling of this `SKILL.md`,
wherever your installer placed this skill — e.g. `~/.claude/skills/map-issue-to-tasks/`
or `~/.agents/skills/map-issue-to-tasks/`).
The enrichment template is at `templates/issue-enrichment.md`, relative to that same directory.

## Do this

1. **Fetch.** `issue.sh fetch <n>` — read title, body, labels, and existing
   comments. Note related/duplicate issues. If it's already labeled `mapped`,
   say so and confirm before redoing the work.
2. **Explore the codebase** for the modules/files this touches. Use the
   project's own affordances (e.g. `what-about` has a `run-what-about` skill and
   a `tasks/` convention). Cite concrete file paths.
3. **Enrich.** Fill the template (copy it, replace the `<!-- … -->` guidance):
   Analysis, Context & affected areas, Acceptance criteria, Non-goals, Open
   questions, Task breakdown. Write it to a scratch file.
4. **Derive tasks.** Run the `spec-driven-development` and
   `planning-and-task-breakdown` skills to turn the acceptance criteria into
   small, verifiable, dependency-ordered tasks. Render them in **the project's
   task format** — match an existing example if the repo has one (e.g.
   `what-about`'s `tasks/todo.md`: `**ID — Title** 🔒gate`, then `Acceptance:` /
   `Verify:` / `Files:`, where **`Verify:` always includes the project's quality
   gate**; add dependency/milestone notes à la `tasks/plan.md`). If the repo has
   no `tasks/` convention, create `tasks/issue-<n>-<slug>.md` with that shape.
   Regardless of which format applies, **every task heading gets a leading
   checkbox** — `- [ ] **ID — Title** 🔒gate` — even when matching an
   existing project convention that doesn't itself use one, so
   `fix-mapped-issue` always has something unambiguous to tick after each
   task merges. If `tasks/issue-<n>-<slug>.md` already exists for this issue
   from before this convention (headings with no leading checkbox), retrofit
   one onto every heading while you're editing the file — `- [x]` for tasks
   the file already marks done/merged, `- [ ]` for the rest — rather than
   adding new checkbox-only headings alongside old checkbox-less ones.
5. **Write outputs (non-destructive):**
   - Tasks → **`tasks/issue-<n>-<slug>.md`** (`issue.sh slug <n>` gives the
     `<n>-<slug>` stem). Never overwrite an unrelated existing task file.
   - Enrichment → a **GitHub issue comment** via `issue.sh comment <n> <file>`.
     The original issue body is **left untouched**.
   - **Keep the tasks file lean.** It's read every time an agent picks up this
     issue, so prefer terse, scannable task entries over prose — a leaner file
     pays off repeatedly.
6. **Label it.** `issue.sh label <n>` — tags the issue `mapped` (creating the
   label on first use). This is what lets `issue.sh unmapped` distinguish
   issues still needing this treatment from ones already scoped. Do this last,
   after the enrichment comment has actually posted.

## Review before posting

Default to **`DRY_RUN=1`** first — it prints the comment (and the label action)
instead of posting, so you (and the user) can check it. Post for real only once
it reads well.

```bash
I=<this-skill's-own-directory>/issue.sh   # wherever your installer put this skill
"$I" unmapped                          # which open issues still need mapping
"$I" fetch 24                          # read the issue
"$I" slug  24                          # -> 24-show-a-notification-when-a-profile-is-re-published
DRY_RUN=1 "$I" comment 24 enrich.md    # preview the enrichment comment
"$I" comment 24 enrich.md              # post it for real
"$I" label 24                          # tag it mapped
```

## Filing a follow-up issue

Mapping an issue sometimes surfaces a concern that belongs in a *different*
repo — a tooling gap in a shared skill, a design question that's really about
another project. `issue.sh create <repo> <title> <file>` opens a new issue
under the same bot identity as every other `issue.sh`/`pr.sh` call, so this
never needs an ad-hoc `gh issue create` (which would use whatever `gh auth`
happens to be ambient — exactly the identity leak this tooling exists to
prevent). `<repo>` is `owner/name`, so it can target any repo, not just the
one the agent is currently sitting in.

```bash
I=<this-skill's-own-directory>/issue.sh   # wherever your installer put this skill
DRY_RUN=1 "$I" create rsenna/rs-agent-plugin "Title" body.md   # preview
"$I" create rsenna/rs-agent-plugin "Title" body.md             # post it for real
```

This is not part of the numbered workflow above — it's a standalone
capability for when mapping (or any other) work surfaces a concern that
needs its own tracked issue elsewhere.

## Boundaries

- Do not edit the issue body, do not close the issue, do not start implementing
  — that's `fix-mapped-issue`.
- Flag 🔒 ask-first gates in the tasks (new deps, DB migrations, CI/secret
  changes) so implementation pauses for approval.
- Keep each task small enough to ship as its own PR (one concern).
