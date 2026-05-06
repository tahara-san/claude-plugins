---
name: plan-doc
description: Creates structured spec and implementation plan documents for a task or feature before any code is written. Use this whenever the user wants to plan a feature, fix, refactor, or new system — triggered by "/plan-doc", "create a spec", "write a plan for", "plan this feature", "document this task", "spec this out", or any request to think through and document an implementation approach. Even when a user describes a task and seems ready to jump into coding, use this skill to create the plan documents first. Always use this for non-trivial tasks before implementation begins.
allowed-tools: Read, Write, Glob, Bash(git rev-parse *), Bash(ls *), AskUserQuestion, Skill(codex-chunk)
---

# plan-doc

Creates a spec document and TODO checklist for a task. Document-creation only — no code is written.

## Usage

```
/plan-doc [task-name]
```

- `task-name` — Optional. Kebab-case identifier (e.g., `add-user-auth`). If omitted, derived from the description.
- The task description and any appendix (code, logs, error messages) follow the command in the user's message.

## Preflight (MANDATORY before Step 1)

This skill orchestrates `/codex-chunk` (Step 7: Codex Plan Review). Before
doing anything else, verify it appears in the available-skills list shown in
your system context.

If `/codex-chunk` is NOT available, STOP and tell the user:

> Required skill missing: `/codex-chunk`. Install before retrying:
> `/plugin install codex-chunk@tahara-claude-plugins`

You MUST NOT substitute `/codex-chunk` with another skill or agent (e.g.,
`code-review`, `simplify`, `code-simplifier`, a generic Agent call). The
chunked review behavior is required by Step 7 — substitution silently breaks
the documented workflow and is a procedural violation, not a workaround.
Halt and surface the missing dependency rather than improvising.

The plan documents this skill writes also reference `/simplify` (built into
Claude Code itself) and `/codex-chunk` for the implementer who will later
run `/plan-code`. Those references are intentional — do not rewrite them to
mention different skills.

## Procedure

### Step 1: Extract Task Info

1. **Task name**: Use the argument if provided. Otherwise, derive a short kebab-case name from the description (e.g., "add user authentication" → `add-user-auth`). Max 4-5 words, lowercase, hyphens only.
2. **Task description**: The user's message content. If nothing was provided beyond the command, ask once for the task description before proceeding.
3. **Output directory**: `<project-root>/tasks/<task-name>/`

Find the project root:
```bash
git rev-parse --show-toplevel 2>/dev/null || pwd
```

### Step 2: Gather Context

1. Read `CLAUDE.md` from the project root if it exists — extract architecture, tech stack, and conventions.
2. Note any code snippets, logs, or error messages the user included as appendix context.
3. Skim the files most likely to be touched (Glob + Read) so the decisions you surface in Step 3 are grounded in the actual code, not guesses.

---

### Step 3: Surface Decisions and Manual-Handling Needs (MANDATORY — BLOCKING GATE)

> The plan you write here will lock in real engineering choices. Do NOT silently pick when multiple legitimate options exist, and do NOT plan around investigation/testing steps that the user has to do for you. Identify both, ask the user via `AskUserQuestion`, and proceed to Step 4 only after the answers are in. This is a blocking gate, not a "nice-to-have".

#### 3.1 — Identify open decisions

Walk through the task and your Step 2 reading. For each item below, list every place where a senior engineer would NOT pick the answer blindly — those are the decisions you must surface to the user:

- **Library / framework choice** when more than one option is plausible
- **Architectural pattern** — new service vs. inline in caller; shared module vs. local helper; sync vs. async; queue vs. direct call
- **Data model / schema** — new column vs. new table; nullable vs. default; denormalize vs. join; index choices that change query shape
- **Public API shape** — return value vs. throw; optional vs. required field; naming; versioning
- **Error-handling policy** — swallow + log, surface to caller, retry, fail fast
- **Performance / resource trade-offs** — cache TTL, batch size, pagination limits, concurrency
- **UX-visible choices** — default state, label copy, behavior on empty/error
- **Scope boundaries** — "does this also fix the related Y?" / "should X be touched in this task?"
- **Migration / backward-compatibility shape** — only when the user has not already said "no migration code"

