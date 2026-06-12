---
name: plan-code
description: Executes implementation plans phase-by-phase with iterative parallel review cycles (Codex chunked review + Claude Code Fable5 review, run concurrently). Use this whenever the user wants to implement a plan — either from /plan-doc files (e.g., "/plan-code @tasks/my-feature") or from an in-context plan (e.g., "/plan-code implement this plan"). Triggers on "/plan-code", "implement the plan", "start coding the plan", "execute the phases". Always use this for plan-based implementation to ensure proper review discipline.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill(codex-chunk), Skill(simplify), EnterPlanMode, ExitPlanMode, AskUserQuestion
---

# plan-code

Implements a plan phase-by-phase with `/simplify`, an iterative **parallel review round** per phase (`/codex-chunk` + Claude Code Fable5 Review, run concurrently, both must be clean), and a final holistic review. Works with `/plan-doc` output files or in-context plans.

## Usage

```
/plan-code @tasks/<task-name>          # from plan-doc files
/plan-code implement this plan         # from in-context plan
```

## Enforcement Rule

> **MANDATORY — NO EXCEPTIONS.** Every numbered step and every checkable item (`- [ ]`) in the plan documents is a **blocking requirement**. You MUST execute each one in order. Skipping, reordering, or "optimizing away" any step — including `/simplify`, the Claude Code Fable5 Review lane, or the Step 2a Decision Gate — is a violation. If you are about to start a review round (`/codex-chunk` + Fable5), STOP and verify you have already run `/simplify` on the same files first. If you haven't, go back and run it. A review round has TWO mandatory lanes — running only Codex (or only Fable5) and declaring the round clean is a violation, as is advancing before the background Fable5 result has been collected. The Step 2a Decision Gate is equally non-bypassable: a general "no clarifying questions" / "work without stopping" instruction is NOT the per-task "just decide" bypass — see Step 2a for the exact rule. This Enforcement Rule exists because there is a documented pattern of skipping `/simplify` (and silently absorbing architectural decisions) to save time, which defeats the purpose of the review workflow.

---

## Preflight (MANDATORY before Step 1)

This skill orchestrates **`/simplify`** and **`/codex-chunk`**. Before doing
anything else, verify BOTH appear in the available-skills list shown in your
system context.

If either is missing, STOP and tell the user which one is missing and how to
install it:

- `/simplify` — built into Claude Code itself (Claude Code >= 2.x ships with
  this skill). If it is missing, the user is on an older release; do not
  proceed.
- `/codex-chunk` — install with
  `/plugin install codex-chunk@tahara-claude-plugins`

You MUST NOT substitute these with other skills or agents (e.g.,
`code-simplifier`, `code-review`, generic `Agent(...)` calls). The
documented review cycle (`/simplify` → parallel review round → fix →
repeat) depends on the *specific* behavior of these two skills.
Substitution silently breaks the cycle and is a procedural violation, not
a workaround. Halt and surface the missing dependency rather than
improvising.

The review workflow's second lane — the **Claude Code Fable5 Review**
(defined below) — needs NO install: it uses Claude Code's built-in Agent
tool. It is equally non-substitutable: the Fable5 lane never replaces
`/codex-chunk`, and `/codex-chunk` never replaces the Fable5 lane. Every
review round runs BOTH.

This preflight is a one-time check at skill entry. After it passes, follow
the procedure below — and at every "Run `/simplify`" or "Run `/codex-chunk`"
step, invoke the EXACT named skill, never a substitute. Equally: every
review round must LAUNCH the Fable5 lane and COLLECT its background result —
a round that ran only one lane is incomplete, not clean.

---

## Claude Code Fable5 Review — definition

The second lane of every review round: an independent review by a **fresh
Claude Code subagent** (never the implementer context reviewing itself),
run in parallel with `/codex-chunk`.

- **Launch:** Agent tool with `run_in_background: true` and
  `model: "fable"` — the Agent tool's model selector for Fable 5. If the
  harness no longer offers `"fable"`, use the newest flagship selector it
  does offer and tell the user — flag the substitution prominently in the
  final report; never substitute silently.
- **Agent type:** `code-reviewer` for code reviews if the session offers
  it, otherwise `general-purpose`; `general-purpose` for plan-document
  reviews.
- **Prompt MUST include:** the exact files (or sections) to review, the
  CRITICAL/WARNING/INFO severity taxonomy, and the output format
  `[SEVERITY] file:line — description` (identical to `/codex-chunk`), so
  findings from both lanes merge cleanly.
