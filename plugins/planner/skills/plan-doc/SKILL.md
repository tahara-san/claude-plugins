---
name: plan-doc
description: Creates structured spec and implementation plan documents for a task or feature before any code is written. Use this whenever the user wants to plan a feature, fix, refactor, or new system — triggered by "/plan-doc", "create a spec", "write a plan for", "plan this feature", "document this task", "spec this out", or any request to think through and document an implementation approach. Even when a user describes a task and seems ready to jump into coding, use this skill to create the plan documents first. Always use this for non-trivial tasks before implementation begins.
allowed-tools: Read, Write, Edit, Glob, Bash(git rev-parse *), Bash(ls *), AskUserQuestion, Skill(codex-chunk), Agent, SendMessage, EnterPlanMode, ExitPlanMode
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

This skill orchestrates `/codex-chunk` (Step 7: Parallel Plan Review).
Before doing anything else, verify it appears in the available-skills list
shown in your system context.

If `/codex-chunk` is NOT available, STOP and tell the user:

> Required skill missing: `/codex-chunk`. Install before retrying:
> `/plugin install codex-chunk@tahara-claude-plugins`

You MUST NOT substitute `/codex-chunk` with another skill or agent (e.g.,
`code-review`, `simplify`, `code-simplifier`, a generic Agent call). The
chunked review behavior is required by Step 7 — substitution silently breaks
the documented workflow and is a procedural violation, not a workaround.
Halt and surface the missing dependency rather than improvising.

Step 7's second lane — the **Claude Code Fable (high reasoning) Review**
— needs NO install: it uses Claude Code's built-in Agent tool (a
`general-purpose` subagent launched with `run_in_background: true` and
`model: "fable"`; the prompt must request high-reasoning thoroughness since
the Agent tool has no effort parameter — if the harness exposes an effort
selector, set it to `high`; if the harness no longer offers `"fable"`, fall
back to `model: "opus"` — the latest Opus model, prompted for
xhigh-reasoning thoroughness — and tell the user — flag the substitution
prominently, never substitute silently). The lanes are not interchangeable:
the Fable lane never replaces `/codex-chunk`, and `/codex-chunk` never
replaces the Fable lane.

Also confirm **`review-policy`** — the planner plugin's finding-disposition
contract, bundled alongside this skill — appears in the available-skills
list. It is never user-invoked; Step 7 loads it to decide which findings
actually block. If it is missing, the planner plugin is misconfigured:
reinstall with `/plugin install planner@tahara-claude-plugins` rather than
improvising a pass/fail rule.

The plan documents this skill writes also reference `/simplify` (built into
Claude Code itself), `/codex-chunk`, the Claude Code Fable (high
reasoning) Review, and `review-policy` for the implementer who will later run
`/plan-code`. Those references are intentional — do not rewrite them to
mention different skills.

## Step 0: Enter Plan Mode (MANDATORY before Step 1)

Call `EnterPlanMode` immediately so the investigation + decision-gate phase
(Steps 1–3) runs inside plan mode. Plan mode's session reminder explicitly
supersedes any other instruction — including a session-level "work without
stopping for clarifying questions" reminder injected by Auto Mode — which
keeps Step 3's BLOCKING GATE intact and prevents silent decision absorption.

**Skip plan-mode entry only when BOTH conditions hold:**

1. The task description you received already contains a
   `## Pre-resolved Decisions` block (Step 3.1 settled upstream — typically
   by `/plan-issues` Step 6), AND
2. It also contains a `## Manual-Handling Notes` block, OR an explicit
   statement that no manual-handling is needed (Step 3.2 settled upstream).

When both are pre-resolved, the upstream skill is managing the gate; do NOT
call `EnterPlanMode` here, and do NOT call `ExitPlanMode` at the Step 3.4
boundary. Proceed directly to Step 1.

