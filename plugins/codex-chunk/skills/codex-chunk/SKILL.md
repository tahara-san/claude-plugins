---
name: codex-chunk
description: Sends large review prompts to Codex CLI in logical chunks, aggregates results into a PASS/CHANGES_REQUIRED/BLOCKED verdict with blocking and advisory findings reported separately. Use for reviewing plans, diffs, or code changes that may be too large for a single codex exec call.
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

### Options

- `--base <branch>` — base branch for diff (default: `main`)
- `--path <file>` — file path for plan review
- `--glob <pattern>` — glob pattern for files review
- `--context <text>` — additional context to include in preamble

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

### Step 3: Decide — Single Call vs Chunking

Measure the total content size. **Threshold: 7,000 characters (~3,000 tokens).**

- **Below threshold:** Skip to Step 5 (Single Call Mode). Send the entire content in one codex call.
- **Above threshold:** Continue to Step 4 (Chunking).

### Step 4: Chunk the Content

**Split axis:**

- `diff`: Split by file. Each file's diff is one unit.
- `plan`: Split by top-level heading (`## `). Each section is one unit.
- `files`: Each file is one unit.

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
