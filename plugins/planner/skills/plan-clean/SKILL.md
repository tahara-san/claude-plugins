---
name: plan-clean
description: Removes completed task directories and stale issue articles from a project's `tasks/` directory. A task is "complete" only when EVERY checklist item (including verification/testing/QA items) is checked off — implementation done but tests still pending counts as INCOMPLETE and is preserved. Use this whenever the user wants to clean up the tasks/ directory — triggered by "/plan-clean", "clean up tasks", "remove completed task plans", "purge completed tasks", "tidy the tasks directory". Always classifies + confirms with the user before any deletion.
allowed-tools: Read, Edit, Glob, Grep, Bash(git rev-parse *), Bash(git status *), Bash(ls *), Bash(rm *), Bash(find *), AskUserQuestion, EnterPlanMode, ExitPlanMode
---

# plan-clean

Scans `tasks/` for task subdirectories and out-of-scope issue files, classifies each as **complete** / **incomplete** / **ambiguous**, and removes only the complete ones — after explicit user confirmation.

## Core Rule

> **A task is complete only when EVERY checkable item (`- [ ]`) in its plan files is checked (`- [x]`).** This includes verification, testing, build, and QA items. If implementation is done but tests are still pending, the task is **NOT** complete and must be preserved.

## Usage

```
/plan-clean              # scan, classify, then prompt for confirmation
/plan-clean --dry-run    # scan and classify only, never delete
```

## Step 0: Enter Plan Mode (MANDATORY before Step 1)

Call `EnterPlanMode` immediately so the scan + classification + report +
ambiguous-bucket review (Steps 1–6.1, 6.2) all run inside plan mode. Plan
mode's session reminder explicitly supersedes any other instruction —
including a session-level "work without stopping for clarifying questions"
reminder injected by Auto Mode — which keeps Step 6's BLOCKING GATE intact
and prevents silent deletion absorption.

If `--dry-run` was passed, you still call `EnterPlanMode` so Steps 1–5 run
in plan mode for consistency, but you will NOT call `ExitPlanMode` at the
Step 6 boundary — instead, output the report and stop while still in plan
mode (the user remains free to exit plan mode themselves).

If the session is already in plan mode when this skill starts, do NOT call
`EnterPlanMode` again — but DO call `ExitPlanMode` at Step 6.3 (unless
`--dry-run` was passed) so the user gets the structured final-confirmation
point before any deletions run.

## Procedure

### Step 1: Locate the tasks/ Directory

1. Find the project root:
   ```bash
   git rev-parse --show-toplevel 2>/dev/null || pwd
   ```
2. Verify `<project-root>/tasks/` exists. If not, tell the user there is nothing to clean and stop.

### Step 2: Enumerate Candidates

Two categories to classify:

**A. Task subdirectories** — every immediate subdirectory of `tasks/` EXCEPT:
- `out-of-scope-issues/` (handled separately in category B)
- Any directory whose name starts with `.` (hidden)

**B. Out-of-scope issue articles** — three layouts may coexist:
- **Priority-bucketed** (current): `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` where `<priority>` is one of `critical`, `high`, `medium`, `low`, `proposal`, `other`. Files MAY also live one level deeper under `<priority>/manual/<YYYYMMDD>_<short-kebab>.md` — the **manual-tier**: parked for human investigation/intervention. The `manual/` segment is recognised (do NOT emit the unrecognised-subdir warning for it). Manual-tier files are classified by the same rules as priority-root files in Step 4 — default **ambiguous**, promote to **complete** only on a hard signal.
- **Legacy flat**: `tasks/out-of-scope-issues/<short-kebab>.md` (one issue per file, no priority subdir, no date prefix) — still recognised for unmigrated projects
- **Single-file**: `tasks/out-of-scope-issues.md` (treat each `##`/`###` section as one issue)

Discover candidate files with a recursive scan so all three layouts are picked up:
```bash
find <project-root>/tasks/out-of-scope-issues -type f -name '*.md' 2>/dev/null
```
Files under an unrecognised subdir of `out-of-scope-issues/` (e.g., `archive/`, `wip/`, anything not in the six-value priority set, or anything nested under a priority other than `manual/`) are NOT in scope — skip them and emit `[warn] unrecognised subdir: <path>` so the user can move/rename manually. The `<priority>/manual/` tier IS recognised — never warn on it.

Also check whether `<project-root>/tasks/out-of-scope-issues.md` exists; if so, read it and split into sections.

Top-level files in `tasks/` (e.g., `tasks/lessons.md`) are NEVER touched.

### Step 3: Classify Each Task Subdirectory

For each task subdirectory, read every `*.md` file inside it (typically `progress.md`, `todo.md`, `todo-phase-*.md`, `spec.md`, `ignored-warnings.md`).

Apply this decision tree, in order. **Stop at the first matching row.**

