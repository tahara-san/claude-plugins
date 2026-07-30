# planner

Plan-driven workflow plugin. Bundles six skills and one Stop hook.

## Skills

| Skill | Purpose |
|-------|---------|
| `/plan-doc` | Writes a `spec.md` + `todo.md` (or phase-split `progress.md` + `todo-phase-N.md`) for a task. Surfaces open architectural decisions and manual-handling needs to the user via a mandatory ask gate before drafting. Document-only — no code is written. Finalizes drafts through a parallel review round: `/codex-chunk` + a Claude Code Fable (high reasoning) Review (background `general-purpose` subagent on `model: "fable"`); both lanes must run, and the gate passes unless a lane produces a blocking finding. |
| `/plan-code` | Implements a plan phase-by-phase with mandatory `/simplify` → parallel review rounds per phase (`/codex-chunk` + Claude Code Fable (high reasoning) Review run concurrently — a background subagent, `code-reviewer` type for code if available else `general-purpose`; both lanes must run), a holistic review across all phases, and `npm run build` verification. Re-rounds after fixes run at delta scope: unchanged already-clean content carries its verdict forward, and only changed/semantically-affected files plus a delta-interactions chunk are re-reviewed. |
| `review-policy` | Internal reference contract — not user-invoked. Defines what actually fails a review gate: the four-part blocker predicate, the disposition ledger, remedy-scope binding, and the convergence budget. Loaded by `/plan-doc`, `/plan-code`, and `/plan-issues` at their gates. See [Review gates](#review-gates). |
| `/plan-clean` | Scans `tasks/` for completed task directories and resolved out-of-scope issue articles. Classifies each as complete / incomplete / ambiguous and removes only the complete ones after explicit confirmation. |
| `/plan-issues` | Scans `tasks/out-of-scope-issues/` (priority-bucketed, legacy flat, or single-file layout), groups issues, batch-asks the user about each group's open decisions and manual-handling needs upfront, then routes each group through `/plan-doc` to produce task plans. |
| `/plan-commit` | Session wrap-up: removes the task directory implemented in the SAME session (and the issue files it resolved), then stages everything, commits once, and pushes to the current branch (or `/plan-commit <target-branch>` to switch/create and commit there). Fully automatic — no confirmation gate — but verifies the task is complete first and blocks (deleting nothing) if unchecked items remain. |

`plan-doc`, `plan-code`, and `plan-issues` start with a **Preflight** block
that verifies their dependencies (`/simplify`, `/codex-chunk`, `/plan-doc`,
`review-policy`) are loaded. They fail fast with an install hint if a
dependency is missing and explicitly forbid substituting other skills/agents.

## Review gates

Review rounds are dual-lane and parallel, but a round **passes unless a lane
produces a blocking finding**. `review-policy` is the single source of truth
for what that means:

- **Blocker predicate.** A finding blocks only when it is *grounded, concrete,
  contract-relevant, and material*. Severity is the reviewer's opinion; the
  predicate is the gate. A `[CRITICAL]` with no evidence and no concrete
  failure mode is not a blocker; a `[WARNING]` that violates an explicit
  acceptance criterion is.
- **Advisory-only output closes the gate.** No source mutation, no rerun.
  That is a full pass, not a shortcut.
- **Remedy scope is bound to the blockers.** A fix batch may touch only what
  closes a confirmed blocking finding plus its coupled artifacts and
  semantically affected neighbors — fixing advisories "while we're in there"
  is what stales the approval and restarts the loop.
- **Everything gets a disposition.** Each finding lands in
  `tasks/<task>/reviews/round-<n>/dispositions.md`. Items dispositioned
  `park-follow-up` or `out-of-scope` additionally become
  `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md` files —
  where `/plan-issues` later picks them up. `accept-no-action`,
  `reject-unsupported`, and `duplicate` leave no backlog entry.
- **Split verdicts get a cross-lane dispute cycle.** When one lane passes and
  the other returns `CHANGES_REQUIRED`, the passing lane meta-reviews the
  disputed blockers (UPHOLD/OBJECT per finding); if it objects to every one,
  the failing lane reconsiders on the same bytes. A final PASS closes the
  dispute; a re-affirmed FAIL stands and is remediated — user escalation comes
  only from the convergence budget, never from the disagreement itself.
- **Convergence budget.** At most 4 judged-byte-mutating remediation rounds
  per gate, then convergence mode, then escalation to the user after one more
  bounded round (the 5th). Dispute steps and clarification reruns don't count.
  A late critical security/data-integrity/correctness finding still blocks.
- **Process failures stay fail-closed.** A lane that never ran, was never
  collected, or emitted unparseable output is `BLOCKED_PROCESS` — never
  downgraded to advisory, never compensated by the other lane's PASS.

Legacy `tasks/<task>/ignored-warnings.md` files remain readable; new runs
write the round ledger instead.

## Hook

| Event | What it does |
|-------|--------------|
| `Stop` | When the assistant's last turn mentions issue-like keywords ("pre-existing", "out-of-scope", "follow-up", "skipped", "code smell") AND no file was written under `tasks/out-of-scope-issues/`, the hook soft-blocks the Stop and re-prompts the agent to log the issues. |

The hook enforces the user-level "Out-of-Scope Issue Tracking (MANDATORY)"
rule — it expects each finding to land in
`tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md`. See your
global `CLAUDE.md` for the full rule.

## Dependencies

Required at runtime (not bundled):

- **`/simplify`** — built into Claude Code itself (>= 2.x). Always present.
- **`/codex-chunk`** — install separately:
  `/plugin install codex-chunk@tahara-claude-plugins`
- **`codex` CLI** — required transitively by `/codex-chunk`. Install via the
  `codex@openai-codex` plugin.
- **Claude Code Fable (high reasoning) Review** — no install needed: the
  second review lane uses Claude Code's built-in Agent tool (background
  subagent, `model: "fable"`, prompted for high-reasoning thoroughness;
  falls back to `model: "opus"` (the latest Opus model, prompted for
  xhigh-reasoning thoroughness) if `"fable"` is unavailable — the skills
  must tell the user about the substitution, never fall back silently).

## Install

```bash
/plugin install planner@tahara-claude-plugins
```