If the session is **already** in plan mode when this skill starts (the user
invoked `/plan-doc` from within an existing plan-mode turn), do NOT call
`EnterPlanMode` again — but DO call `ExitPlanMode` at Step 3.4 so the user
gets the structured approval before files are written.

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

### Step 3.4: Exit Plan Mode (MANDATORY before any writes)

> **Skip this step ONLY if Step 0 also skipped `EnterPlanMode`** because the
> upstream skill is managing plan mode (both `## Pre-resolved Decisions`
> and `## Manual-Handling Notes` blocks were present in the task
> description). In every other case — including when the user entered plan
> mode themselves before invoking this skill — this step is mandatory.

Call `ExitPlanMode` before any file is written. The plan you submit for
approval is the readiness summary the user signs off on:

- **Decisions captured in Step 3.1** — each "Q → A" with provenance: user
  answer / "just decide" delegation / pre-resolved upstream
- **Manual-handling notes from Step 3.2** that will land in `spec.md`
- **Structure choice for Step 4** if you can already tell from Step 2
  reading (small vs. large); otherwise say "structure TBD in Step 4"
- **Files Step 5 / Step 6 will write** — list the relative paths

After approval, proceed to Step 4. Steps 4–10 perform writes and the
parallel plan reviews and cannot run inside plan mode.

If the user does NOT approve (sends a redirect, edit request, or any
non-approval reply), treat it as a course correction — re-enter the
relevant earlier step rather than partially writing files.

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
> Skipping any step (especially `/simplify`) is a violation. Neither review lane may run until `/simplify` has run on the same files first.
> **Review rounds are dual-lane and parallel.** Lane 1 — Claude Code Fable (high reasoning) Review: a fresh subagent launched via the Agent tool with `run_in_background: true`, a `name` (so delta rounds can message the same reviewer), and `model: "fable"` (or `model: "opus"` — the latest Opus model, prompted for xhigh-reasoning thoroughness — if `"fable"` is unavailable; tell the user, flag the substitution prominently, never substitute silently); the prompt must request high-reasoning thoroughness (the Agent tool has no effort parameter; if an effort selector exists, use `high`); agent type `code-reviewer` for code if available else `general-purpose`, `general-purpose` for docs; the prompt must name the files, the CRITICAL/WARNING/INFO taxonomy, and the `[SEVERITY] file:line — description` output format. Lane 2 — `/codex-chunk` on the same files. Launch the Fable lane FIRST (background), run `/codex-chunk` while it works, then collect BOTH results — never judge a round on the Codex result alone. Both prompts must carry the `review-policy` §8 reviewer contract and ask for a closing `Verdict: PASS | CHANGES_REQUIRED | BLOCKED` line.
> **A round passes when both lanes ran and NEITHER produced a BLOCKING finding — judged by the `review-policy` blocker predicate (grounded + concrete + contract-relevant + material), not by severity label alone.** Advisory findings get a recorded disposition in `tasks/<task-name>/reviews/round-<n>/dispositions.md` and are PARKED, never fixed inside the gate: `park-follow-up` / `out-of-scope` items become `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` files, the rest stay in the ledger. **Remedy scope is bound to the blockers** — a fix batch may touch only what closes a confirmed BLOCKING finding plus its coupled artifacts and semantically affected neighbors. Advisory-only output CLOSES the gate: no source mutation, no rerun. Budget: at most 4 judged-byte-mutating remediation rounds per gate, then convergence mode, then escalate to the user after one more bounded round (the 5th). Split verdicts (one lane PASS, one CHANGES_REQUIRED) run the `review-policy` §7a bilateral cross-lane dispute exchange — the passing lane adjudicates the blockers AND the failing lane adjudicates the passing lane's PASS position, both `[UPHOLD|OBJECT]` per finding; a finding falls only when both lanes object, and anything either lane upholds is remediated and re-rounded, never immediately escalated. A lane that never ran or emitted unparseable output is `BLOCKED_PROCESS` — fail-closed, never parked.
> **Re-rounds after fixes run at DELTA scope.** Round 1 of a gate is always full-coverage; when a round completes, record per-file clean verdicts (diff/blob hashes + round id) in the progress notes. A re-round covers: files changed since their last clean review, files semantically affected by the fix (uncertain impact boundary ⇒ full round instead), files with NO recorded clean baseline (a failed round 1 leaves none — the next round is effectively full again), and one small delta-interactions chunk; only files with a recorded clean baseline carry verdicts forward. Write the delta round's scope list into the notes before launching it — under-scoping without that trail is non-compliant. Before ANY re-round, batch coupled artifacts into the fix (indexes for query/sort changes, config, docs, callers of changed signatures — fix each or clear it with a one-line recorded rationale). Tiers (behavior classification FIRST): behavior-affecting or uncertain fixes ⇒ dual-lane delta round regardless of size; confirmed non-behavioral doc-only fixes (no code files) ⇒ single-agent `/simplify` (this IS the mandatory post-fix `/simplify` for this tier, never a skip) + a single-lane delta check by the persistent Fable reviewer (the ONLY two-lane exception); confirmed non-behavioral ≤5-line mechanical code fixes ⇒ dual-lane delta round; new files/scope ⇒ treat as round 1 for that content (full dual-lane review of it plus semantically affected neighbors); any BLOCKING finding ⇒ full round. A partial rerun outside these rules cannot pass a gate.

