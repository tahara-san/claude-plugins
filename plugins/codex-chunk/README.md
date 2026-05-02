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

Common options: `--base <branch>`, `--context <text>`.

See [`skills/codex-chunk/SKILL.md`](skills/codex-chunk/SKILL.md) for the
full command surface, chunking rules, and aggregation format.

## Dependencies

- **`codex` CLI** — install via `/plugin install codex@openai-codex`.
  `/codex-chunk` shells out to `codex exec --sandbox read-only ...`.

## Install

```bash
/plugin install codex-chunk@tahara-claude-plugins
```
