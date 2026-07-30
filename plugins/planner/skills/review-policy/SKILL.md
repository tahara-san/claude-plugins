---
name: review-policy
description: Internal reference contract — NOT invoked directly by the user. Defines how every planner review gate disposes of reviewer findings: the blocker predicate (what can actually fail a round), the mandatory disposition ledger, non-blocking parking into out-of-scope issues, remedy-scope binding, cross-lane dispute resolution on split verdicts, and the convergence budget. `/plan-doc`, `/plan-code`, and `/plan-issues` load this at their review gates. Do not invoke as a slash command; do not auto-fire it on review-sounding requests.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(git diff *), Bash(date *)
---

# review-policy

The canonical finding-disposition and convergence contract for every review gate in
the `planner` plugin: `/plan-code` (per-phase 2d, holistic Step 3, build-fix rounds),
`/plan-doc` (Step 7 finalization), and `/plan-issues` (via the `/plan-doc` flow it
invokes).

> **This is a reference, not a command.** It is loaded *by* the planner skills at
> their gates. Do not run it standalone, and do not invoke it because a request
> mentions "review".

## Why this exists

The gates used to pass only when neither lane reported "CRITICAL or **worth-addressing**
WARNINGs". That phrase has no floor: any reviewer nit can be read as worth addressing,
so it gets fixed, the fix mutates the reviewed bytes, the mutation stales the approval,
and the gate reruns — forever, without the change-set getting meaningfully safer. A
stronger reviewer will always find one more worthwhile improvement.

The endpoint of a gate is **controlled residual risk with auditable disposition**, not a
literal zero-findings verdict.

Nothing here weakens an existing guarantee. Dual-lane launch, full-vs-delta scoping,
recorded clean baselines, the mandatory `/simplify` step, and the fail-closed rule that
**any required lane's non-PASS blocks the gate** all remain in force.

---

## 1. Two independent axes — never collapse them

### 1a. Lane / process state

| State | Meaning |
|---|---|
| `QUALIFYING` | The lane ran with the required tool/model on the intended scope and emitted a parseable verdict. |
| `BLOCKED_PROCESS` | The lane could not produce a qualifying review. |

Process failures include: the lane never launched, the background subagent result was
never collected, the wrong model ran without the substitution being surfaced, output is
malformed or unparseable, required coverage is missing, the reviewer reviewed files
outside the declared scope, or the `codex` CLI was unavailable/unauthenticated.

**A process failure is never a parked finding.** It stays fail-closed. Do not reclassify
a `BLOCKED_PROCESS` lane as advisory, do not park it, and do not treat the companion
lane's PASS as compensation. Fix the process and rerun that lane.

### 1b. Substantive finding materiality

Every substantive reviewer item gets exactly one materiality label:

`BLOCKING` · `ADVISORY` · `INSIGNIFICANT` · `UNSUPPORTED` · `DUPLICATE` · `OUT_OF_SCOPE`

---

## 2. The blocker predicate

A finding is `BLOCKING` only when **all four** hold:

1. **Grounded** — it cites evidence inside the reviewed scope (a real file, line, or
   contract), not a general impression.
2. **Concrete** — it names a reproducible or logically specific failure mode, not a
   preference or a generalized possibility.
3. **Contract-relevant** — it violates at least one explicit user requirement, an
   acceptance criterion or checklist item in the task docs, a `CLAUDE.md` rule, or a
   required verification guarantee.
4. **Material before the gate closes** — leaving it unresolved can affect at least one of:
   - correctness or executability;
   - security, privacy, authorization, or secret handling;
   - data loss, corruption, durable inconsistency, or financial integrity;
   - concurrency, retry, idempotency, transaction, lifecycle, or ownership safety;
   - a public API/schema/compatibility requirement that is actually in scope;
   - required build/test/static verification;
   - target-environment operability, or rollback/cleanup safety;
   - a missing plan decision that would force the implementer to invent material behavior.

**Severity is the reviewer's opinion; the predicate is the gate.**

- A `[CRITICAL]` label with no grounded evidence and no concrete failure mode is **not**
  a blocker. Adjudicate it (§7), don't reflexively fix it.
- A `[WARNING]` that violates an explicit acceptance criterion **is** a blocker.
- `[INFO]` is never a blocker on its own.

---

## 3. Not blockers by default

Unless a finding independently satisfies §2, label it `ADVISORY`, `INSIGNIFICANT`,
`UNSUPPORTED`, `DUPLICATE`, or `OUT_OF_SCOPE`:

- cosmetic wording, formatting, naming, or style preferences;
- optional readability improvements with no behavioral ambiguity;
- extra test hardening beyond already-adequate acceptance/invariant coverage;
- speculative concerns with no evidenced failure path;
- portability for environments the task does not support;
- broad refactors or abstractions the task does not require;
- evidence/provenance polish that does not affect scope, coverage, or verdict validity;
- unrelated pre-existing defects;
- repeated or reworded versions of an already-dispositioned finding.

**Wording exception.** A documentation or plan-document wording defect stays `BLOCKING`
when it can cause unsafe implementation, an incorrect command, wrong authorization
behavior, data loss, or another material contract failure.

---

## 4. Dispositions

Every substantive reviewer item gets exactly one recorded disposition:

| Disposition | Meaning |
|---|---|
| `remediate-now` | Confirmed blocker. Fix it, rerun affected verification, rerun the affected review scope. |
| `park-follow-up` | Real future work, not blocking this gate. Route to `tasks/out-of-scope-issues/` (§6). |
| `accept-no-action` | No worthwhile follow-up exists. Record rationale + residual risk in the ledger only. |
| `reject-unsupported` | Evidence contradicts the claim or cannot support it. Record why. |
| `duplicate` | Same defect as an already-dispositioned finding. Reference the canonical finding ID. |
| `out-of-scope` | Real but outside the active task's contract. Route through `tasks/out-of-scope-issues/`; do **not** expand the active task. |

### Stable finding identity

Assign a `finding_id` (`F-001`, `F-002`, …) on a finding's **first** appearance and reuse
it across every later round and both lanes. **Rewording does not create a new finding.**
A rephrased repeat is `duplicate` against the canonical ID; it does not increment the
novel-finding count and it does not consume a remediation round. Without this, a reviewer
that rephrases the same nit each round makes convergence impossible.

---

## 5. Remedy-scope binding (the core anti-churn rule)

**The remedy target is bound to the blocking findings.**

A fix batch inside a gate may touch only:

- the code/docs required to close a confirmed `BLOCKING` finding, **plus**
- that fix's coupled artifacts (indexes for query/sort changes, config for behavior
  flags, docs for renamed exports, callers of changed signatures), **plus**
- files semantically affected by the fix.

It may **not** touch anything else. Specifically:

- Do **not** fix an `ADVISORY` finding opportunistically because you happen to be
  editing nearby. That mutates judged bytes, stales the approval, and restarts the loop
  — it is the exact churn this policy exists to stop.
- Do **not** apply unrelated `/simplify` suggestions after a gate has passed. Post-fix
  `/simplify` runs on the blocker fix and its affected scope only.
- Do **not** widen the task's acceptance criteria to absorb a reviewer's suggestion.

Genuine improvements that fail the predicate belong in `tasks/out-of-scope-issues/`
as a future task, never in the current gate's fix batch.

**If no finding is `BLOCKING`, the gate closes with zero judged-byte mutations and zero
lane reruns.** That is a complete, qualifying pass — not a shortcut.

---

## 6. Parking behavior

- **Every** finding gets a ledger entry (§11). The ledger is the audit trail.
- `park-follow-up` and `out-of-scope` **additionally** write an out-of-scope issue file
  per the user-level "Out-of-Scope Issue Tracking (MANDATORY)" rule:
  `tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md`, with **Issue /
  Location / Severity / Context / Suggested Fix** sections in that order. `<priority>` is
  the lowercased `Severity` value (`critical` · `high` · `medium` · `low` · `proposal` ·
  `other`); `<YYYYMMDD>` is today's date at creation time. Use the
  `<priority>/manual/` tier for findings that genuinely need a human in the loop.
  **Dedup first** with a recursive scan across every priority subdir including `manual/`:

  ```bash
  find tasks/out-of-scope-issues -type f -name '*.md'
  ```

  Update the existing file rather than creating a near-duplicate.
- `accept-no-action`, `reject-unsupported`, and `duplicate` create **no** backlog entry.
  This is what keeps advisory noise out of the issue tracker.
- **Do not edit judged task/code bytes solely to record a parking rationale.** The
  ledger lives in the review-evidence plane (§9).

### Authorization boundary

- Parking a finding that objectively fails the predicate needs **no** user approval.
- **Waiving a confirmed blocker, or waiving a required review lane, does** require
  explicit user approval.
- A passing review is never authorization to commit, push, deploy, or mutate data.
  Those stay separate explicit authorizations.

---

## 7. Verdict semantics

