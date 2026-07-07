---
name: plan-code
description: Executes implementation plans phase-by-phase with iterative parallel review cycles (Codex chunked review + Claude Code Opus 4.8 (xhigh reasoning) review, run concurrently). Use this whenever the user wants to implement a plan — either from /plan-doc files (e.g., "/plan-code @tasks/my-feature") or from an in-context plan (e.g., "/plan-code implement this plan"). Triggers on "/plan-code", "implement the plan", "start coding the plan", "execute the phases". Always use this for plan-based implementation to ensure proper review discipline.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, SendMessage, Skill(codex-chunk), Skill(simplify), EnterPlanMode, ExitPlanMode, AskUserQuestion
---

# plan-code

Implements a plan phase-by-phase with `/simplify`, an iterative **parallel review round** per phase (`/codex-chunk` + Claude Code Opus 4.8 (xhigh reasoning) Review, run concurrently, both must be clean), and a final holistic review. Re-rounds after fixes run at **delta scope** (see "Review Rounds: full vs. delta") so unchanged, already-clean content is not re-reviewed. Works with `/plan-doc` output files or in-context plans.

## Usage

```
/plan-code @tasks/<task-name>          # from plan-doc files
/plan-code implement this plan         # from in-context plan
```

## Enforcement Rule

> **MANDATORY — NO EXCEPTIONS.** Every numbered step and every checkable item (`- [ ]`) in the plan documents is a **blocking requirement**. You MUST execute each one in order. Skipping, reordering, or "optimizing away" any step — including `/simplify`, the Claude Code Opus 4.8 (xhigh reasoning) Review lane, or the Step 2a Decision Gate — is a violation. If you are about to start a review round (`/codex-chunk` + Opus 4.8), STOP and verify you have already run `/simplify` on the same files first. If you haven't, go back and run it. A review round has TWO mandatory lanes — running only Codex (or only Opus 4.8) and declaring the round clean is a violation (the ONLY exception is the doc-only fix tier defined in "Review Rounds: full vs. delta"), as is advancing before the background Opus 4.8 result has been collected. Re-rounds after fixes follow the delta-round rules in "Review Rounds: full vs. delta" — a delta round per those rules IS compliant; any partial rerun *outside* those rules cannot pass a gate. The Step 2a Decision Gate is equally non-bypassable: a general "no clarifying questions" / "work without stopping" instruction is NOT the per-task "just decide" bypass — see Step 2a for the exact rule. This Enforcement Rule exists because there is a documented pattern of skipping `/simplify` (and silently absorbing architectural decisions) to save time, which defeats the purpose of the review workflow.

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

The review workflow's second lane — the **Claude Code Opus 4.8 (xhigh
reasoning) Review** (defined below) — needs NO install: it uses Claude
Code's built-in Agent tool. It is equally non-substitutable: the Opus 4.8
lane never replaces `/codex-chunk`, and `/codex-chunk` never replaces the
Opus 4.8 lane. Every review round except the doc-only fix tier (defined in
"Review Rounds: full vs. delta") runs BOTH.

This preflight is a one-time check at skill entry. After it passes, follow
the procedure below — and at every "Run `/simplify`" or "Run `/codex-chunk`"
step, invoke the EXACT named skill, never a substitute. Equally: every
review round must LAUNCH the Opus 4.8 lane and COLLECT its background result —
a round that ran only one lane is incomplete, not clean.

---

## Claude Code Opus 4.8 (xhigh reasoning) Review — definition

The second lane of every review round: an **independent Claude Code
subagent** (never the implementer context reviewing itself), run in
parallel with `/codex-chunk`. It is spawned fresh for a gate's round 1,
then reused persistently for that gate's delta rounds.

- **Launch:** Agent tool with `run_in_background: true`, a `name` (record
  the name in the phase's progress notes — delta rounds MUST message that
  recorded reviewer, not a new one), and `model: "opus"` — the Agent
  tool's model selector for Opus 4.8. If the harness no longer offers
  `"opus"`, use the newest flagship selector it does offer and tell the
  user — flag the substitution prominently in the final report; never
  substitute silently.