If `CLAUDE.md` or existing code already enforces an answer, take that answer — don't ask. Only ask about choices that are still genuinely open.

#### 3.2 — Identify manual-handling needs

List anything that requires the user to act, observe, or supply context that you cannot get yourself:

- A bug whose root cause is NOT derivable from the code/logs in front of you — you need a repro, a stack trace, or production-state details
- Tests or verification that need real credentials, accounts, hardware, devices, or external services
- UI / visual changes that need a human to look at the rendered result
- Performance or load behavior that can only be checked against real data or production scale
- Security or compliance judgement calls
- Anything depending on systems you cannot reach (third-party APIs, prod DB, internal dashboards)

If a manual step is required just to verify the fix, call it out so the plan can include the user's role explicitly in the TODO.

#### 3.3 — Ask in one batched round

- If 3.1 and 3.2 both came up empty, state "No open decisions or manual-handling needs; proceeding to draft." and continue to Step 4.
- Otherwise, bundle the open items into a single `AskUserQuestion` call. Cap at ~4 questions per round; if more remain, ask the most consequential first and follow up after.
  - **For each decision**: present 2–4 concrete options with a one-line trade-off per option. Avoid open-ended "what do you think?" prompts when a multiple-choice question would do.
  - **For manual-handling needs**: either ask the user to supply the missing information now, or confirm the plan should call out the manual step explicitly so it lands in the TODO with the user as the actor.
- Record every answer — they become inputs to Step 5 (`spec.md`) and Step 6 (TODOs). Do not silently override them later.

> If the user explicitly says "just decide" or "use your judgment", proceed — but record each choice you made under the `## Decisions` section in `spec.md` (Step 5), tagged "(no user input — Claude's call)", so the calls stay visible in review. That is the only acceptable bypass; do not skip the ask just because you think the answer is obvious.
>
> If the task description you received already includes a `## Pre-resolved Decisions` block (e.g., from `/plan-issues` Step 6), trust those answers and only ask about items NOT covered there.

---

### Step 4: Decide Document Structure

Before writing, estimate the plan scope:

| Signal | Structure |
|--------|-----------|
| Single focused task, 1–3 phases, <5,000 chars estimated | **Small**: `spec.md` + `todo.md` |
| Multiple phases (4+), complex system, spans many files, or estimated >5,000 chars | **Large**: `spec.md` + `progress.md` + `todo-phase-N.md` per phase |

When in doubt, prefer the large structure — it scales better.

---

### Step 5: Draft and Write `spec.md`

Save to `tasks/<task-name>/spec.md`.

