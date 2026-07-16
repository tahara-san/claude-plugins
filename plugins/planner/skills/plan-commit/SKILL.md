---
name: plan-commit
description: Wraps up a planning session — removes the task directory implemented in THIS session (and the out-of-scope issue files it resolved), then stages everything, commits once, and pushes to the current branch (or a user-specified target branch). Use only in the same session as /plan-doc or /plan-code, after the work is done — triggered by "/plan-commit", "commit the plan", "wrap up and commit", "clean up and push this task". Fully automatic — no confirmation gate; verifies task completeness first and blocks if unchecked items remain.
allowed-tools: Read, Edit, Glob, Grep, Bash(git *), Bash(rm *), Bash(ls *), Bash(find *), AskUserQuestion
---

# plan-commit

Session wrap-up: removes the task directory this session implemented (via `/plan-doc` + `/plan-code`) and the issue files this session resolved, then commits everything in ONE commit and pushes.

## Usage

```
/plan-commit                  # commit + push on the current branch
/plan-commit <target-branch>  # switch/create <target-branch>, commit + push there
```

## Core Rules

> **Session-scoped, never a global scan.** Only remove the task directory(ies) and issue files that THIS session created, implemented, or resolved — identified from the conversation context. Cleaning up arbitrary old tasks in `tasks/` is `/plan-clean`'s job; do not absorb it.

> **Fully automatic — no confirmation gate.** Invoking this skill IS the user's consent to delete the session's task docs, commit, and push. Do not stop to ask "proceed?" on the happy path. The ONLY stops are the blocking conditions in Steps 1, 2, and 4 (unidentifiable artifacts, incomplete task, detached HEAD / failed switch).

## Procedure

### Step 1: Identify This Session's Artifacts

From the conversation context of THIS session, identify:

**A. Task directory(ies)** — `tasks/<task-name>/` that `/plan-doc` created or `/plan-code` implemented in this session.

**B. Resolved issue files** — out-of-scope issue files that this session's work resolved. Recognise the same reference forms as `/plan-clean` Step 4, across all three layouts:
- The implemented task's `spec.md` (or `todo.md`) has a `Source:` line or markdown link pointing at the issue file — priority-bucketed (`tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md`), manual-tier (`<priority>/manual/...`), or legacy flat (`tasks/out-of-scope-issues/<short-kebab>.md`). When matching by kebab name, strip the optional `YYYYMMDD_` date prefix and any `manual/` segment — they are metadata, not identity.
- The issue body contains `Status:\s*(Resolved|Fixed|Done)` (case-insensitive) — only count it if this session set that status or did the resolving work.
- The session ran the `/plan-issues` → `/plan-doc` → `/plan-code` flow for the issue.
- Single-file layout: the resolved issue is a `##`/`###` section inside `tasks/out-of-scope-issues.md`.

Find the project root with:
```bash
git rev-parse --show-toplevel 2>/dev/null || pwd
```

> **BLOCKING:** If no task directory is identifiable from the session context (e.g., the skill was invoked in a fresh session), do NOT fall back to scanning `tasks/` and guessing. Ask the user via `AskUserQuestion` which task directory to wrap up — or point them to `/plan-clean` if they want a general cleanup — and stop until answered.

### Step 2: Verify Completeness (BLOCKING)

Apply `/plan-clean`'s core rule, scoped to the session's task directory(ies):

- **`progress.md` exists** → it is authoritative: every phase row must indicate done AND the Completion Criteria checklist (if present) must have zero `- [ ]` items. Stale `- [ ]` in `todo-phase-N.md` files are ignored when both hold.
- **No `progress.md`** → every `- [ ]` across ALL `*.md` files in the directory must be `- [x]` — including verification, testing, build, and QA items.

If ANY task directory is incomplete: list its unchecked items, delete NOTHING, commit NOTHING, and stop. The only bypass is the user explicitly replying "remove anyway" (or equivalent) after seeing the block — a standing "work without stopping" instruction is NOT that bypass.

> `/plan-clean`'s uncommitted-changes signal does NOT apply here — committing the working tree is this skill's purpose.

### Step 3: Remove

For each identified artifact:

**Task directory:**
```bash
rm -rf <project-root>/tasks/<task-name>/
```

**Resolved issue file (priority-bucketed, manual-tier, or legacy flat):** pass the full discovered path to `rm`.

**Resolved issue section (single-file layout):** use `Edit` to remove the section heading through the next sibling-or-higher heading (or EOF), plus any trailing `---` rule. If `tasks/out-of-scope-issues.md` then contains only whitespace or a bare title, delete the file.

Leave empty directories in place — including `tasks/out-of-scope-issues/` and any now-empty priority subdir. The project convention expects them to exist.

### Step 4: Resolve the Target Branch

- **No argument** → stay on the current branch.
- **`<target-branch>` given** → switch before committing, carrying the dirty working tree along:
  ```bash
  git switch <target-branch>       # if it exists locally or as a remote-tracking branch
  git switch -c <target-branch>    # otherwise, create it from the current HEAD
  ```
  If the switch fails (e.g., local-change conflicts), stop and report — do not stash or discard anything.
- **Detached HEAD** → blocking: ask the user which branch to commit to before proceeding.

### Step 5: Commit (one commit for everything)

From the project root:
```bash
git add -A
git commit -m "<message>"
```

One commit covers the session's implementation changes AND the doc removals. Message shape:

- **Subject:** `<task title>: <one-line summary derived from spec.md's Goal>` (read the Goal before deleting the task dir in Step 3).
- **Body:** one line noting the cleanup, e.g. `Remove completed task docs (tasks/<task-name>/) and resolved issue files.`

### Step 6: Push

```bash
git push                           # upstream already set
git push -u origin <branch>        # no upstream yet
```

NEVER pass `--force` / `--force-with-lease`. If the push is rejected or fails (non-fast-forward, auth, no remote), stop and report — the commit stays local; do not retry with force and do not attempt a pull/rebase on your own.

### Step 7: Final Report

Summarize:
1. Deleted paths (task dirs + issue files/sections).
2. Commit hash + subject line.
3. Branch committed to, and the push result (pushed / rejected-with-reason).
4. Any issue files deliberately left in place (found but not attributable to this session).

## Safety Rules

- **Never delete files outside `<project-root>/tasks/`.** Resolve every candidate path against the project root and verify the prefix before any `rm`.
- **Only session-identified paths.** Never delete a task dir or issue file just because it "looks done" — if this session didn't produce or resolve it, it is `/plan-clean`'s territory.
- **Never delete top-level files in `tasks/`** (e.g., `tasks/lessons.md`, `tasks/todo.md`).
- **Concrete paths only** — no `..`, no unexpanded globs in `rm` arguments.
- **No force push, ever.**
- **Any git failure mid-sequence** (switch, add, commit, push) → stop immediately and report the exact state, e.g. "docs removed and committed, but push rejected — commit <hash> is local on <branch>". Never leave the user guessing what happened.
