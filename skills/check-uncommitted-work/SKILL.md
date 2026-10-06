---
name: check-uncommitted-work
description: Audit a shared Git checkout for branch drift and uncommitted, untracked, or ignored paths, then classify each item conservatively. Use at session start when the shared checkout may contain stray work, or when asked to check for uncommitted work.
---

# Check Uncommitted Work

Run this audit from the repository's shared checkout, not from a task worktree. Resolve the script beside this skill file. Usage:

    A=<this-skill's-own-directory>/check-uncommitted-work.sh
    "$A"

The script is read-only. It compares the current branch with the target of origin/HEAD, flags a non-default branch, and reports whether its HEAD is already an ancestor of the default branch. It lists changed, untracked, and ignored paths individually. A linked Git worktree is rejected so a task branch cannot be mistaken for the shared checkout. If origin/HEAD is unset, configure it with git remote set-head origin --auto; the audit does not guess a default branch or fetch.

## Classify each path

- KNOWN_NOISE: path matches one of the built-in local-tool patterns or a user pattern. Built-ins cover .pi/ and .skillkit/.
- REVIEW: open the file and inspect its content and status before deciding. Classify substantive task output, docs, or code as real work; if its purpose or ownership remains uncertain, call it ambiguous and ask the user. A filename, age, or status alone is not enough to decide.
- Root AGENTS.md and CLAUDE.md changes stay REVIEW by default because they may be legitimate user edits. If inspection confirms a machine-specific Available Skills rewrite, treat it as known tool noise; users who consistently want those paths categorized as noise can add patterns explicitly.

User patterns are additional Bash glob patterns, one per line, relative to the repository root, in XDG_CONFIG_HOME/check-uncommitted-work/noisy-paths or, when XDG_CONFIG_HOME is unset, $HOME/.config/check-uncommitted-work/noisy-paths. Blank lines and lines whose first character is # are ignored. For example, a custom pattern could be cache/tool-output/*.

Patterns only classify paths; they never delete, stash, restore, or otherwise change checkout state. Do not treat KNOWN_NOISE as permission to discard anything.
