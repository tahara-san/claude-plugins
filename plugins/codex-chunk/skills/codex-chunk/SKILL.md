---
name: codex-chunk
description: Sends large review prompts to Codex CLI in logical chunks, aggregates results into a PASS/CHANGES_REQUIRED/BLOCKED verdict with blocking and advisory findings reported separately. Also handles one direction of a bilateral cross-lane dispute exchange (`dispute` type — meta-review of a peer lane's blockers, or reconsideration of Codex's own against the peer's PASS position). Use for reviewing plans, diffs, or code changes that may be too large for a single codex exec call.
allowed-tools: Bash(codex *), Bash(git diff *), Bash(git log *), Read, Grep, Glob
---

# Codex Chunk Review

Splits large review prompts into logical chunks, sends each to Codex CLI individually, and aggregates a unified review report with a rolled-up `PASS`/`CHANGES_REQUIRED`/`BLOCKED` verdict and blocking findings separated from advisories. This prevents Codex CLI timeouts (~150s hard cutoff) on large diffs or plans.

## Usage

```
/codex-chunk <type> [options]
```

### Review Types

| Type | Description | Source |
|------|-------------|--------|
| `diff` | Git diffs between branches | `git diff <base>...HEAD` |
| `plan` | Plan text or file | Argument text or file path |
| `files` | Specific files by glob | Glob pattern → read each file |
| `dispute` | Cross-lane verdict adjudication (meta-review of a peer lane's blockers, or reconsideration of Codex's own) | Caller-supplied dispute dossier (file or inline) |

### Options

- `--base <branch>` — base branch for diff (default: `main`)
- `--path <file>` — file path for plan review
- `--glob <pattern>` — glob pattern for files review
- `--context <text>` — additional context to include in preamble
- `--role <meta|reconsider>` — REQUIRED for `dispute`: `meta` = Codex previously
  PASSED this content and now adjudicates the peer lane's blocking findings;
  `reconsider` = Codex previously returned CHANGES_REQUIRED and now re-examines
  its own blockers against the peer lane's PASS position
- `--dossier <file>` — dossier file for dispute review (otherwise the dossier is
  provided inline as the argument)

### Dispute reviews

Used by the planner plugin's `review-policy` §7a bilateral cross-lane dispute
exchange when a dual-lane round ends with split verdicts. Both lanes adjudicate
each other's position on the same unchanged bytes, in the same vocabulary, and a
disputed finding is dropped only when both lanes object to it — so this call
answers one direction of that exchange, never the whole resolution.

The dossier is assembled by the caller and must contain: each disputed blocking
finding (`finding_id`, severity, evidence, failure mode, violated contract), the
disputed content itself (or the exact excerpts the findings cite), and — for
`--role reconsider` — the peer lane's PASS position (its verdict plus the
rationale and any advisory notes covering the disputed material). The content
under review is UNCHANGED since Codex's prior verdict; a dispute call must never
review new bytes.

### Delta reviews

The caller may declare the review a **delta since a prior clean review**
(e.g. a `/plan-code` delta re-round). In that mode:

- Submit ONLY the changed content plus the caller-supplied prior-verdict
  summary (which files were previously reviewed clean, at what state).
