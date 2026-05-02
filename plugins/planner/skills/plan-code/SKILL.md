---
name: plan-code
description: Executes implementation plans phase-by-phase with iterative Codex review cycles. Use this whenever the user wants to implement a plan — either from /plan-doc files (e.g., "/plan-code @tasks/my-feature") or from an in-context plan (e.g., "/plan-code implement this plan"). Triggers on "/plan-code", "implement the plan", "start coding the plan", "execute the phases". Always use this for plan-based implementation to ensure proper review discipline.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill(codex-chunk), Skill(simplify), EnterPlanMode, ExitPlanMode, AskUserQuestion
---

# plan-code

Implements a plan phase-by-phase with iterative Codex review, `/simplify`, and a final holistic review. Works with `/plan-doc` output files or in-context plans.

## Usage

```
/plan-code @tasks/<task-name>          # from plan-doc files
/plan-code implement this plan         # from in-context plan
```

## Enforcement Rule

> **MANDATORY — NO EXCEPTIONS.** Every numbered step and every checkable item (`- [ ]`) in the plan documents is a **blocking requirement**. You MUST execute each one in order. Skipping, reordering, or "optimizing away" any step — including `/simplify` — is a violation. If you are about to run `/codex-chunk`, STOP and verify you have already run `/simplify` on the same files first. If you haven't, go back and run it. This rule exists because there is a documented pattern of skipping `/simplify` to save time, which defeats the purpose of the review workflow.

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
documented review cycle (`/simplify` → `/codex-chunk` → fix → repeat)
depends on the *specific* behavior of these two skills. Substitution
silently breaks the cycle and is a procedural violation, not a workaround.
Halt and surface the missing dependency rather than improvising.

This preflight is a one-time check at skill entry. After it passes, follow
the procedure below — and at every "Run `/simplify`" or "Run `/codex-chunk`"
step, invoke the EXACT named skill, never a substitute.

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

For each phase, run this cycle. **All four sub-steps (2a–2d) are MANDATORY. Do NOT skip any.**

#### 2a. Implement

- Follow implementation rules from the plan (spec.md or in-context)
- No migration or backward-compatibility code unless explicitly requested

#### 2b. Simplify (MANDATORY — DO NOT SKIP)

> **BLOCKING GATE:** You MUST complete this step before proceeding to 2c. Running `/codex-chunk` without first running `/simplify` is a violation.

1. Run `/simplify` on the phase's changed files
2. Implement the `/simplify` plan (if it produces changes)

#### 2c. Codex Review (MANDATORY — DO NOT SKIP)

> **PREREQUISITE CHECK:** Before running `/codex-chunk`, confirm you have already run `/simplify` on this phase's files in step 2b. If you have not, STOP and go back to 2b.

1. Run `/codex-chunk` on all files changed in this phase
2. If Codex returns CRITICAL findings or worth-addressing WARNINGs:
   - Fix the issues
   - Run `/simplify` on the fixes (MANDATORY — do not skip even for "small" fixes)
   - Rerun `/codex-chunk` on affected files
3. Iterate until Codex returns a clean review

#### 2d. Update Progress (MANDATORY — DO NOT SKIP)

**File-based plan**: Check off completed tasks in `todo.md` or `todo-phase-N.md`, and mark the phase complete in `progress.md` if applicable.

**In-context plan**: Note the phase as complete and summarize what was done.

---

### Step 3: Holistic Review (MANDATORY for multi-phase plans)

> **SKIP this step ONLY if the plan has a single phase.** For all multi-phase plans, this step is MANDATORY.

After all phases are complete:

1. Run `/simplify` on ALL changed files across all phases **(MANDATORY — do not skip)**
2. Run `/codex-chunk` on ALL changed files across all phases together **(MANDATORY — do not skip)**
3. If Codex finds CRITICAL or worth-addressing WARNING findings:
   a. Fix the issues
   b. Run `/simplify` on the fixes (MANDATORY)
   c. Rerun `/codex-chunk` on affected files; iterate until clean
   d. Document all skipped or ignored warnings in `tasks/<task-name>/ignored-warnings.md` (file-based) or report them in-context
4. Repeat steps 1–3 until Codex returns a clean holistic review

---

### Step 4: Build Verification (MANDATORY)

After the holistic review passes:

1. Run `npm run build`
2. If the build succeeds, proceed to Step 5
3. If the build fails:
   a. Fix the build errors
   b. Run `/simplify` on the fixes (MANDATORY)
   c. Run `/codex-chunk` on the fix changes; iterate until clean (fix → `/simplify` → `/codex-chunk`)
   d. Rerun `npm run build`
   e. Repeat steps 3a–3d until the build passes

---

### Step 5: Completion (MANDATORY)

1. **File-based plan**: Mark all completion criteria checked in `progress.md` or `todo.md`
2. Report to the user:
   - Summary of all phases completed
   - Any warnings that were skipped or ignored (with rationale)
   - Build verification result
   - Total number of `/simplify` and `/codex-chunk` iterations performed (to prove they were run)