- **Collection:** the result arrives via background-task notification and
  MUST be collected before the round can be judged. Never declare a round
  clean on the Codex result alone.
- **Parallel pattern:** launch the Fable5 subagent FIRST (background),
  then run `/codex-chunk` in the foreground, then collect both results.

---

## Procedure

### Step 1: Load the Plan

**From files** (`@tasks/<task-name>`):
1. Read `spec.md` for technical approach and implementation rules
2. Read `todo.md` (small plan) or `progress.md` + all `todo-phase-N.md` files (large plan)
3. Identify all phases and their tasks

**From context** (in-context plan):
1. Extract phases and tasks from the conversation
2. If the plan isn't already chunked into phases, organize it into logical phases before proceeding
3. Confirm the phase breakdown with the user if it wasn't explicit

### Step 2: Execute Each Phase

> **Auto-advance between phases.** Once a phase finishes Step 2e (Update Progress), immediately begin the next phase. Do NOT pause to ask "ready to continue?", "should I proceed?", "shall I start phase N+1?", or otherwise wait for a go-ahead — the plan was already approved when `/plan-code` started, and phases run continuously until either every phase is complete or the Step 2a Decision Gate fires. The user can interrupt at any time to redirect.

For each phase, run this cycle. **All five sub-steps (2a–2e) are MANDATORY. Do NOT skip any.**

#### 2a. Decision Gate (MANDATORY — BLOCKING)

> **STOP and ask before implementing whenever an unresolved decision surfaces.** This mirrors `/plan-doc` Step 3 and applies both at the start of the phase AND mid-implementation. If implementation requires a non-trivial architectural, API, data-model, error-handling, scope, or UX choice that the plan (`spec.md` or the in-context plan) does not already settle, you MUST surface it via `AskUserQuestion` and wait for the answer before writing or continuing the affected code.

**At phase start:** scan this phase's tasks against `spec.md` (or the in-context plan). For each task, ask: "is the choice this implies already settled by `spec.md`'s `## Decisions`, by `CLAUDE.md`, or by existing code?" If not, it is an open decision and goes to the gate.

**Mid-implementation:** if a fresh decision surfaces while writing code, halt that file's work and run the gate before continuing. Do NOT guess and "patch later" — that defeats the gate.

**What counts as a blocking decision** (same categories as `/plan-doc` Step 3.1):

- Library / framework choice when more than one plausible option exists
- Architectural pattern — new module vs. inline; sync vs. async; queue vs. direct call; shared module vs. local helper
- Data model / schema — new column vs. new table; nullable vs. default; index changes that affect query shape
- Public API shape — return value vs. throw; optional vs. required field; naming; versioning
- Error-handling policy — swallow + log, surface to caller, retry, fail fast
- Performance / resource trade-offs — cache TTL, batch size, pagination, concurrency
- UX-visible choices — default state, label copy, behavior on empty/error
- Scope boundaries — "does this also fix the related Y?" / "should X be touched here?"
- Manual-handling needs — info you cannot get without the user (repro, credentials, prod state, devices, third-party access)

**What does NOT need a gate**:

- Choices already resolved in `spec.md`'s `## Decisions`, in `CLAUDE.md`, or enforced by existing code — take those answers, don't re-ask
- Mechanical follow-through (variable names, file layout that mirrors existing code, formatting) — just decide
- Trivially-reversible choices in test scaffolding or throwaway scratch code

**How to ask**:

- Bundle related questions into a single `AskUserQuestion` call. Cap at ~4 questions per round; ask the most consequential first if more remain.
- Present 2–4 concrete options per decision with a one-line trade-off per option. Avoid open-ended "what do you think?" prompts when a multiple-choice question would do.
- For manual-handling needs: ask the user to supply the missing input now, OR confirm the plan should record the manual step explicitly so it lands in the TODO with the user as the actor.

**After the user answers**:

- Record each answer under `## Decisions` in `spec.md` (file-based plans) or in-line in your running report (in-context plans), tagged with the phase that surfaced it.
- Resume the phase — do NOT restart the skill from Step 1.

> **The "just decide" bypass.** If the user has explicitly said "just decide" / "use your judgment" / "your call" *for this task*, proceed with your best call and record it under `## Decisions` tagged "(no user input — Claude's call)". A general session-level "no clarifying questions" / "work without stopping" instruction is NOT this bypass — only an explicit per-task delegation counts. This matches `/plan-doc` Step 3's bypass rule.