- The preamble must state the delta baseline ("delta since <round id /
  diff hash>; unchanged files carry a prior clean verdict").
- The Step 7 report MUST label its coverage as **delta-only** and restate
  the carried-forward prior verdict — the aggregate must never read as a
  full review of the whole change-set when only changed material was
  reviewed.

## Procedure

Follow these steps precisely. Do NOT skip or reorder.

### Step 1: Pre-flight Checks

Validate inputs based on review type:

- For `diff` type: verify the base branch exists with `git rev-parse --verify <base> 2>/dev/null`.
- For `plan --path`: verify the file exists.
- For `dispute`: verify `--role` is given (`meta` or `reconsider`) and, with `--dossier`, that the file exists. Then verify the dossier actually contains what the role requires: the disputed blocking findings AND the disputed content (or its cited excerpts) for both roles, plus the peer lane's PASS position (verdict + rationale/notes on the disputed material) for `reconsider`. A dispute call without a role, or with a dossier missing required material, is malformed — report `BLOCKED` without calling codex; never adjudicate over absent evidence.

### Step 2: Gather Content

**For `diff` type:**

1. Get the diff:
   ```bash
   git diff <base>...HEAD
   ```
2. Get commit context:
   ```bash
   git log --oneline <base>...HEAD
   ```
3. Get changed file list:
   ```bash
   git diff --name-only <base>...HEAD
   ```

**For `plan` type:**

1. If `--path <file>` is given, read the file with the Read tool.
2. Otherwise, the user provides the plan text inline as the argument.

**For `files` type:**

1. Use the Glob tool with the provided pattern to find files.
2. Read each matched file with the Read tool.

**For `dispute` type:**

1. If `--dossier <file>` is given, read the file with the Read tool; otherwise use the inline dossier text.
2. Dossiers are small by design, so dispute calls almost always run in Single Call Mode (Step 3 threshold applies as usual). If a dossier does exceed the threshold, chunk it by disputed finding — each finding plus its cited excerpts (and the peer's PASS position, for `reconsider`) is one unit; never split a single finding across chunks.

### Step 3: Decide — Single Call vs Chunking

Measure the total content size. **Threshold: 7,000 characters (~3,000 tokens).**

- **Below threshold:** Skip to Step 5 (Single Call Mode). Send the entire content in one codex call.
- **Above threshold:** Continue to Step 4 (Chunking).

### Step 4: Chunk the Content

**Split axis:**

- `diff`: Split by file. Each file's diff is one unit.
- `plan`: Split by top-level heading (`## `). Each section is one unit.
- `files`: Each file is one unit.
- `dispute`: Split by disputed finding. Each finding plus its cited excerpts (and the peer's PASS position, for `reconsider`) is one unit.

**Bin-packing rules:**

1. Start with the first unit. Accumulate adjacent units into a chunk.
2. If adding the next unit would exceed 6,000 characters, close the current chunk and start a new one.
3. For diffs: prefer grouping files in the same directory together.
4. If a single unit exceeds 6,000 characters, send it as its own chunk (never split a single file mid-content).

**Cap:** Maximum 10 chunks. If you end up with more than 10, increase the chunk size limit proportionally until chunks are <= 10.

### Step 5: Build the Preamble

Every chunk (and single-call mode) gets a preamble prepended. Build it dynamically using project conventions already available in your conversation context:

```
REVIEW SCOPE: {N total files} files changed. {This is chunk M of T | This is the complete review.}

COMMITS:
{git log --oneline output or user-provided context}

TASK: Review the following code/plan for correctness, bugs, security issues, and adherence to project conventions. Tag each finding with a severity:
- CRITICAL: Bugs, security vulnerabilities, data loss risks
- WARNING: Code smells, convention violations, potential issues
- INFO: Suggestions, minor improvements, style notes

Format each finding as:
[SEVERITY] file:line — description

BLOCKING vs ADVISORY. Do not turn style, formatting, naming, optional
hardening, speculation, or preference into blockers. A testing gap blocks
only when an explicit acceptance criterion or material invariant has no
adequate verification path. Classify against the declared scope above, not
an imagined ideal system. Every blocker must carry evidence, a concrete
failure mode, and the violated contract or invariant.

End with exactly one line:
Verdict: PASS | CHANGES_REQUIRED | BLOCKED
PASS is correct when only advisories remain. Use CHANGES_REQUIRED only for
findings that meet the blocker bar above. Use BLOCKED only if you could not
review the content at all.
```

Keep the preamble under ~1,400 characters.

**Two preamble levels:**

- **Scoped (default).** The preamble above, PLUS an explicit scope fence:
  "Review the content below only — do NOT grep or explore the repository
  broadly." Open-ended sweep instructions in every chunk's preamble cause
  Codex to wander the repo and hit the timeout. When cross-repo consumer
  checking is genuinely needed (e.g. "does anything else assume the old
  behavior?"), run ONE dedicated sweep chunk per review with that explicit
  question — never embed sweep language in every chunk.
- **Ultra-lean (retry).** Strips the preamble to the bare task + severity
  taxonomy + output format + the BLOCKING-vs-ADVISORY paragraph and the
  verdict line: no `--context` material, no commits list, no convention
  notes. The blocking bar and the verdict line are NOT optional trimming —
  a chunk reviewed without them returns findings the caller cannot
  disposition. Used only for timeout retries and sub-chunks (Step 6).

**Dispute preambles.** The `dispute` type replaces the review preamble above with
one of the two templates below (still ≤ ~1,400 characters, still ending in a
`Verdict:` line so error handling and transcript recovery work unchanged). Both
carry the scope fence: "Adjudicate the dossier below only — do NOT grep or
explore the repository."

*`--role meta`:*

```
DISPUTE META-REVIEW. You are one of two independent review lanes. You reviewed
the content excerpted below and returned PASS. The peer lane returned
CHANGES_REQUIRED with the blocking findings in the dossier. Adjudicate each
finding on its merits — do not defend your prior verdict.

A finding qualifies as a blocker only if it is grounded (cites real evidence in
the reviewed content), concrete (a reproducible or logically specific failure
mode), contract-relevant (violates an explicit requirement, acceptance
criterion, or repository rule), and material (correctness, security, data
integrity, concurrency, API compatibility, required verification, or
operability). Style, naming, optional hardening, speculation, and preference do
not qualify.

For each finding output exactly one line:
[UPHOLD|OBJECT] F-xxx — rationale (evidence-based, one or two sentences)

End with exactly one line:
Verdict: UPHOLD | OBJECT | BLOCKED
UPHOLD if you uphold ANY finding as a genuine blocker. OBJECT only if you
object to every finding. BLOCKED only if you could not adjudicate the
dossier at all.
```

*`--role reconsider`:*

```
DISPUTE RECONSIDERATION. You are one of two independent review lanes. You
reviewed the content excerpted below and returned CHANGES_REQUIRED with the
blocking findings in the dossier. The peer lane reviewed the same content and
returned PASS — its verdict, rationale, and notes on the disputed material are
in the dossier. The content is UNCHANGED since your review. Judge whether the
peer's pass direction holds on your own findings; do not defend your prior
verdict.

Re-examine each of your blockers against the peer's position and the blocker
bar: grounded (cites real evidence in the reviewed content), concrete (a
reproducible or logically specific failure mode), contract-relevant (violates an
explicit requirement, acceptance criterion, or repository rule), and material
(correctness, security, data integrity, concurrency, API compatibility, required
verification, or operability). Style, naming, optional hardening, speculation,
and preference do not qualify. Upholding a finding must answer the peer's
position with evidence, a concrete failure mode, and the violated contract or
invariant, not restate the original claim.

For each finding output exactly one line:
[UPHOLD|OBJECT] F-xxx — rationale (evidence-based, one or two sentences)
UPHOLD re-affirms your blocker; OBJECT withdraws it.

End with exactly one line:
Verdict: UPHOLD | OBJECT | BLOCKED
UPHOLD if you re-affirm ANY of your findings as a genuine blocker. OBJECT only
if you withdraw every one. BLOCKED only if you could not adjudicate the dossier
at all.
```

### Step 6: Execute Codex Calls

**Single Call Mode** (content below threshold):

```bash
codex exec --sandbox read-only --skip-git-repo-check - 2>/dev/null <<'CHUNK_EOF'
{preamble}

{full content}
CHUNK_EOF
```

**Chunked Mode:**

Execute chunks **sequentially** (not in parallel — avoids rate limits, enables progress reporting).

For each chunk (M of T):

1. Report progress to the user: `Reviewing chunk M of T...`
2. Run:
   ```bash
   codex exec --sandbox read-only --skip-git-repo-check - 2>/dev/null <<'CHUNK_EOF'
   {preamble with chunk M of T}

   {chunk content}
   CHUNK_EOF
   ```
   Use a **5-minute Bash timeout** (300000ms) per chunk.
3. Capture the output.

**Important flags — always use:**
- `--sandbox read-only` — review only, no writes
- `--skip-git-repo-check` — avoid git repo validation overhead
- `2>/dev/null` — suppress stderr thinking tokens
- `-` (stdin) — read prompt from heredoc to avoid shell escaping issues

**Never use:**
- `-m` flag — model is controlled by the user's `~/.codex/config.toml`
- `--full-auto` — this is a read-only review

**Error handling — adaptive re-chunking:**

For each chunk execution:

| Situation | Action |
|-----------|--------|
| **Timeout** (5min exceeded) | Retry the SAME chunk once with the **ultra-lean preamble** (Step 5) — timeouts are usually caused by preamble-induced repo exploration, not content size. If the lean retry also times out, attempt adaptive re-chunking (see below). If sub-chunks also fail, mark as FAILED:TIMEOUT |
| **Swallowed by a Codex Stop hook** (no `Verdict:` line + a logging/issue-file note) | Attempt transcript recovery (below). **If recovery succeeds**, do NOT retry, do NOT re-chunk, do NOT count as FAILED — the model already did the work and retrying burns a full call to reproduce the same swallow. **If recovery does not return a verdict-bearing message for this chunk's own session, the swallow diagnosis is unconfirmed** — the chunk is unreviewed. Attempt adaptive re-chunking (below); if that also yields no verdict, mark as FAILED:NO_VERDICT. Never let an unrecovered no-verdict output fall into the Success row. |
| **Empty output** | First apply the transcript-recovery check below — a swallowed response can also present as near-empty stdout. Only if recovery finds no verdict-bearing message, attempt adaptive re-chunking (see below). If sub-chunks also fail, mark as FAILED:EMPTY |
| **Non-zero exit** | Record error, mark as FAILED:ERROR, continue |
| **Success** (non-empty output containing a `Verdict:` line) | Store output, continue |

A zero-exit, non-empty output with **no `Verdict:` line** is NOT a success — it is the
swallowed-response candidate above. Match the rows in order and only classify a chunk as
`Success` once you have a verdict, whether returned directly or recovered.

**Adaptive re-chunking on failure:** When a chunk still fails after the lean retry (timeout), on empty output, or on an unrecovered no-verdict output, split the failed chunk's content into smaller sub-chunks using a reduced limit of **3,500 characters** (roughly half the normal limit). Re-execute each sub-chunk with the **ultra-lean preamble** (updating the chunk numbering to reflect sub-chunks, e.g., "chunk 3a of 5"). If any sub-chunk also fails, mark it as FAILED and continue to the next. Do not recurse further — one level of re-chunking is the maximum.

Never abort the entire review because one chunk failed. Partial results are valuable.

**Recovering a swallowed response**

A Codex-side `Stop` hook may block Codex's final message when it contains ordinary
review vocabulary (`pre-existing`, `out-of-scope`, `follow-up`, `no-op`, `skipped`,
`code smell`), demanding the finding be written to
`tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<slug>.md`. Codex complies, and the
continuation's closing line (e.g. `Logged the ... at [20260729_foo.md](...)`) becomes
the **last** assistant message. `codex exec` prints only the last message, so the real
review is discarded before it reaches stdout — but it still exists in the transcript.

The hook fires on the *response*, not the prompt, so sanitizing prompts does not
prevent it. Do NOT add prompt-level instructions telling Codex to avoid the trigger
words: that was tested and failed — a fully abstracted prompt containing none of the
words still tripped the hook, because the model's own answer used "follow-up".

**Detector:** a chunk's output that contains **no `Verdict:` line** but does reference
`tasks/out-of-scope-issues` (or is a short note about logging/recording an issue) is a
**candidate swallowed response** — not yet an empty or failed one. Observed variants
include both a file link (`Logged the ... at [20260729_foo.md](...)`) and a bare
completeness note (`Completeness check: no out-of-scope issue was logged. ...`) — the
absent `Verdict:` line is the trigger to *investigate*, not the specific phrasing. The
candidate only becomes a confirmed swallow when transcript recovery below returns this
chunk's own verdict-bearing message; until then it is still a potential failure.

Transcripts live at `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ISO8601>-<uuid>.jsonl`,
one JSON object per line. Assistant turns are lines where `payload.role == "assistant"`,
with `payload.content` an array of `{type, text}` objects. Two shape details matter:

- **A `codex exec` often writes TWO session files with near-identical timestamps.** One
  is the real session; the other is the `approvals_reviewer = "auto_review"` sidecar,
  which contains only a short `{"outcome":"allow"}` assistant message. Pick the session
  whose `user` message matches the prompt that was sent; ignore the sidecar. The sidecar
  is not always written (a call needing no approval review produces a single file), so
  never assume the newest file is the sidecar — match on the prompt.
- The forced continuation is visible as a `user` message containing
  `<hook_prompt hook_run_id="stop:...">`. Its presence confirms the diagnosis. When
  grepping the raw `.jsonl` for it, remember the quotes are JSON-escaped
  (`hook_run_id=\"stop:`) — match `hook_prompt` alone, or parse the line as JSON.

Recover the **last** assistant message containing a `Verdict:` line (or, for a
non-review call, the last one matching the requested output format) — NOT the final
assistant message, which is the logging note.

**You MUST identify the session by matching the prompt you sent.** Never just take the
newest verdict-bearing transcript: chunks run sequentially into the same session
directory, so the newest verdict may belong to the *previous* chunk. Attributing it to
this chunk would silently swap one chunk's verdict for another's. Set `CHUNK_MARKER` to
a string that appears in the prompt you just sent and is unique to it (e.g. a distinctive
file path or code line from the chunk content — not the generic preamble):

```bash
export CHUNK_MARKER='<a distinctive line from the chunk you just sent>'

python3 - <<'PY'
import json, glob, os
marker = os.environ["CHUNK_MARKER"]
files = sorted(glob.glob(os.path.expanduser(
    "~/.codex/sessions/*/*/*/rollout-*.jsonl")), key=os.path.getmtime, reverse=True)[:12]
for path in files:
    users, hooked, best = [], False, None
    for line in open(path):
        try: d = json.loads(line)
        except ValueError: continue
        pl = d.get("payload") or {}
        c = pl.get("content")
        if not isinstance(c, list): continue
        text = " ".join(x.get("text", "") for x in c if isinstance(x, dict))
        if pl.get("role") == "user":
            users.append(text)
            if "hook_prompt" in text: hooked = True
        elif pl.get("role") == "assistant" and "Verdict:" in text:
            best = text
    if not any(marker in u for u in users):
        continue                      # not this chunk's session
    if best is None:
        continue                      # matched, but holds no verdict — almost always the
                                      # approvals sidecar, which embeds your prompt verbatim.
                                      # Keep scanning; do NOT stop here.
    print("MATCHED SESSION:", os.path.basename(path))
    print("stop-hook continuation present:", hooked)
    print("-" * 40)
    print(best if best else "NO VERDICT-BEARING MESSAGE")
    break
else:
    print("NO SESSION MATCHED MARKER")
PY
```

The approvals sidecar **also matches your marker** — it receives your prompt verbatim as
untrusted evidence — so marker matching alone does not exclude it. What distinguishes the
sidecar is that it holds no verdict-bearing assistant message (its only assistant output
is `{"outcome":"allow"}`). That is why the loop above skips a matched session with no
verdict and keeps scanning, rather than stopping at the first match. If the call was not a
verdict-bearing review, swap the `"Verdict:" in text` test for a marker from the
requested output format.

A recovered response is **as authoritative as a directly returned one** — it is the
model's actual output, not a reconstruction. The aggregated report must NOT mark such a
chunk as degraded, failed, or partial; it counts as a normal successful chunk whose
findings and verdict carry full weight.

**The recovery must be positively confirmed, never assumed.** Suppressing retry/re-chunk
is only justified when the script matched *this chunk's* session by marker AND returned a
verdict-bearing message. A no-match, or a match with `NO VERDICT-BEARING MESSAGE`, means
you have not recovered anything — treat the chunk by its observed symptom and let the
normal failure path run. `stop-hook continuation present: True` corroborates the
diagnosis; treat `False` with a successful marker+verdict match as still recoverable
(the swallow can occur without a recorded continuation), but never invent a recovery
from a session you could not match.

**Preventive (conditional, best-effort):** the Codex-side planner hook has no opt-out
today. *If* it ever grows one, read-only advisory calls should be invoked as:

```bash
PLANNER_OOS_GUARD=off codex exec --sandbox read-only --skip-git-repo-check - <<'EOF'
...
EOF
```

This env var does not exist yet — it is a proposed fix in the `codex-plugins` repo.
Transcript recovery above remains the primary mechanism and must never depend on it.

### Step 7: Aggregate & Present Results

After all chunks complete, build and output the final report:

```markdown
# Codex Review Report

## Summary
- **Verdict:** {PASS | CHANGES_REQUIRED | BLOCKED}
- **Review type:** {diff|plan|files}
- **Coverage:** {full | DELTA-ONLY since <baseline round id / diff hash> — unchanged files carry the prior clean verdict: <one-line prior-verdict summary>}
- **Chunks:** {completed}/{total} successful
- **Recovered chunks:** {N of M chunks whose response was swallowed by a Codex Stop hook and recovered from transcript, or "None"}
- **Base branch:** {base} (for diff type)

## Blocking findings
{findings the chunk verdicts marked as meeting the blocker bar — each with its
evidence, concrete failure mode, and the violated contract/invariant — or
"None." Keep the original `[SEVERITY] file:line — description` line for each.}

## Non-blocking findings (advisory)
{everything else, grouped by severity. These are for the caller to disposition
and park — they are NOT a work queue.}

### CRITICAL
{deduplicated CRITICAL findings across all chunks, or "None found."}

### WARNING
{deduplicated WARNING findings across all chunks, or "None found."}

### INFO
{deduplicated INFO findings across all chunks, or "None found."}

## Failed Chunks
{list of failed chunks with reason, or "None — all chunks reviewed successfully."}

## Per-Chunk Details
<details>
<summary>Chunk 1 of N: {files or section names}</summary>

{raw codex output for this chunk}
</details>

{repeat for each chunk}
```

**Deduplication:** If the same file + same issue appears in multiple chunk outputs, keep only the most detailed version.

**Recovered chunks:** a chunk recovered from a transcript (Step 6) counts as **successful**
in the `{completed}/{total}` tally and its findings carry full weight — but it MUST still be
counted on the `Recovered chunks` line. Recovering silently would hide a real environment
problem: the user needs to know the Codex-side Stop hook is still mangling output, since
every affected call costs a wasted round-trip and any review not covered by this skill is
losing its verdict outright.

**Aggregate verdict:** `BLOCKED` if any chunk returned `BLOCKED` or failed in a
way that leaves scope unreviewed; otherwise `CHANGES_REQUIRED` if any chunk
returned `CHANGES_REQUIRED`; otherwise `PASS`. A `PASS` with a non-empty
advisory list is a complete pass — do not soften it to "passed with issues",
and do not invent a `PASS_WITH_FINDINGS` state.

**Dispute reports** replace the Blocking/Advisory sections with the per-finding
adjudication lines (`[UPHOLD|OBJECT] F-xxx — rationale`), and the Summary
verdict line carries the dispute verdict `UPHOLD | OBJECT | BLOCKED` — the same
vocabulary for both roles, since both directions of the exchange answer the same
question about the same findings. Aggregate a chunked dispute conservatively:
`UPHOLD` if any chunk upheld any finding, `OBJECT` only if every chunk objected
to every finding. A dispute chunk that failed or returned no verdict leaves its
findings UNADJUDICATED — report them as such and roll up to `BLOCKED`; never
default a missing adjudication to `OBJECT`. `BLOCKED` is a process outcome, not
an adjudication: the caller (`review-policy` §7a) treats it as a failed
direction of the exchange under its process-retry rules (§10b) — fail-closed,
so the disputed blockers stand — and maps content verdicts back onto the gate,
where a finding is dropped only when BOTH lanes objected to it.

A finding belongs in **Blocking findings** only if the reviewing chunk backed it
with evidence, a concrete failure mode, and a violated contract or invariant. A
`[CRITICAL]` label alone does not qualify it; put an unsupported CRITICAL under
advisory and say why. The caller applies its own blocker predicate on top of
this — the split here is a starting point, not the final adjudication.

If there are blocking findings, highlight them prominently at the top.

## Examples

**Review current branch diff against main:**
```
/codex-chunk diff
```

**Review diff against a specific base branch:**
```
/codex-chunk diff --base develop
```

**Review a plan file:**
```
/codex-chunk plan --path ./PLAN.md
```

**Review specific files:**
```
/codex-chunk files --glob "src/handlers/**/*.ts"
```

**Review with additional context:**
```
/codex-chunk diff --context "Focus on error handling changes"
```

**Adjudicate a peer lane's blockers (Codex previously passed this content):**
```
/codex-chunk dispute --role meta --dossier tasks/my-task/reviews/round-2/dispute-dossier.md
```

**Reconsider Codex's own blockers against the peer lane's PASS position:**
```
/codex-chunk dispute --role reconsider --dossier tasks/my-task/reviews/round-2/dispute-dossier.md
```
