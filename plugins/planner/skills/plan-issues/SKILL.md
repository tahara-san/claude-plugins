---
name: plan-issues
description: Creates task plan documents for fixing issues logged in `tasks/out-of-scope-issues/<priority>/` (priority-bucketed per-issue files), `tasks/out-of-scope-issues/` (legacy flat layout), or `tasks/out-of-scope-issues.md` (single aggregated file) by routing each (or grouped) issue through the `/plan-doc` flow. Supports filtering by priority via positional args (e.g., `/plan-issues critical,high`). Use this whenever the user wants to triage out-of-scope issues into actionable task plans — triggered by "/plan-issues", "plan the out-of-scope issues", "create tasks for logged issues", "address out-of-scope issues", or any request to convert logged out-of-scope issues into task plans. Does not implement fixes — use `/plan-code` afterwards for that.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git rev-parse *), Bash(ls *), Bash(find *), Bash(rm *), AskUserQuestion, Skill(plan-doc), EnterPlanMode, ExitPlanMode
---

# plan-issues

Converts entries from out-of-scope issue logs into task plan documents via the `/plan-doc` flow. Supports three layouts:

- **Priority-bucketed directory layout** (current): `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` where `<priority>` is one of `critical`, `high`, `medium`, `low`, `proposal`, `other`. Files MAY also live one level deeper under `<priority>/manual/<YYYYMMDD>_<short-kebab>.md` — these are the **manual-tier**: issues that require human investigation/intervention, surfaced in the report but **not** auto-planned and **not** removed by this skill.
- **Legacy flat directory layout**: `tasks/out-of-scope-issues/<short-kebab>.md` (one issue per file, no priority subdir, no date prefix) — still recognised for unmigrated projects
- **Single-file layout**: `tasks/out-of-scope-issues.md` (multiple issues aggregated, typically separated by `##`/`###` headings or `---` rules)

Document-creation only — no code is written.

## Usage

```
/plan-issues [priority...]
```

- Optional positional arg: one or more of `critical`, `high`, `medium`, `low`, `proposal`, `other` (case-insensitive). Comma- or space-separated. Default = all priorities.
- Examples:
  - `/plan-issues` — process every issue across every priority subdir
  - `/plan-issues critical,high` — only the two highest-severity buckets
  - `/plan-issues proposal` — only improvement suggestions

The skill scans all enabled layouts, filters by the requested priorities, and produces one or more `/plan-doc` task directories under `tasks/`.

## Preflight (MANDATORY before Step 1)

This skill invokes `/plan-doc` (Step 7: one invocation per issue group).
Both skills ship together in the `planner` plugin, so `/plan-doc` should
always be available — but verify it appears in your available-skills list
before proceeding.

If `/plan-doc` is NOT available, STOP and tell the user the planner plugin
is misconfigured: `/plan-doc` should be installed alongside this skill.

You MUST NOT substitute `/plan-doc` with another skill or agent (e.g.,
ad-hoc Write calls, a generic Agent that "writes a plan"). The documented
flow assumes `/plan-doc`'s exact output structure (`spec.md` + `todo.md` or
`progress.md` + `todo-phase-N.md`); substitution silently breaks the
downstream `/plan-code` step and is a procedural violation, not a
workaround.

## Step 0: Enter Plan Mode (MANDATORY before Step 1)

Call `EnterPlanMode` immediately so the discovery + grouping + decision-gate
phase (Steps 1–6) runs inside plan mode. Plan mode's session reminder
explicitly supersedes any other instruction — including a session-level
"work without stopping for clarifying questions" reminder injected by Auto
Mode — which keeps Step 6's BLOCKING GATE intact across every group.

If the session is already in plan mode when this skill starts, do NOT call
`EnterPlanMode` again — but DO call `ExitPlanMode` at Step 6.4 so the user
gets a structured approval point covering every group, every captured
decision, every planned `/plan-doc` invocation, AND every source file that
will be removed in Step 8 before any of those actions run.

## Procedure

### Step 1: Locate the Issues

1. Find the project root:
   ```bash
   git rev-parse --show-toplevel 2>/dev/null || pwd
   ```
2. **Parse the priority filter** from positional args (if any). Tokens may be comma- or space-separated, case-insensitive. Validate each token is one of `critical`, `high`, `medium`, `low`, `proposal`, `other`; warn on unrecognised tokens and ignore them. If no tokens were provided, the filter accepts all priorities.
3. **Discover candidate files** with a recursive scan:
   ```bash
   find <project-root>/tasks/out-of-scope-issues -type f -name '*.md'
   ```
   This captures both priority-bucketed files (`out-of-scope-issues/<priority>/*.md`) and legacy flat files (`out-of-scope-issues/*.md`). Also check whether `<project-root>/tasks/out-of-scope-issues.md` (single-file layout) exists — read it if so.