### Per-Phase Implementation Review
1. Implement the phase
2. **MANDATORY:** Run `/simplify` on the phase's changed files — implement any changes it produces
3. **MANDATORY:** Run a parallel review round on all changed files in the phase — Fable review in background + `/codex-chunk` (PREREQUISITE: step 2 must be complete). Round 1 is full-coverage; record the reviewed state when clean.
4. Disposition every finding per `review-policy` into `tasks/<task-name>/reviews/round-<n>/dispositions.md`. **If NO finding is BLOCKING → the gate is PASSED**: write the `park-follow-up` / `out-of-scope` items to `tasks/out-of-scope-issues/<priority>/`, change nothing else, and move on.
5. If a finding IS BLOCKING — where a split-verdict round (one lane `PASS`, one `CHANGES_REQUIRED`) FIRST runs the `review-policy` §7a bilateral dispute exchange, and only findings that survived the exchange enter remediation: fix ONLY the blockers (batching their coupled artifacts) → re-run `/simplify` scoped to the fix (tiered) → re-run a round at the scope the delta-round rules require (dual-lane delta by default; full for BLOCKING findings/new scope/uncertain impact; single-lane check only for doc-only fixes). Iterate until a round ends with every required lane `QUALIFYING` and no BLOCKING finding outstanding; at 4 mutating rounds, enter convergence mode and escalate after one more (the 5th).

### Holistic Review (after all phases complete)
SKIP if single-phase plan. Otherwise:
6. **MANDATORY:** Run `/simplify` on ALL changed files across all phases
7. **MANDATORY:** Run a parallel review round on ALL changed files together — Fable review in background + `/codex-chunk` (PREREQUISITE: step 6 must be complete). The first holistic round is full-coverage; record the reviewed state when clean.
8. Disposition every finding per `review-policy`. **If NO finding is BLOCKING → the holistic gate is PASSED**; park the follow-ups and proceed to build verification without touching source.
9. If a finding IS BLOCKING: fix ONLY the blockers (batching coupled artifacts) → re-run `/simplify` scoped to the fix (tiered) → re-run a holistic round at the scope the delta-round rules require (dual-lane delta against the last clean holistic state by default; full coverage for BLOCKING findings/new scope/uncertain impact — a partial rerun outside the rules cannot pass this gate). Iterate until a holistic round ends with every required lane `QUALIFYING` and no BLOCKING finding outstanding.
10. Record every finding's disposition in `tasks/<task-name>/reviews/round-<n>/dispositions.md`, and file the `park-follow-up` / `out-of-scope` ones at `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` (dedup first with a recursive `find`). Legacy `ignored-warnings.md` files stay readable but are not written by new runs.

