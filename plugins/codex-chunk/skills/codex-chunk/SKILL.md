---
name: codex-chunk
description: Sends large review prompts to Codex CLI in logical chunks, aggregates results. Use for reviewing plans, diffs, or code changes that may be too large for a single codex exec call.
allowed-tools: Bash(codex *), Bash(git diff *), Bash(git log *), Read, Grep, Glob
---

# Codex Chunk Review

Splits large review prompts into logical chunks, sends each to Codex CLI individually, and aggregates a unified review report. This prevents Codex CLI timeouts (~150s hard cutoff) on large diffs or plans.

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
```

Keep the preamble under ~1,000 characters.

**Two preamble levels:**

- **Scoped (default).** The preamble above, PLUS an explicit scope fence:
  "Review the content below only — do NOT grep or explore the repository
  broadly." Open-ended sweep instructions in every chunk's preamble cause
  Codex to wander the repo and hit the timeout. When cross-repo consumer
  checking is genuinely needed (e.g. "does anything else assume the old
  behavior?"), run ONE dedicated sweep chunk per review with that explicit
  question — never embed sweep language in every chunk.
- **Ultra-lean (retry).** Strips the preamble to the bare task + severity
  taxonomy + output format: no `--context` material, no commits list, no
  convention notes. Used only for timeout retries and sub-chunks (Step 6).

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
| **Empty output** | Attempt adaptive re-chunking (see below). If sub-chunks also fail, mark as FAILED:EMPTY |
| **Non-zero exit** | Record error, mark as FAILED:ERROR, continue |
| **Success** | Store output, continue |

**Adaptive re-chunking on failure:** When a chunk still fails after the lean retry (timeout) or on empty output, split the failed chunk's content into smaller sub-chunks using a reduced limit of **3,500 characters** (roughly half the normal limit). Re-execute each sub-chunk with the **ultra-lean preamble** (updating the chunk numbering to reflect sub-chunks, e.g., "chunk 3a of 5"). If any sub-chunk also fails, mark it as FAILED and continue to the next. Do not recurse further — one level of re-chunking is the maximum.

Never abort the entire review because one chunk failed. Partial results are valuable.

### Step 7: Aggregate & Present Results

After all chunks complete, build and output the final report:

```markdown
# Codex Review Report

## Summary
- **Review type:** {diff|plan|files}
- **Coverage:** {full | DELTA-ONLY since <baseline round id / diff hash> — unchanged files carry the prior clean verdict: <one-line prior-verdict summary>}
- **Chunks:** {completed}/{total} successful
- **Base branch:** {base} (for diff type)

## Findings

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

If there are CRITICAL findings, highlight them prominently at the top.

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