4. **Resolve each issue's priority** (this drives the filter):
   - File lives under a **recognised** priority subdir (one of the six values) → priority = subdir name. **The subdir is authoritative** (overrides any in-file `Severity:` field for the purpose of filtering and bucket placement).
   - File lives under `<recognised-priority>/manual/...` → priority resolves to the parent recognised priority (so the priority filter still applies), but **mark the issue as `manual-tier`** and **skip Steps 3–8 for it entirely** (no dedup, no grouping, no decision ask, no `/plan-doc` invocation, no source removal). Surface it in the Step 9 final report under "Manual-tier issues (skipped, require human handling)". The `manual/` segment is the only recognised nested subdir — anything else nested under a priority falls through to the unrecognised-subdir rule below.
   - File lives under an **unrecognised** subdir (e.g. `archive/`, `wip/`, anything not in the six-value set, or anything nested under a priority other than `manual/`) → **skip the file entirely** (do not plan, do not delete) and emit `[warn] unrecognised subdir: <path>` so the user can move/rename it manually. Do NOT silently coerce to `other`.
   - File is in the **flat root** (`tasks/out-of-scope-issues/<name>.md`) or a **single-file-layout section** → priority = lowercased value of the in-file `Severity:` field. If missing, empty, or not one of the six values → priority = `other`, AND emit `[warn] severity defaulted to 'other': <path-or-section>`.
   - File is under a recognised priority subdir AND its in-file `Severity:` field disagrees with the subdir → trust the subdir for filtering/bucketing, but emit `[warn] severity/subdir mismatch: <path>` so the inconsistency is visible.
5. **Deduplicate partial-migration overlap**: if the same logical issue appears at both `tasks/out-of-scope-issues/<short-kebab>.md` (legacy flat) and `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` (new layout), prefer the new-layout file and **skip** the flat one (do NOT delete it). Flag the legacy file in the final report so the user can remove it manually. Match by stripping the optional `YYYYMMDD_` prefix from the new-layout filename and comparing the remaining kebab name.
6. **Apply the priority filter**: narrow the issue list to those whose resolved priority is in the requested set. The filtered list is the ONLY list passed forward to Steps 3–8. Issues not in the filtered list MUST NOT be planned, deleted, or reported as removed. Keep a separate count of pre-filter total + skipped/warned files for the final report.
7. If the filtered list is empty (or both layouts are absent entirely), tell the user there are no matching issues to plan and stop.

### Step 2: Read and Normalize Each Issue

Treat each issue as a record with these fields, regardless of source layout:
- **Source**: file path (and section heading, for single-file layout)
- **Resolved priority**: from Step 1 (subdir for new layout; in-file `Severity:` otherwise)
- **Issue** description
- **Location** (file path + line numbers)
- **Severity** (Low / Medium / High / Critical / Proposal / Other)
- **Context**
- **Suggested Fix**

**Directory layout** — each `*.md` file is one issue. Read the whole file.

**Single-file layout** — split `tasks/out-of-scope-issues.md` into individual issues:
- Primary delimiter: top-level issue headings (typically `## ` or `### `)
- Fallback delimiter: horizontal rules (`---`) between blocks
- Use the heading text (or first line) as the issue's short title and `Source` reference (e.g., `tasks/out-of-scope-issues.md#missing-error-handling-in-user-route`)
- If the file's structure is ambiguous and you cannot reliably split it, ask the user once how issues are delimited before proceeding

### Step 3: Deduplicate Against Existing Tasks

1. List existing subdirectories of `<project-root>/tasks/` (excluding `out-of-scope-issues/` and any other non-task dirs).
2. For each candidate issue, check whether an existing task already addresses it by:
   - Reading the `spec.md` (or `todo.md`) of each existing task subdir
   - Matching against issue title, location, and suggested fix
3. Skip any issue already covered by an existing task. Note skipped issues in the final report.

### Step 4: Group Issues

- **Group** small/trivial fixes that share a theme (e.g., "minor lint cleanup", "missing error handling across routes") into a single task.
- **Keep separate** any issue that is medium+ severity, requires architectural decisions, touches multiple subsystems, or has a non-trivial scope.
- Each group becomes one `/plan-doc` task.

Suggested grouping heuristics:
- Group by resolved priority = `low` **and** small surface area (1–2 files, single concern)
- `proposal` items may also be grouped when they share a theme (e.g., "developer-experience improvements")
- Do not group across unrelated files or unrelated concerns even if both are `low`/`proposal`

### Step 5: Generate Task Names