### Build Verification (final step)
11. **MANDATORY:** Run `npm run build`
12. If the build fails:
    a. Fix the build errors
    b. **MANDATORY:** Run `/simplify` on changed files (tiered)
    c. **MANDATORY:** Run a review round on the fix changes at the scope the delta-round rules require (Fable in background + `/codex-chunk` for code fixes); disposition the findings per `review-policy` and iterate only while a BLOCKING finding remains — advisories are parked, not fixed
    d. Rerun `npm run build`
    e. Repeat steps 12a–12d until the build passes
    f. If any build-fix edit could affect behavior covered by more than one phase — including edits to the file that failed to compile — re-run the holistic review (steps 6–10 as applicable, scope per the delta-round rules: delta against the last clean holistic state, or full coverage when the impact boundary is uncertain) before declaring done; if that rerun produces further edits, repeat from step 11
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
- [ ] Per-phase: `/simplify` → parallel review round (`/codex-chunk` ∥ Fable review) passes — both lanes ran and neither produced a BLOCKING finding per `review-policy`; every finding dispositioned in the round ledger, follow-ups parked to `tasks/out-of-scope-issues/`; re-rounds at delta-round-rule scope with recorded baselines
- [ ] Holistic `/simplify` → parallel review round (`/codex-chunk` ∥ Fable review) passes (skip if single-phase)
- [ ] `npm run build` passes

---

## Implementation Rules

- **Orchestrator**: Claude Fable, medium effort
- **Coders (subagents)**: Claude Sonnet 5, high effort
- Orchestrator spawns subagents for all non-trivial code changes; direct edits only for trivial/single-line changes
- No migration or backward-compatibility code unless explicitly requested by the user
- Prefer concise, elegant solutions

## Implementation Workflow

> **⚠ MANDATORY — EVERY STEP BELOW IS A BLOCKING REQUIREMENT.**
> Skipping any step (especially `/simplify`) is a violation. Neither review lane may run until `/simplify` has run on the same files first.
> **Review rounds are dual-lane and parallel.** Lane 1 — Claude Code Fable (high reasoning) Review: a fresh subagent launched via the Agent tool with `run_in_background: true`, a `name` (so delta rounds can message the same reviewer), and `model: "fable"` (or `model: "opus"` — the latest Opus model, prompted for xhigh-reasoning thoroughness — if `"fable"` is unavailable; tell the user, flag the substitution prominently, never substitute silently); the prompt must request high-reasoning thoroughness (the Agent tool has no effort parameter; if an effort selector exists, use `high`); agent type `code-reviewer` for code if available else `general-purpose`, `general-purpose` for docs; the prompt must name the files, the CRITICAL/WARNING/INFO taxonomy, and the `[SEVERITY] file:line — description` output format. Lane 2 — `/codex-chunk` on the same files. Launch the Fable lane FIRST (background), run `/codex-chunk` while it works, then collect BOTH results — never judge a round on the Codex result alone. Both prompts must carry the `review-policy` §8 reviewer contract and ask for a closing `Verdict: PASS | CHANGES_REQUIRED | BLOCKED` line.
> **A round passes when both lanes ran and NEITHER produced a BLOCKING finding — judged by the `review-policy` blocker predicate (grounded + concrete + contract-relevant + material), not by severity label alone.** Advisory findings get a recorded disposition in `tasks/<task-name>/reviews/round-<n>/dispositions.md` and are PARKED, never fixed inside the gate: `park-follow-up` / `out-of-scope` items become `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` files, the rest stay in the ledger. **Remedy scope is bound to the blockers** — a fix batch may touch only what closes a confirmed BLOCKING finding plus its coupled artifacts and semantically affected neighbors. Advisory-only output CLOSES the gate: no source mutation, no rerun. Budget: at most 4 judged-byte-mutating remediation rounds per gate, then convergence mode, then escalate to the user after one more bounded round (the 5th). Split verdicts (one lane PASS, one CHANGES_REQUIRED) run the `review-policy` §7a bilateral cross-lane dispute exchange — the passing lane adjudicates the blockers AND the failing lane adjudicates the passing lane's PASS position, both `[UPHOLD|OBJECT]` per finding; a finding falls only when both lanes object, and anything either lane upholds is remediated and re-rounded, never immediately escalated. A lane that never ran or emitted unparseable output is `BLOCKED_PROCESS` — fail-closed, never parked.
> **Re-rounds after fixes run at DELTA scope.** Round 1 of a gate is always full-coverage; when a round completes, record per-file clean verdicts (diff/blob hashes + round id) in the progress notes. A re-round covers: files changed since their last clean review, files semantically affected by the fix (uncertain impact boundary ⇒ full round instead), files with NO recorded clean baseline (a failed round 1 leaves none — the next round is effectively full again), and one small delta-interactions chunk; only files with a recorded clean baseline carry verdicts forward. Write the delta round's scope list into the notes before launching it — under-scoping without that trail is non-compliant. Before ANY re-round, batch coupled artifacts into the fix (indexes for query/sort changes, config, docs, callers of changed signatures — fix each or clear it with a one-line recorded rationale). Tiers (behavior classification FIRST): behavior-affecting or uncertain fixes ⇒ dual-lane delta round regardless of size; confirmed non-behavioral doc-only fixes (no code files) ⇒ single-agent `/simplify` (this IS the mandatory post-fix `/simplify` for this tier, never a skip) + a single-lane delta check by the persistent Fable reviewer (the ONLY two-lane exception); confirmed non-behavioral ≤5-line mechanical code fixes ⇒ dual-lane delta round; new files/scope ⇒ treat as round 1 for that content (full dual-lane review of it plus semantically affected neighbors); any BLOCKING finding ⇒ full round. A partial rerun outside these rules cannot pass a gate.