| Signal | Classification |
|--------|----------------|
| `git status --porcelain <dir>` shows uncommitted changes | **incomplete** — KEEP, warn the user |
| Plan-file body contains an `ignored-warnings.md` reference AND that file has `- [ ]` items | **incomplete** — KEEP |
| **`progress.md` exists** — see "Authoritative `progress.md` rule" below | use that result |
| Any `*.md` in the dir has at least one `- [ ]` (unchecked) line (no `progress.md`) | **incomplete** — KEEP |
| At least one `- [x]` AND zero `- [ ]` across ALL `*.md` in the dir (no `progress.md`) | **complete** — candidate for delete |
| No checkboxes at all (pure prose plan) | **ambiguous** — ask the user |

Then re-scan body text of all `*.md` files (regardless of branch above) for any of these (case-insensitive). If a match is found and the task is currently classified **complete**, downgrade to **ambiguous** and surface the matched line in the report:

- `TODO:` / `FIXME:` / `XXX:`
- `pending` / `not yet` / `still need(s|ed)?` / `blocker` / `blocked on`
- `needs verification` / `needs testing` / `needs review` / `awaiting`

(`pending` etc. legitimately appear in finished plans — e.g., "originally pending, now done" — so this is a soft downgrade, not a hard exclusion.)

#### Authoritative `progress.md` rule (large multi-phase plans)

`plan-code`'s update-progress step keeps `progress.md` authoritative but sometimes leaves stale `- [ ]` items in per-phase files (`todo-phase-N.md`). When `progress.md` exists, use IT as the source of truth and ignore per-phase checkbox staleness:

1. Locate the phase-status section in `progress.md`. Typical patterns to scan for (case-insensitive):
   - A "Phases" / "Progress" / "Status" section with rows or bullets per phase, each marked complete/done/✓ or pending/in-progress
   - A `- [ ]` / `- [x]` checklist at the top of `progress.md` covering each phase
   - A "Completion Criteria" section near the end with its own checklist
2. The task is **complete** when BOTH:
   - Every phase row indicates done (e.g., `Phase 1: COMPLETE`, `- [x] Phase 1`, `Phase 2 ✓`).
   - The "Completion Criteria" checklist (if present) has zero `- [ ]` items.
3. If either is unsatisfied → **incomplete**.
4. If `progress.md`'s phase-tracking format is unfamiliar / unparseable → **ambiguous** (do not silently fall through to per-phase scanning).
5. Stale `- [ ]` items inside `todo-phase-N.md` are IGNORED for the completion decision when (1)–(2) hold. They are still listed in the report's "complete — note" line so the user sees the discrepancy and can re-tick them in a follow-up if they want clean phase files.

When no `progress.md` exists, fall through to the per-phase / `todo.md` scan rows in the table above (this is the "small plan" path).

### Step 4: Classify Each Out-of-Scope Issue

Issue articles are bug reports, not implementation plans — they typically have no checkboxes. Default to **ambiguous**, then promote to **complete** ONLY if one of these hard signals fires:

- A task subdirectory exists whose `spec.md` (or `todo.md`) contains a `Source:` line OR markdown link pointing at this issue, AND that task is **complete** per Step 3. Match the issue against any of these reference forms (whichever appears in the source-link path):
  - Priority-bucketed (current): `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md`
  - Priority-bucketed without date prefix: `tasks/out-of-scope-issues/<priority>/<short-kebab>.md` — legacy match path only; new files MUST use the date-prefixed form above.
  - Priority-bucketed manual tier (current): `tasks/out-of-scope-issues/<priority>/manual/<YYYYMMDD>_<short-kebab>.md` (legacy `<priority>/manual/<short-kebab>.md` form also recognised; new files MUST use the date-prefixed form)
  - Legacy flat: `tasks/out-of-scope-issues/<short-kebab>.md` — still recognised for unmigrated projects
  - Single-file fragment: `tasks/out-of-scope-issues.md#<heading-anchor>`

  When matching by **kebab name only** (e.g., the spec links to a flat path but the actual file is now priority-bucketed, or the spec links to the priority root but the actual file is under `manual/`, or vice versa), strip the optional `YYYYMMDD_` date prefix from the filename first — the prefix is metadata, not part of the issue identity. Match on the remaining kebab. The `manual/` segment is also stripped for kebab-only matching: a spec linking to `<priority>/<kebab>.md` matches a real file at `<priority>/manual/<kebab>.md` (and vice versa).
- The issue body contains a top-level line matching `Status:\s*(Resolved|Fixed|Done)` (case-insensitive).

For single-file-layout issues (sections inside `tasks/out-of-scope-issues.md`), apply the same rules per section.

### Step 5: Build the Classification Report

Produce a single report grouped as:

```
## Complete (will delete after confirmation)
- tasks/<task-a>/                                            — todo.md: all 12 checkboxes checked
- tasks/<task-b>/                                            — progress.md: all 4 phases COMPLETE, completion criteria all checked
                                                               (note: todo-phase-2.md has 3 stale `- [ ]` items, ignored per progress.md)
- tasks/out-of-scope-issues/medium/20260502_<x-kebab>.md     — addressed by completed tasks/<task-a>/
- tasks/out-of-scope-issues/<legacy-x>.md                    — addressed by completed tasks/<task-b>/

## Incomplete (will keep)
- tasks/<task-c>/                                            — 3 of 8 unchecked: "Verify build passes", "Run E2E", "Update CHANGELOG"
- tasks/<task-d>/                                            — uncommitted changes in working tree
- tasks/<task-g>/                                            — progress.md: Phase 3 still IN PROGRESS

## Ambiguous (asking before any action)
- tasks/<task-e>/                                            — pure prose plan, no checkboxes
- tasks/<task-f>/                                            — all checkboxes checked, but body says "TODO: revisit auth flow"
- tasks/<task-h>/                                            — progress.md exists but phase-status format unparseable
- tasks/out-of-scope-issues/high/20260415_<y-kebab>.md       — no linked completed task and no Status: line
- tasks/out-of-scope-issues/archive/<z-kebab>.md             — unrecognised subdir 'archive/' (skipped, surface only)
```

For each "Incomplete" entry, include the unchecked-item snippet (or the uncommitted-change reason) so the user can tell at a glance what's still open. For each "Ambiguous" entry, include the specific signal that triggered the downgrade.

### Step 6: Confirm Before Deleting

> **MANDATORY — never delete without explicit user confirmation. This step is a blocking gate.**

If `--dry-run` was passed: output the Step 5 report and stop. Do not run any `rm` or `Edit`. Stay in plan mode (do not call `ExitPlanMode`).

Otherwise:

#### 6.1 — Output the Report

Output the Step 5 report.

#### 6.2 — Resolve Ambiguous Entries

For the **Ambiguous** group, ask the user once (a single AskUserQuestion call with the list, or a plain-text prompt) which entries to delete. Default = keep. Accept either "delete A, C" or "keep all" / "delete all".

#### 6.3 — Exit Plan Mode for Final Approval (MANDATORY before Step 7)

Call `ExitPlanMode`. The plan you submit for approval is the **final
"will delete" list** — Complete entries plus user-approved Ambiguous
entries from Step 6.2. Spell every path explicitly:

- **Task subdirectories that will be `rm -rf`'d** — full paths, one per line
- **Out-of-scope issue files that will be `rm`'d** — full paths, including
  whether each is priority-bucketed, legacy-flat, or manual-tier
- **Single-file-layout sections that will be removed via `Edit`** — list
  the section heading + parent file path for each

`ExitPlanMode`'s approval here REPLACES the previous "explicit final
confirmation" step. Approval = proceed to Step 7. Any non-approval reply
(redirect, edit, "wait", "no", or anything other than approval) aborts
cleanly with no deletions.

### Step 7: Delete

After confirmation, for each approved entry:

**Task subdirectory:**
```bash
rm -rf <project-root>/tasks/<task-name>/
```

**Out-of-scope issue file (directory layout — priority-bucketed OR legacy flat):**
Pass the file's full discovered path to `rm`. Both shapes are valid:
```bash
# Priority-bucketed:
rm <project-root>/tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md
# Legacy flat:
rm <project-root>/tasks/out-of-scope-issues/<short-kebab>.md
```

**Out-of-scope issue section (single-file layout):**
- Use `Edit` to remove the section heading line through the next sibling-or-higher heading (or end-of-file).
- If a `---` rule immediately followed the section, remove it too.
- After all approved sections are removed, if `tasks/out-of-scope-issues.md` contains only whitespace or only a top-level title with no remaining issues, delete the file:
  ```bash
  rm <project-root>/tasks/out-of-scope-issues.md
  ```

After deletions, **leave any empty directories in place** — including
`tasks/out-of-scope-issues/` itself and any now-empty priority subdir
(`critical/`, `high/`, `medium/`, `low/`, `proposal/`, `other/`). The
project convention expects these to exist.

### Step 8: Final Report

Summarize:
1. Total candidates scanned (tasks + issues).
2. Deleted (count + paths).
3. Kept incomplete (count + a one-line reason each).
4. User-skipped ambiguous (count + paths) — these need manual review later.
5. Reminder to commit the removals (do **NOT** auto-commit). Suggested message: `Clean up completed tasks: <task-a>, <task-b>, …`.

## Safety Rules

- **Never delete files outside `<project-root>/tasks/`.** Resolve every candidate path against the project root and verify it starts with `<project-root>/tasks/` before any `rm`.
- **Never delete top-level files in `tasks/`** (e.g., `tasks/lessons.md`). Only subdirectories and the contents of `tasks/out-of-scope-issues/` (and sections inside `tasks/out-of-scope-issues.md`) are in scope.
- **Never use `rm -rf` on a path containing `..` or unexpanded globs.** Pass concrete absolute paths only.
- If `git status --porcelain <candidate>` shows uncommitted changes inside a candidate, refuse to delete it, surface the change to the user, and downgrade to **incomplete**.
- Treat `--dry-run` as a hard read-only mode — no `rm`, no `Edit` writes anywhere.
- Treat any aborted final confirmation as "do nothing" — no partial deletions.