For each group, derive a short kebab-case task name (max 4–5 words). Examples:
- Single issue: use the issue's short description (e.g., `missing-error-handling-user-route`)
- Grouped: use a thematic name (e.g., `cleanup-minor-lint-issues`)

When deriving a task name from a new-layout filename, strip the `YYYYMMDD_` date prefix first — the prefix is metadata, not part of the task identity. For example, `20260502_missing-error-handling-user-route.md` → task name `missing-error-handling-user-route`.

### Step 6: Surface Decisions and Manual-Handling Needs Per Group (MANDATORY — BLOCKING GATE)

> Each `/plan-doc` invocation in Step 7 will lock in engineering choices for one group. To avoid surprising the user with N rounds of mid-skill questions (one per group), resolve all open decisions and manual-handling needs UPFRONT in a single batched ask, then pass the answers into each `/plan-doc` call. Proceed to Step 7 only after this gate is closed.

#### 6.1 — Per-group discovery

For each group from Step 4, identify open items using the same triggers as `/plan-doc` Step 3:

- **Decisions**: library / framework, architectural pattern, data model / schema, public API shape, error-handling policy, performance trade-offs, UX defaults, scope boundaries, migration / backward-compatibility shape — anything where multiple legitimate options exist and a senior engineer would NOT pick blindly.
- **Manual-handling needs**: a bug whose root cause isn't derivable from the logs/code in front of you (needs a repro from the user); tests requiring real credentials, hardware, or external services; UI/visual checks; performance/load validation against real data; security or compliance judgement; anything depending on systems Claude can't reach.

If `CLAUDE.md` or existing code already enforces an answer, take it — don't ask. Issues with a single obvious fix (e.g., a clear typo, a missing null guard with one correct shape) need no decision ask.

#### 6.2 — Batch-ask across all groups

- If no group has any open items, state "No open decisions across N groups; proceeding to /plan-doc invocations." and move to Step 7.
- Otherwise, gather the items across ALL groups into one or more `AskUserQuestion` rounds (cap at ~4 questions per round; multiple rounds are fine if needed). For each question, prefix with the group's task name so the user knows which plan it affects (e.g., `[add-user-auth] Which auth library?`). For each decision, present 2–4 concrete options with a one-line trade-off per option.
- For manual-handling needs: either ask the user to supply the missing information now (and capture their reply for the plan), or confirm the plan should call out the manual step explicitly so it lands in the TODO with the user as the actor.

#### 6.3 — Capture answers and pass them through

Record every answer keyed by group + question. In Step 7, embed the captured decisions in each `/plan-doc` task description under a clearly labeled `## Pre-resolved Decisions` block so `/plan-doc` Step 3 sees the answers as already settled and does not re-ask.

If the user said "just decide" / "use your judgment" for a particular group, note it for that group and let `/plan-doc` Step 3 record the choices under `## Decisions Made Without User Input` per its bypass rule.

#### 6.4 — Exit Plan Mode (MANDATORY before Step 7)

Call `ExitPlanMode` before any `/plan-doc` invocation or source removal.
The plan you submit for approval covers the entire downstream batch:

- **Groups created** — task name + the issue files mapped into each
- **Decisions captured per group** — each "Q → A" with provenance (user
  answer / "just decide" delegation), grouped by task name
- **Manual-handling notes per group** — what the user is expected to do
- **Step 7 actions** — list each `/plan-doc` invocation that will run
- **Step 8 actions** — list every source file that will be removed
  (priority-bucketed paths, legacy flat paths, single-file sections),
  AND every source that will NOT be removed (manual-tier files, files
  with warnings, partial-migration overlaps)

The user's approval here authorizes the **entire** Step 7 + Step 8
sequence. Each `/plan-doc` invocation in Step 7 will see both
`## Pre-resolved Decisions` and `## Manual-Handling Notes` blocks in
its task description and will skip its own plan-mode cycle per
`/plan-doc` Step 0's bypass rule — so the user is not re-prompted for
each group.

If the user does NOT approve (sends a redirect, edit request, or any
non-approval reply), treat it as a course correction. Do NOT invoke
`/plan-doc` and do NOT remove any source files.

---

### Step 7: Invoke `/plan-doc` Per Group

For each group, invoke the `plan-doc` skill with:
- The chosen task name
- A composed task description that includes:
  - Summary of the issue(s)
  - Locations (file paths + line numbers)
  - Severities
  - Suggested fixes
  - Source references — file path for directory-layout issues, or `tasks/out-of-scope-issues.md#<heading-anchor>` for single-file-layout issues
  - **`## Pre-resolved Decisions`** block — the user-confirmed answers captured in Step 6 for this group (omit the block entirely if Step 6 found no open items for this group). `/plan-doc` will trust this block and skip re-asking for the items it covers.
  - **`## Manual-Handling Notes`** block — any manual steps the user is expected to perform for this group (omit if none). `/plan-doc` will carry these through into `spec.md` and into the TODO with the user as the actor.