### Per-Phase Implementation Review
1. Implement the phase
2. **MANDATORY:** Run `/simplify` on the phase's changed files — implement any changes it produces
3. **MANDATORY:** Run a parallel review round on all changed files in the phase — Fable review in background + `/codex-chunk` (PREREQUISITE: step 2 must be complete). Round 1 is full-coverage; record the reviewed state when clean.
4. Disposition every finding per `review-policy` into `tasks/<task-name>/reviews/round-<n>/dispositions.md`. **If NO finding is BLOCKING → the gate is PASSED**: write the `park-follow-up` / `out-of-scope` items to `tasks/out-of-scope-issues/<priority>/`, change nothing else, and move on.
5. If a finding IS BLOCKING — where a split-verdict round (one lane `PASS`, one `CHANGES_REQUIRED`) FIRST runs the `review-policy` §7a bilateral dispute exchange, and only findings that survived the exchange enter remediation: fix ONLY the blockers (batching their coupled artifacts) → re-run `/simplify` scoped to the fix (tiered) → re-run a round at the scope the delta-round rules require (dual-lane delta by default; full for BLOCKING findings/new scope/uncertain impact; single-lane check only for doc-only fixes). Iterate until a round ends with every required lane `QUALIFYING` and no BLOCKING finding outstanding; at 4 mutating rounds, enter convergence mode and escalate after one more (the 5th).