```markdown
# <Task Title>

## Goal
<What this achieves and why it's needed. 2–4 sentences.>

## Scope

### In Scope
- <item>

### Out of Scope
- <item>

## Decisions
<Include this section ONLY if Step 3 captured user-confirmed answers, OR if the user told you to use your judgment (record each call here tagged "no user input — Claude's call"). Omit entirely if Step 3 found no open decisions.>

- **Q:** <decision question> — **A:** <chosen option> _(user)_  · trade-off: <one-line summary of what was traded off>
- **Q:** <decision> — **A:** <choice> _(no user input — Claude's call)_

## Manual-Handling Notes
<Include this section ONLY if Step 3.2 surfaced steps the user must perform (repro, manual QA, credentials-gated tests, etc.). Each entry should name the user as the actor and describe what they need to do or supply.>

- <e.g., "User to capture browser console output during step X and paste into the TODO before that phase starts.">

## Technical Approach
<How the implementation will work. Key design decisions and rationale. Be specific about patterns, libraries, and architectural choices. The choices recorded under "Decisions" above MUST be reflected here verbatim — do not contradict them.>

## Expected File Changes

| File | Change | Description |
|------|--------|-------------|
| `path/to/file` | Create / Modify / Delete | What changes and why |

## Implementation Rules
<Include this section ONLY for large plans. For small plans, these go in todo.md instead.>

- No migration or backward-compatibility code unless explicitly requested by the user
- Prefer concise, elegant solutions over verbose or defensive ones

## Implementation Workflow
<Include this section ONLY for large plans. For small plans, these go in todo.md instead.>

> **⚠ MANDATORY — EVERY STEP BELOW IS A BLOCKING REQUIREMENT.**
> Skipping any step (especially `/simplify`) is a violation. `/codex-chunk` MUST NOT run until `/simplify` has run on the same files first.

### Per-Phase Implementation Review
1. Implement the phase
2. **MANDATORY:** Run `/simplify` on the phase's changed files — implement any changes it produces
3. **MANDATORY:** Run `/codex-chunk` on all changed files in the phase (PREREQUISITE: step 2 must be complete)
4. If Codex finds CRITICAL or worth-addressing WARNINGs: fix → re-run `/simplify` → re-run `/codex-chunk`
5. Iterate until Codex returns a clean review

### Holistic Review (after all phases complete)
SKIP if single-phase plan. Otherwise:
6. **MANDATORY:** Run `/simplify` on ALL changed files across all phases
7. **MANDATORY:** Run `/codex-chunk` on ALL changed files together (PREREQUISITE: step 6 must be complete)
8. If Codex finds CRITICAL or worth-addressing WARNINGs: fix → re-run `/simplify` → re-run `/codex-chunk`
9. Iterate until Codex returns a clean holistic review
10. Document all ignored warnings in `tasks/<task-name>/ignored-warnings.md`

### Build Verification (final step)
11. **MANDATORY:** Run `npm run build`
12. If the build fails:
    a. Fix the build errors
    b. **MANDATORY:** Run `/simplify` on changed files
    c. **MANDATORY:** Run `/codex-chunk` on changed files; iterate until clean
    d. Rerun `npm run build`
    e. Repeat steps 12a–12d until the build passes
```

> For **small plans**: omit the Implementation Rules and Workflow sections from `spec.md` — they go in `todo.md`.
> For **large plans**: include both sections in `spec.md` since they won't be repeated in the phase todos.

---

### Step 6: Draft TODO Document(s)

#### Small Plan — `todo.md`

Save to `tasks/<task-name>/todo.md`.

```markdown
# <Task Title> — TODO

## Phase 1: <Phase Name>
- [ ] <specific, actionable step>
- [ ] <step>
- [ ] <step>

## Phase 2: <Phase Name>
- [ ] <step>
- [ ] <step>

## Verification
- [ ] All tasks above completed
- [ ] Per-phase: `/simplify` → `/codex-chunk` passes (no CRITICAL or worth-addressing WARNINGs)
- [ ] Holistic `/simplify` → `/codex-chunk` passes (skip if single-phase)
- [ ] `npm run build` passes

---

## Implementation Rules

- **Orchestrator**: Claude Opus, xhigh effort
- **Coders (subagents)**: Claude Sonnet, medium effort
- Orchestrator spawns subagents for all non-trivial code changes; direct edits only for trivial/single-line changes
- No migration or backward-compatibility code unless explicitly requested by the user
- Prefer concise, elegant solutions

## Implementation Workflow

> **⚠ MANDATORY — EVERY STEP BELOW IS A BLOCKING REQUIREMENT.**
> Skipping any step (especially `/simplify`) is a violation. `/codex-chunk` MUST NOT run until `/simplify` has run on the same files first.

### Per-Phase Implementation Review
1. Implement the phase
2. **MANDATORY:** Run `/simplify` on the phase's changed files — implement any changes it produces
3. **MANDATORY:** Run `/codex-chunk` on all changed files in the phase (PREREQUISITE: step 2 must be complete)
4. If Codex finds CRITICAL or worth-addressing WARNINGs: fix → re-run `/simplify` → re-run `/codex-chunk`
5. Iterate until Codex returns a clean review

### Holistic Review (after all phases complete)
SKIP if single-phase plan. Otherwise:
6. **MANDATORY:** Run `/simplify` on ALL changed files across all phases
7. **MANDATORY:** Run `/codex-chunk` on ALL changed files together (PREREQUISITE: step 6 must be complete)
8. If Codex finds CRITICAL or worth-addressing WARNINGs: fix → re-run `/simplify` → re-run `/codex-chunk`
9. Iterate until Codex returns a clean holistic review
10. Document all ignored warnings in `tasks/<task-name>/ignored-warnings.md`

### Build Verification (final step)
11. **MANDATORY:** Run `npm run build`
12. If the build fails:
    a. Fix the build errors
    b. **MANDATORY:** Run `/simplify` on changed files
    c. **MANDATORY:** Run `/codex-chunk` on changed files; iterate until clean
    d. Rerun `npm run build`
    e. Repeat steps 12a–12d until the build passes
```