#### 2b. Implement

- Follow implementation rules from the plan (spec.md or in-context)
- No migration or backward-compatibility code unless explicitly requested

#### 2c. Simplify (MANDATORY — DO NOT SKIP)

> **BLOCKING GATE:** You MUST complete this step before proceeding to 2d. Starting a review round (either lane) without first running `/simplify` is a violation.

1. Run `/simplify` on the phase's changed files
2. Implement the `/simplify` plan (if it produces changes)

#### 2d. Parallel Review Round — Codex ∥ Fable5 (MANDATORY — DO NOT SKIP)

> **PREREQUISITE CHECK:** Before starting the review round, confirm you have already run `/simplify` on this phase's files in step 2c. If you have not, STOP and go back to 2c.

1. Launch the Claude Code Fable5 Review subagent (see definition above) in the background on all files changed in this phase
2. Run `/codex-chunk` on the same files while the Fable5 review runs
3. Collect BOTH results (wait for the background Fable5 notification — do not advance on the Codex result alone), then merge and dedup the findings
4. If EITHER lane returns CRITICAL findings or worth-addressing WARNINGs:
   - Fix the issues (union of both lanes' findings)
   - Run `/simplify` on the fixes (MANDATORY — do not skip even for "small" fixes)
   - Rerun the FULL round (both lanes) on ALL files changed in this phase — not just the files that were fixed
5. Iterate until BOTH lanes return clean in the same round

#### 2e. Update Progress (MANDATORY — DO NOT SKIP)

**File-based plan**: Check off completed tasks in `todo.md` or `todo-phase-N.md`, and mark the phase complete in `progress.md` if applicable.

**In-context plan**: Note the phase as complete and summarize what was done.

> After 2e, immediately start the next phase at 2a (Decision Gate). Do NOT pause for user confirmation between phases.

---

### Step 3: Holistic Review (MANDATORY for multi-phase plans)

> **SKIP this step ONLY if the plan has a single phase.** For all multi-phase plans, this step is MANDATORY.

After all phases are complete:

1. Run `/simplify` on ALL changed files across all phases **(MANDATORY — do not skip)**
2. Run a parallel review round on ALL changed files together **(MANDATORY — do not skip)**: launch the Fable5 review subagent in the background, run `/codex-chunk` on the same files, collect both results
3. If EITHER lane finds CRITICAL or worth-addressing WARNING findings:
   a. Fix the issues (union of both lanes' findings)
   b. Run `/simplify` on the fixes (MANDATORY)
   c. Rerun the FULL holistic round (both lanes) on ALL changed files together — a holistic round only counts when it covers every changed file; a partial rerun on affected files alone cannot pass this gate
   d. Document all skipped or ignored warnings (from either lane) in `tasks/<task-name>/ignored-warnings.md` (file-based) or report them in-context
4. Repeat steps 1–3 until BOTH lanes return a clean holistic round

---

### Step 4: Build Verification (MANDATORY)

After the holistic review passes:

1. Run `npm run build`
2. If the build succeeds, proceed to Step 5
3. If the build fails:
   a. Fix the build errors
   b. Run `/simplify` on the fixes (MANDATORY)
   c. Run a parallel review round on the fix changes (Fable5 in background + `/codex-chunk`); iterate until both lanes are clean (fix → `/simplify` → both lanes)
   d. Rerun `npm run build`
   e. Repeat steps 3a–3d until the build passes
   f. If any build-fix edit could affect behavior covered by more than one phase — including edits to the file that failed to compile — re-run the FULL holistic round (Step 3, both lanes, ALL changed files) before proceeding to Step 5; if that holistic rerun produces further edits, repeat Step 4 (build verification) before completion

---

### Step 5: Completion (MANDATORY)

1. **File-based plan**: Mark all completion criteria checked in `progress.md` or `todo.md`
2. Report to the user:
   - Summary of all phases completed
   - Decisions surfaced via the Step 2a gate (one line each: phase + Q → A) so the user can see which calls were settled with their input vs. punted to Claude under an explicit "just decide" bypass
   - Any warnings that were skipped or ignored (with rationale, noting which lane raised them)
   - Build verification result
   - Total number of `/simplify` iterations and review rounds performed, with per-lane counts (`/codex-chunk` and Fable5) — to prove both lanes ran every round