### Holistic Review (after all phases complete)
SKIP if single-phase plan. Otherwise:
6. **MANDATORY:** Run `/simplify` on ALL changed files across all phases
7. **MANDATORY:** Run a parallel review round on ALL changed files together — Fable review in background + `/codex-chunk` (PREREQUISITE: step 6 must be complete). The first holistic round is full-coverage; record the reviewed state when clean.
8. Disposition every finding per `review-policy`. **If NO finding is BLOCKING → the holistic gate is PASSED**; park the follow-ups and proceed to build verification without touching source.
9. If a finding IS BLOCKING: fix ONLY the blockers (batching coupled artifacts) → re-run `/simplify` scoped to the fix (tiered) → re-run a holistic round at the scope the delta-round rules require (dual-lane delta against the last clean holistic state by default; full coverage for BLOCKING findings/new scope/uncertain impact — a partial rerun outside the rules cannot pass this gate). Iterate until a holistic round ends with every required lane `QUALIFYING` and no BLOCKING finding outstanding.
10. Record every finding's disposition in `tasks/<task-name>/reviews/round-<n>/dispositions.md`, and file the `park-follow-up` / `out-of-scope` ones at `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` (dedup first with a recursive `find`). Legacy `ignored-warnings.md` files stay readable but are not written by new runs.