| Verdict | Meaning |
|---|---|
| `PASS` | No `BLOCKING` findings. A non-empty advisory list is still a **complete** pass. |
| `CHANGES_REQUIRED` | At least one finding satisfies the predicate. Each listed blocker must carry grounded evidence, a concrete failure mode, the violated contract/invariant, and the required correction. A `CHANGES_REQUIRED` with an empty or structurally incomplete blocker list is malformed — treat it as `BLOCKED_PROCESS`, not as a content verdict. |
| `BLOCKED` | The lane could not complete a qualifying review (process/tool/scope/input failure). **Not** a content-severity label. |

Do **not** invent a `PASS_WITH_FINDINGS` state. `PASS` plus a non-empty advisory list
already expresses that outcome.

### Never override a required lane

An aggregate `PASS` while any required lane's current verdict is `CHANGES_REQUIRED` is
forbidden. **Only the lane itself may change its verdict** — via the cross-lane dispute
cycle (§7a) when the round's verdicts split, or via a bounded same-byte clarification
rerun when they don't. The companion lane's existing `PASS` stays current as long as
the reviewed bytes do not change.

When you judge a lane's blocker non-blocking but there is no passing lane to referee
(both lanes returned `CHANGES_REQUIRED`):

1. Verify the claim against the reviewed evidence.
2. Record a disposition naming precisely which element of the predicate fails.
3. **Do not change judged bytes.**
4. Run **one** bounded same-byte clarification rerun of that lane, citing this policy and
   the source-grounded evidence. Do not negotiate repeatedly inside the stale session.
5. If the lane re-affirms `CHANGES_REQUIRED`, the blocker **stands**: remediate it and
   re-round. Escalation to the user comes from the §10a budget, not from the
   disagreement itself.

A same-byte clarification rerun is not a remediation round (§10).

---

## 7a. Cross-lane dispute resolution (split verdicts)

**Trigger.** A round ends with both lanes `QUALIFYING` and split verdicts: one lane
`PASS`, the other `CHANGES_REQUIRED` with a structurally complete blocker list. **Every
such split runs this cycle** — even when the failing lane's blockers look plainly valid;
the referee's analysis still feeds the fix. The cycle does NOT fire for
`BLOCKED`/`BLOCKED_PROCESS` (fail-closed — fix the process and rerun that lane), for a
both-`CHANGES_REQUIRED` round (normal remediation, §7 above), or for a malformed
`CHANGES_REQUIRED` (already `BLOCKED_PROCESS`, §7).

**Settled findings are excluded from the trigger.** A finding already re-affirmed
through D2 in this gate (matched by canonical `finding_id`) is settled: a later split
whose disputed blockers are ALL settled does not re-enter the cycle — their blocker
status stands; remediate directly. A mixed split (settled + novel blockers) runs the
cycle over the novel blockers only, with the settled ones proceeding straight to
remediation.

**Step D1 — meta-review by the passing lane** (same bytes, no source mutation).
Send the passing lane a dispute dossier: each disputed blocker's `finding_id`, severity,
evidence, failure mode, and violated contract, plus the disputed content (or a pointer
to it) and the §2 blocker predicate. Ask for a per-finding adjudication
`[UPHOLD|OBJECT] F-xxx — rationale` and a closing line `Verdict: UPHOLD | OBJECT` —
`UPHOLD` if it upholds ANY disputed blocker, `OBJECT` only if it objects to every one.

- **Codex as referee:** `/codex-chunk dispute --role meta` — never raw `codex exec`.
- **Fable as referee:** SendMessage to the gate's recorded persistent Fable reviewer;
  if messaging is unavailable, spawn a fresh subagent given the prior-verdict summary
  plus the dossier.

**D1 = `UPHOLD`** → the dispute resolves as a rejection. Treat every upheld finding as a
confirmed blocker: remediate and re-round per the delta-round rules, feeding the
meta-review's rationale into the fix. Findings the referee objected to (while others
were upheld) get a normal orchestrator disposition — an objection is evidence, not an
auto-dismissal.

**D1 = `OBJECT` (every disputed finding)** → Step D2.

**Step D2 — reconsideration by the failing lane** (same bytes). Send the failing lane
the meta-review's per-finding objections and ask it to re-review the unchanged content,
either withdrawing or re-affirming each blocker, closing with a final
`Verdict: PASS | CHANGES_REQUIRED`.

- **Codex reconsidering:** `/codex-chunk dispute --role reconsider`.
- **Fable reconsidering:** SendMessage to the same persistent reviewer.