- **Reasoning effort: xhigh.** The Agent tool has no effort parameter, so
  the prompt itself must request xhigh-reasoning thoroughness (e.g. "review
  with high scrutiny; verify the math/invariants by hand, don't skim"). If
  the harness exposes an effort selector for subagents, set it to `xhigh`.
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
- **Parallel pattern:** launch the Opus 4.8 subagent FIRST (background),
  then run `/codex-chunk` in the foreground, then collect both results.
- **Delta rounds:** for re-rounds after fixes, message the SAME persistent
  reviewer (SendMessage to its name) with the delta description instead of
  spawning a fresh full-context subagent — it retains the change-set
  context, making delta verification fast. If the harness cannot message a
  previous subagent, spawn a fresh one scoped to the delta plus the
  prior-verdict summary.

---

## Review Rounds: full vs. delta — definition

These rules govern how much a review round must cover. They exist because
of a measured failure mode: re-reviewing byte-identical content after every
fix found zero new issues across an entire session while consuming most of
its review calls.

**Round 1 of any gate (per-phase 2d, holistic Step 3) is always
FULL-COVERAGE** — every changed file in the gate's scope, both lanes.

**Re-rounds after fixes run at DELTA scope.** A delta round re-reviews:

- (a) files changed since their last clean review;
- (b) files **semantically affected** by the fix even if unchanged —
  contract, query-shape, config, or exported-behavior changes ripple into
  callers/consumers; when the impact boundary is uncertain, run a FULL
  round instead of guessing;
- (c) one small "delta interactions" chunk describing what the fix changed
  and what it couples to.

Unchanged, unaffected files carry their clean verdicts forward — but a
file may carry a verdict forward ONLY if a recorded clean review exists
for its current content. Files with NO recorded clean baseline (e.g. the
round that covered them was not clean, or they were never reviewed) are
ALWAYS in the re-round's scope — a failed round 1 leaves no baselines to
carry, so the next round is effectively full again.
**Audit requirement:** when a round completes, record per-file/per-chunk
clean verdicts — the reviewed state (`git diff` hash or per-file blob
hashes) plus a round id — in the phase's progress notes; "unchanged"
always means "unchanged relative to a recorded clean state", never a
guess. Before launching a delta round, write its scope list (changed /
semantically-affected / no-baseline files) into the same notes —
under-scoping without this written trail is non-compliant.

**Coupled-artifact fix batching (before ANY re-round).** Enumerate the
infrastructure coupled to the mechanism you just changed — index
definitions for query/sort changes, config for behavior flags, docs for
renamed exports, callers of changed signatures — and, in the same batch,
either fix each one or clear it with a one-line recorded rationale in the
progress notes (a private "looks fine" is not a clearance). This prevents
the serial one-finding-per-round pattern where each re-round discovers the
next coupled artifact.

**Tiered ceremony (precedence order — behavior classification FIRST):**

1. Any behavior-affecting or uncertain-coupling fix → dual-lane delta
   round, regardless of size.
2. Confirmed non-behavioral, low-coupling, **doc-only** fix (no code files
   touched) → single-agent `/simplify` (this IS the mandatory post-fix
   `/simplify` for this tier — a reduced fan-out, never a skip) + a
   single-lane delta check by the persistent Opus 4.8 reviewer. This is the
   ONLY defined exception to the two-lane requirement.
3. Confirmed non-behavioral, low-coupling, **≤5-line mechanical code** fix
   → dual-lane delta round (both lanes, delta scope).
4. New files or new scope entering the change-set → treat the new content
   as round 1: full dual-lane review of it plus its semantically affected
   neighbors; previously clean files keep their recorded verdicts.
5. Any CRITICAL finding → full round after the fix.

A gate passes when a round — full or delta, per these rules — ends with
every required lane clean. A partial rerun outside these rules cannot pass
a gate.

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

#### 2d. Parallel Review Round — Codex ∥ Opus 4.8 (MANDATORY — DO NOT SKIP)

> **PREREQUISITE CHECK:** Before starting the review round, confirm you have already run `/simplify` on this phase's files in step 2c. If you have not, STOP and go back to 2c.

1. Launch the Claude Code Opus 4.8 (xhigh reasoning) Review subagent (see definition above) in the background on all files changed in this phase
2. Run `/codex-chunk` on the same files while the Opus 4.8 review runs
3. Collect BOTH results (wait for the background Opus 4.8 notification — do not advance on the Codex result alone), then merge and dedup the findings. When the round completes, record per-file/per-chunk clean verdicts (diff hash + round id) per "Review Rounds: full vs. delta" — including the clean portions of a round that had findings elsewhere.
4. If EITHER lane returns CRITICAL findings or worth-addressing WARNINGs:
   - Fix the issues (union of both lanes' findings), batching coupled artifacts per "Review Rounds: full vs. delta"
   - Run `/simplify` on the fixes (MANDATORY — single-agent tier allowed only per the tiered-ceremony rules)
   - Rerun a review round at the scope the delta-round rules require (dual-lane delta round by default; full round for CRITICALs, new scope, or uncertain impact; single-lane check only for the doc-only tier)
5. Iterate until the round (full or delta, per the rules) ends with every required lane clean

#### 2e. Update Progress (MANDATORY — DO NOT SKIP)

**File-based plan**: Check off completed tasks in `todo.md` or `todo-phase-N.md`, and mark the phase complete in `progress.md` if applicable.

**In-context plan**: Note the phase as complete and summarize what was done.

> After 2e, immediately start the next phase at 2a (Decision Gate). Do NOT pause for user confirmation between phases.

---

### Step 3: Holistic Review (MANDATORY for multi-phase plans)

> **SKIP this step ONLY if the plan has a single phase.** For all multi-phase plans, this step is MANDATORY.

After all phases are complete:

1. Run `/simplify` on ALL changed files across all phases **(MANDATORY — do not skip)**
2. Run a parallel review round on ALL changed files together **(MANDATORY — do not skip)**: launch the Opus 4.8 review subagent in the background, run `/codex-chunk` on the same files, collect both results. This first holistic round is always FULL-COVERAGE; record the reviewed state when clean.
3. If EITHER lane finds CRITICAL or worth-addressing WARNING findings:
   a. Fix the issues (union of both lanes' findings), batching coupled artifacts per "Review Rounds: full vs. delta"
   b. Run `/simplify` on the fixes (MANDATORY — single-agent tier allowed only per the tiered-ceremony rules)
   c. Rerun a holistic round at the scope the delta-round rules require — dual-lane delta round (changed + semantically affected files + the delta-interactions chunk, clean verdicts carried forward) by default; full coverage again for CRITICALs, new scope, or uncertain impact. A partial rerun outside those rules cannot pass this gate.
   d. Document all skipped or ignored warnings (from either lane) in `tasks/<task-name>/ignored-warnings.md` (file-based) or report them in-context
4. Repeat steps 1–3 until a holistic round (full or delta, per the rules) ends with every required lane clean

---

### Step 4: Build Verification (MANDATORY)

After the holistic review passes:

1. Run `npm run build`
2. If the build succeeds, proceed to Step 5
3. If the build fails:
   a. Fix the build errors
   b. Run `/simplify` on the fixes (MANDATORY — single-agent tier allowed only per the tiered-ceremony rules)
   c. Run a review round on the fix changes at the scope the delta-round rules require (Opus 4.8 in background + `/codex-chunk` for code fixes); iterate until the required lanes are clean (fix → `/simplify` → round)
   d. Rerun `npm run build`
   e. Repeat steps 3a–3d until the build passes
   f. If any build-fix edit could affect behavior covered by more than one phase — including edits to the file that failed to compile — re-run a holistic round (Step 3, scope per the delta-round rules: delta round against the last clean holistic state, or full coverage when the impact boundary is uncertain) before proceeding to Step 5; if that holistic rerun produces further edits, repeat Step 4 (build verification) before completion

---

### Step 5: Completion (MANDATORY)

1. **File-based plan**: Mark all completion criteria checked in `progress.md` or `todo.md`
2. Report to the user:
   - Summary of all phases completed
   - Decisions surfaced via the Step 2a gate (one line each: phase + Q → A) so the user can see which calls were settled with their input vs. punted to Claude under an explicit "just decide" bypass
   - Any warnings that were skipped or ignored (with rationale, noting which lane raised them)
   - Build verification result
   - Total number of `/simplify` iterations and review rounds performed, with per-lane counts (`/codex-chunk` and Opus 4.8) and each round's scope (full vs. delta, with the carried-forward baseline id for delta rounds) — to prove both lanes ran every round, except doc-only tier rounds, which must each cite their tier justification
