# codex-chunk

`/codex-chunk` skill — sends large review prompts to Codex CLI in logical
chunks and aggregates the results into a single report. Designed to avoid
the ~150s hard timeout on `codex exec` for large diffs / plans / file sets.

## Usage

```
/codex-chunk <type> [options]
```

| Type | Source |
|------|--------|
| `diff` | `git diff <base>...HEAD` |
| `plan` | inline plan text or `--path <file>` |
| `files` | `--glob <pattern>` |
| `dispute` | inline dossier or `--dossier <file>`, with `--role <meta\|reconsider>` |

Common options: `--base <branch>`, `--context <text>`.

The `dispute` type answers one direction of the planner plugin's bilateral
cross-lane dispute exchange on split review verdicts: `--role meta` has Codex
adjudicate a peer lane's blocking findings on content Codex previously passed;
`--role reconsider` has Codex re-examine its own blockers against the peer
lane's PASS position on unchanged content. Both roles report
`[UPHOLD|OBJECT] F-xxx` per finding and close with `Verdict: UPHOLD | OBJECT |
BLOCKED`, so the caller can apply its rule that a finding falls only when both
lanes object to it.

## Verdict

Every chunk prompt carries an explicit blocking bar — style, formatting,
naming, optional hardening, speculation, and preference are **not** blockers,
and a blocker must carry evidence, a concrete failure mode, and the violated
contract. Each chunk closes with `Verdict: PASS | CHANGES_REQUIRED | BLOCKED`,
and the aggregated report leads with the rolled-up verdict plus separate
**Blocking** and **Non-blocking (advisory)** sections. `PASS` with a non-empty
advisory list is a complete pass — the advisory list is for the caller to
disposition, not a work queue.

## Swallowed-response recovery

A Codex-side `Stop` hook can block Codex's final message when it uses ordinary
review vocabulary ("pre-existing", "out-of-scope", "follow-up", …), forcing a
continuation whose closing line is a logging note. Because `codex exec` prints
only the last message, the real review never reaches stdout. `/codex-chunk`
detects this (no `Verdict:` line + a logging note), recovers the genuine
response from the session transcript under `~/.codex/sessions/`, and reports a
**Recovered chunks** count so the underlying environment problem stays visible.
Recovered output is the model's actual answer, so it is treated as fully
authoritative — never retried, re-chunked, or marked degraded.

See [`skills/codex-chunk/SKILL.md`](skills/codex-chunk/SKILL.md) for the
full command surface, chunking rules, and aggregation format.

## Dependencies

- **`codex` CLI** — install via `/plugin install codex@openai-codex`.
  `/codex-chunk` shells out to `codex exec --sandbox read-only ...`.

## Install

```bash
/plugin install codex-chunk@tahara-claude-plugins
```