- **`PASS`** → both lanes now hold `PASS` on the same bytes. Disposition the withdrawn
  findings `reject-unsupported` (rationale: withdrawn after cross-lane dispute) and
  close the gate if nothing else blocks.
- **`CHANGES_REQUIRED` (re-affirmed)** → only the **re-affirmed** blockers stand:
  remediate them and re-round. Blockers withdrawn in the same response are dispositioned
  `reject-unsupported` (withdrawn after cross-lane dispute) and do NOT enter the fix
  batch. Do NOT escalate here — escalation comes only from the §10a budget (or a
  blocker waiver, §6).

**Accounting.** D1 and D2 are same-byte process steps (§10b): they never count as
remediation rounds and never mutate judged bytes. At most ONE dispute cycle per gate
round. A finding re-affirmed through D2 is settled for this gate — a reworded repeat in
a later round is `duplicate` against its canonical ID, never re-disputed. For split
verdicts, D2 subsumes the bounded same-byte clarification rerun (§7) — do not run both.

**Ledger.** Record the cycle in the round ledger (§11): a header line
`Dispute cycle: none | D1 UPHOLD | D1 OBJECT → D2 PASS | D1 OBJECT → D2 re-affirmed`
and, for each disputed finding, the meta-verdict and final verdict in its rationale
column.

---

## 8. Reviewer prompt contract

Every lane's prompt — the `/codex-chunk` preamble and the Claude Code Fable (high
reasoning) Review subagent prompt — MUST state, alongside the
`[SEVERITY] file:line — description` output format:

- Do not turn style, formatting, naming, optional hardening, speculation, or preference
  into blockers.
- A testing gap blocks only when an explicit acceptance criterion or material invariant
  has no adequate verification path.
- Classify findings against the task's declared scope, not an imagined ideal system.
- `PASS` is the correct verdict when only advisories or testing gaps remain.
- Every blocker must carry evidence, a concrete failure mode, and the violated
  contract/invariant.

Advisories are preserved in the review output but must not cause judged-byte mutation or
a lane rerun.

---

## 9. Judged-product plane vs. review-evidence plane

**Judged product** — code, tests, fixtures, migrations, `spec.md`, `todo.md`,
`progress.md`, `todo-phase-N.md`, and any final report that is part of the task
contract. Changing these bytes stales the affected approval and triggers the existing
full/delta rerun policy.

**Review evidence** — disposition ledgers, raw lane outputs, round metadata, and
out-of-scope issue files created solely to park advisories. Writing these does **not**
mutate the reviewed product and MUST NOT trigger another review round. Validate this
plane deterministically instead: referenced files exist, the ledger is complete (one
disposition per finding), no placeholders remain, no secrets leaked.

**Guardrail.** The evidence plane must not be used to smuggle a behavior, command,
acceptance criterion, or contract change around review. Such content is judged product.
If the task's acceptance criteria or completion claim depend on a parked issue's content,
it was judged product all along — classify it that way before the gate closes.

---

## 10. Convergence controls

### 10a. Remediation budget

Default to **at most 4 bundle-mutating remediation rounds per gate** — a round is
bundle-mutating only when it changed judged bytes. Dispute-cycle steps (§7a) and
same-byte clarification reruns never consume this budget (§10b). On reaching the
budget, enter **convergence mode**:

- stop applying optional improvements entirely;
- disable broad unrelated `/simplify` edits;
- deduplicate by stable finding ID;
- review only blocker fixes and their semantically affected scope, under the existing
  delta-round rules;
- require any new late blocker to state its concrete material failure **and** its
  relation to the changed bytes or an explicit task/repository contract;
- automatically park every new low-materiality finding;
- if a material blocker remains, fix it and review it — then, if the gate still cannot
  converge after **one** bounded additional blocker round, **stop and escalate to the
  user** rather than running autonomously. Escalation therefore fires after the **5th**
  bundle-mutating round.

The budget is not auto-approval and never waives a real blocker. **A late CRITICAL
security, data-integrity, or correctness finding still blocks.**

### 10b. Process retries are counted separately

Same-byte clarification reruns (§7), dispute-cycle meta-reviews and reconsiderations
(§7a), and process-failure retries (a lane that crashed, a background result that was
never collected) are **not** bundle-mutating remediation rounds. Default to one fresh
retry per lane per scope and one dispute cycle per gate round; a second failure stops
for explicit user resume/override instead of an autonomous retry loop.

### 10c. Scope freeze after round 1