#### Large Plan — `progress.md`

Save to `tasks/<task-name>/progress.md`.

```markdown
# <Task Title> — Progress

See `spec.md` for full technical details, implementation rules, and workflow.

## Phases

- [ ] **Phase 1**: <Phase Name> → [`todo-phase-1.md`](todo-phase-1.md)
- [ ] **Phase 2**: <Phase Name> → [`todo-phase-2.md`](todo-phase-2.md)
- [ ] **Phase N**: <Phase Name> → [`todo-phase-N.md`](todo-phase-N.md)

## Completion Criteria

- [ ] All phase TODO files fully checked off
- [ ] Per-phase: `/simplify` → `/codex-chunk` passes (no CRITICAL or worth-addressing WARNINGs)
- [ ] Holistic `/simplify` → `/codex-chunk` passes across all phases
- [ ] `npm run build` passes
- [ ] Mark this task complete
```

#### Large Plan — `todo-phase-N.md` (one per phase)

Save to `tasks/<task-name>/todo-phase-N.md`.

```markdown
# Phase N: <Phase Name>

> Implementation rules and workflow are in [`spec.md`](spec.md).

## Tasks

- [ ] <specific, actionable step>
- [ ] <step>
- [ ] <step>

## Done When

- [ ] All tasks above checked off
- [ ] `/simplify` → `/codex-chunk` passes (no CRITICAL or worth-addressing WARNINGs)
- [ ] Mark phase N complete in `progress.md`
```

---

### Step 7: Codex Plan Review (Finalization)

Each plan document must be reviewed by Codex before it is considered final. This step ensures the written documents are already approved when output to the user.

1. Submit `spec.md` to `/codex-chunk` for review
2. If Codex returns CRITICAL findings or worth-addressing WARNINGs, revise the document and resubmit
3. Iterate until Codex returns a clean review
4. For each TODO document (`todo.md`, or `progress.md` + each `todo-phase-N.md`):
   a. Submit the document to `/codex-chunk` for review
   b. If Codex returns CRITICAL findings or worth-addressing WARNINGs, revise and resubmit
   c. Iterate until Codex returns a clean review

Only proceed to Step 8 after all documents pass Codex review.

---

### Step 8: Checklist Quality Rules

Every TODO item must be:
- **Actionable**: starts with a verb (Create, Add, Update, Remove, Wire, Configure, Test...)
- **Specific**: references actual file names, function names, or components where known
- **Atomic**: one thing at a time — if it has two parts, split it

Avoid vague items like "handle errors" or "update logic". Prefer "Add error boundary to `UserForm` component in `src/components/UserForm.tsx`".

---

### Step 9: Confirm Output

After writing all files, tell the user:
1. Which files were created (with relative paths)
2. The chosen structure (small/large) and why
3. A 1–2 sentence summary of the technical approach
4. The decisions captured in Step 3 (one line each: "Q → A") so the user can see exactly which calls were settled with their input vs. punted to Claude
5. Any manual-handling notes the plan now expects from the user
6. Confirmation that all documents passed Codex review

Do NOT start implementing. This skill creates documents only.