### Build Verification (final step)
11. **MANDATORY:** Run `npm run build`
12. If the build fails:
    a. Fix the build errors
    b. **MANDATORY:** Run `/simplify` on changed files (tiered)
    c. **MANDATORY:** Run a review round on the fix changes at the scope the delta-round rules require (Fable in background + `/codex-chunk` for code fixes); disposition the findings per `review-policy` and iterate only while a BLOCKING finding remains — advisories are parked, not fixed
    d. Rerun `npm run build`
    e. Repeat steps 12a–12d until the build passes
    f. If any build-fix edit could affect behavior covered by more than one phase — including edits to the file that failed to compile — re-run the holistic review (steps 6–10 as applicable, scope per the delta-round rules: delta against the last clean holistic state, or full coverage when the impact boundary is uncertain) before declaring done; if that rerun produces further edits, repeat from step 11
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
- [ ] Per-phase: `/simplify` → parallel review round (`/codex-chunk` ∥ Fable review) passes — both lanes ran and neither produced a BLOCKING finding per `review-policy`; every finding dispositioned in the round ledger, follow-ups parked to `tasks/out-of-scope-issues/`; re-rounds at delta-round-rule scope with recorded baselines
- [ ] Holistic `/simplify` → parallel review round (`/codex-chunk` ∥ Fable review) passes across all phases
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
- [ ] `/simplify` → parallel review round (`/codex-chunk` ∥ Fable review) passes (both lanes ran; no BLOCKING finding per `review-policy`; advisories dispositioned and parked)
- [ ] Mark phase N complete in `progress.md`
```

---

### Step 7: Parallel Plan Review — Codex ∥ Fable (Finalization)

Each plan document must pass BOTH review lanes before it is considered final. This step ensures the written documents are already approved when output to the user.

**Judge this gate with the `review-policy` contract.** A document passes when both lanes ran and neither produced a **BLOCKING** finding — not when the reviewers run out of suggestions. For a plan document the blocker predicate means: the finding is grounded in the document's actual text, names a concrete failure mode, violates an explicit requirement or repository rule, and is material — it would cause unsafe implementation, an incorrect command, wrong authorization or data-integrity behavior, or would force the implementer to invent material behavior the plan should have settled. Wording polish, structure preferences, extra-detail requests, and speculative hardening are **advisory**.

For each document (`spec.md` first, then each TODO document — `todo.md`, or `progress.md` + each `todo-phase-N.md`):

1. Launch the Claude Code Fable (high reasoning) Review in the background: a `general-purpose` subagent via the Agent tool with `run_in_background: true` and `model: "fable"` (if the harness no longer offers `"fable"`, fall back to `model: "opus"` — the latest Opus model, prompted for xhigh-reasoning thoroughness — and tell the user; flag the substitution prominently, never substitute silently). The prompt must request high-reasoning thoroughness (no effort parameter exists on the Agent tool; if an effort selector exists, use `high`), name the document, give review context, the CRITICAL/WARNING/INFO taxonomy, and the `[SEVERITY] file:line — description` output format (same as `/codex-chunk`, so the two lanes' findings merge cleanly). It must also carry the `review-policy` §8 reviewer contract (don't blockerize style/preference; classify against the declared scope; `PASS` is correct when only advisories remain; blockers carry evidence + failure mode + violated contract) and ask for a closing `Verdict: PASS | CHANGES_REQUIRED | BLOCKED` line.
2. Submit the same document to `/codex-chunk` for review while the Fable lane runs
3. Collect BOTH results (wait for the background Fable notification — never judge on the Codex result alone) and merge the findings by stable finding ID
4. Disposition every finding per `review-policy` and record the ledger at `tasks/<taskSubDir>/reviews/round-<n>/dispositions.md`
5. **If NO finding is BLOCKING → this document is final. Stop.** Write the `park-follow-up` / `out-of-scope` findings to `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` (dedup first with a recursive `find` across every priority subdir including `manual/`), and move to the next document. Do NOT revise the document, do NOT resubmit — a passing round that gets patched anyway is the churn loop this policy exists to stop.
6. If at least one finding IS BLOCKING (split-verdict rounds go through item 7's bilateral dispute exchange FIRST — only findings that survived the exchange enter this step): patch **only** what closes those blockers (remedy-scope binding — `review-policy` §5), then resubmit that document to BOTH lanes. Increment the round count; on reaching **4** document-mutating rounds, enter convergence mode and escalate to the user after one more bounded blocker round (the 5th).
7. If the round ends with **split verdicts** — one lane `PASS`, the other `CHANGES_REQUIRED` — do not override the failing lane and do not escalate: run the `review-policy` §7a bilateral cross-lane dispute exchange. Run **both** directions on the same bytes (concurrently is fine): the passing lane adjudicates the disputed blockers (Codex: `/codex-chunk dispute --role meta`; Fable: SendMessage to that document's reviewer, or a fresh subagent given the prior-verdict summary), and the failing lane adjudicates the passing lane's PASS position — its verdict, rationale, and notes on the disputed material — re-examining its own blockers against it (Codex: `/codex-chunk dispute --role reconsider`; Fable: SendMessage). Both answer `[UPHOLD|OBJECT] F-xxx` per finding plus a closing `Verdict: UPHOLD | OBJECT`. A finding is dropped only when **both** lanes object (`reject-unsupported`); anything either lane upholds stands — patch only those blockers and resubmit per step 6. Both lanes objecting to everything closes the gate; a direction that returns `BLOCKED` or unparseable output fails closed with one process retry allowed. If both lanes fail and you judge a finding non-blocking, use the §7 clarification-rerun flow; escalation comes only from the round budget.

> Finalization re-rounds are intentionally always full dual-lane — plan
> documents are small, so delta scoping buys nothing here. The delta-round
> rules embedded in the generated templates apply to `/plan-code`
> implementation reviews, not to this step.

Only proceed to Step 8 after every document has a round with both lanes `QUALIFYING` and no BLOCKING finding outstanding.

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
6. Confirmation that all documents passed BOTH review lanes (`/codex-chunk` and the Claude Code Fable (high reasoning) Review), with round counts per document
7. The review disposition summary: how many findings were BLOCKING (and were patched) vs. parked, the ledger paths, and the paths of any out-of-scope issue files written for parked findings — so the user can see what was deliberately deferred rather than fixed

---

### Step 10: Emit Kickoff Prompt (MANDATORY)

After the Step 9 report, emit a copy-pasteable kickoff prompt that wires the newly created task into a `/plan-code` invocation. Render it inside a fenced code block so the user can copy it verbatim.

Substitute the actual task subdirectory name (the kebab-case task name from Step 1).

````
```
/plan-code @tasks/<taskSubDir>

- Automatically start the next steps, phases, tasks unless you need a user decision or manual handling step that you captured in Step 3. If so, wait for the user to complete those before proceeding.
- Remove the task files after completing the task.
- do not create any migration / backward compatibility codes.
```
````

Do NOT start implementing. This skill creates plan documents only — the user runs the kickoff prompt when they're ready.