Round 1 of each gate stays broad (full coverage). Later rounds focus on: closure of prior
blocker IDs, changed bytes, semantically affected neighbors, and newly discovered
material defects. A later reviewer may still report a real material defect outside the
delta — but it must satisfy the predicate. New polish and speculative hardening are
parked.

---

## 11. The round ledger

Each round writes one ledger under the task directory:

```
tasks/<task-name>/reviews/round-<n>/dispositions.md
```

For in-context plans with no task directory, keep the same table inline in the running
report.

```markdown
# Review round <n> — <gate: phase-N | holistic | plan-doc:spec.md | build-fix>

- Coverage: full | delta (baseline: <round id / diff hash>)
- Lanes: codex-chunk = QUALIFYING/PASS · fable = QUALIFYING/PASS
- Judged bytes changed this round: no
- bundle_mutating_remediation_count: 0 / 4
- Convergence mode: off
- Dispute cycle: none

| ID | Lane | Severity | Summary | Materiality | Disposition | Rationale / destination |
|----|------|----------|---------|-------------|-------------|-------------------------|
| F-001 | codex | WARNING | naming in `foo.ts:12` | ADVISORY | accept-no-action | style preference; no contract violated |
| F-002 | fable | WARNING | no retry on `bar()` | ADVISORY | park-follow-up | → tasks/out-of-scope-issues/low/20260727_bar-retry.md |
| F-003 | codex | CRITICAL | unbounded loop in `baz.ts:40` | BLOCKING | remediate-now | predicate ✓✓✓✓ — correctness; fixed in this round |
| F-004 | fable | WARNING | naming in `foo.ts:12` | DUPLICATE | duplicate | → F-001 |
```

Record for each finding, at minimum: `finding_id`, lane, reviewer severity, summary,
materiality, disposition, and the rationale or follow-up destination. Add
`evidence` / `failure_mode` / `contract_or_invariant` / `residual_risk` when the finding
is `BLOCKING` or when the rationale is not self-evident. For a finding that went through
a §7a dispute cycle, the rationale column also records its meta-verdict and final
verdict (e.g. `disputed: meta OBJECT → re-affirmed`).

---

## 12. Migration

- Legacy `tasks/<task-name>/ignored-warnings.md` files remain readable as historical
  evidence. **Do not rewrite them.**
- New runs use `tasks/<task-name>/reviews/round-<n>/dispositions.md` instead of
  accumulating ignored-warnings prose.
- Existing review artifacts stay historical; do not relabel old verdicts.
- A task already in flight adopts this policy at its **next** round.

---

## 13. Worked example

Both lanes return no CRITICALs plus two documentation-accuracy notes.

**Before this policy.** The notes read as "worth addressing", so two task docs get
edited, the approval is staled, both lanes rerun. Round 2 blocks on provenance wording,
round 3 on a stale delta baseline; the gate finally passes on round 5 — four extra rounds
and zero source changes.

**After this policy.** Both notes fail the predicate (not contract-relevant, no material
failure mode). They are recorded as `ADVISORY` with dispositions `accept-no-action` and
`park-follow-up` in `round-1/dispositions.md`, an evidence-plane file. No judged byte
changes, so no approval is staled and no lane reruns. **The gate closes at round 1** with
auditable residual risk.

---

## Pitfalls

- Treating a reviewer's WARNING/INFO list as a mandatory work queue.
- Fixing an advisory "while we're in there" — remedy scope is bound to blockers (§5).
- Converting a `BLOCKED_PROCESS` lane into an advisory, or parking it.
- Declaring an aggregate PASS while a required lane says `CHANGES_REQUIRED`.
- Skipping the §7a dispute cycle on a split verdict — or escalating to the user directly
  on a re-affirmed FAIL instead of remediating and letting the §10a budget escalate.
- Re-disputing a finding the failing lane already re-affirmed through D2.
- Counting D1/D2 dispute steps against the remediation budget.
- Negotiating with a reviewer inside its old session instead of the structured §7a
  dispute cycle (split verdicts) or one bounded same-byte clarification rerun.
- Editing judged bytes just to write down a parking rationale.
- Re-reviewing ledgers or parked issue files as if they were judged product.
- Counting a same-byte clarification or a process retry against the remediation budget.
- Using the budget to suppress a late critical security/data-integrity/correctness
  finding.
- Minting a new finding ID for a reworded repeat, which inflates the novel-finding count
  and prevents convergence.
- Filing every advisory as an out-of-scope issue — only `park-follow-up` and
  `out-of-scope` get a file; `accept-no-action` / `reject-unsupported` / `duplicate` do
  not.