**Hard rules to pass into every `/plan-doc` invocation:**
- Do **not** create migration code
- Do **not** create backward-compatibility shims
- Prefer the most direct, elegant fix

### Step 8: Remove Source Issues (MANDATORY)

> Only run this step for issues whose `/plan-doc` invocation completed successfully. Skipped (already-covered) issues stay where they are. If any `/plan-doc` invocation failed, leave the corresponding source untouched and report the failure.
>
> **Filtered-list guard**: Iterate ONLY over the filtered + successfully-planned issue list produced by Step 1's filter. Never iterate over the full unfiltered discovery glob. A filtered run like `/plan-issues low` MUST NOT delete any non-`low` file. Files that were skipped due to the filter, the unrecognised-subdir warning, the **manual-tier marker**, the partial-migration dedup, or a `/plan-doc` failure all stay where they are. **Manual-tier files (under `<priority>/manual/`) MUST NEVER be removed by this skill** — they are parked for human handling.

For each successfully planned issue:

**Directory layout** — delete the per-issue file using its full path (priority-bucketed or legacy flat, whichever the source was):
```bash
rm <project-root>/tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md
# or, for a legacy flat source:
rm <project-root>/tasks/out-of-scope-issues/<short-kebab>.md
```
After deleting, if the priority subdir (or `tasks/out-of-scope-issues/` itself) is now empty, leave the empty directory in place (do not remove).

**Single-file layout** — remove the corresponding section from `tasks/out-of-scope-issues.md` using `Edit`:
- Remove the heading line through the end of the section (up to but not including the next sibling-or-higher heading, or end-of-file)
- If a `---` rule immediately followed the section, remove it too
- After all planned sections are removed, if the file contains only whitespace or only a top-level title with no remaining issues, delete the file:
  ```bash
  rm <project-root>/tasks/out-of-scope-issues.md
  ```

Track exactly which sources you removed; you will list them in Step 9.

### Step 9: Final Report

After all `/plan-doc` invocations and source removals complete, report to the user:
1. Issues found (count) and where they came from, with a per-priority breakdown (e.g., `critical: 1, high: 0, medium: 3, low: 5, proposal: 2, other: 0`). Manual-tier files DO count toward their parent priority in this breakdown. On a separate line, show how the priority filter narrowed the set (e.g., `Filter: low → 1 of 11 issues selected`); omit the filter line if no filter was applied.
2. Issues skipped because they were already covered (list with the existing task that covers them — these sources are NOT removed)
3. Issues skipped due to warnings (unrecognised subdir, partial-migration overlap, severity defaulted to `other`, severity/subdir mismatch) — list each with the warning reason. These sources are NOT removed.
4. Cross-priority duplicate kebabs in the new layout: same `<short-kebab>` appearing under more than one priority subdir. Usually means a reclassification was done by copy rather than `git mv`. Report only — never auto-deleted; the user resolves manually.
5. **Manual-tier issues (skipped, require human handling)**: list each `<priority>/manual/<file>.md` that fell within the priority filter, with its priority. These were intentionally not planned and not removed. Omit this section entirely if the filter excluded all manual-tier files or none exist.
6. Groups created, with the task name and the issue files mapped into each
7. **Decisions captured in Step 6**: per group, list each "Q → A" so the user can see exactly which calls were settled with their input vs. handed back to Claude. Omit if Step 6 found nothing to ask.
8. **Manual-handling notes captured in Step 6**: per group, list any steps the user is now expected to perform (repro, manual QA, credentials-gated checks, etc.). Omit if none.
9. Paths to all newly created task directories
10. Source files/sections that were removed (and any that were intentionally left in place because their `/plan-doc` invocation failed)

### Step 10: Emit Kickoff Prompt (MANDATORY)

After the report, emit a copy-pasteable kickoff prompt that wires every newly created task into a single `/plan-code` invocation. Render it inside a fenced code block so the user can copy it verbatim.

Substitute the actual task subdirectory names (comma-separated, in the order created). If no new tasks were created, skip this step.

````
```
/plan-code @tasks/<taskSubDir1>, @tasks/<taskSubDir2>, @tasks/<taskSubDirN>

- Automatically start the next steps, phases, tasks unless you need a user decision or manual handling step that you captured in Step 6. If so, wait for the user to complete those before proceeding.
- Remove the task files after completing the task.
- do not create any migration / backward compatibility codes.
```
````

Do NOT start implementing. This skill creates plan documents only — the user runs the kickoff prompt when they're ready.
