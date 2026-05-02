# tahara-claude-plugins

Personal Claude Code plugin marketplace. Three plugins:

| Plugin | What it does |
|--------|--------------|
| [`planner`](plugins/planner) | Plan-driven workflow: `/plan-doc`, `/plan-code`, `/plan-clean`, `/plan-issues`. Plus a Stop hook that enforces logging out-of-scope issues to `tasks/out-of-scope-issues/`. |
| [`env-blocker`](plugins/env-blocker) | PreToolUse hook that blocks Read/Edit/Write/Glob/Bash access to `.env` and `.env.*` files (allows `.env.example` / `.env.sample`). |
| [`codex-chunk`](plugins/codex-chunk) | `/codex-chunk` skill — chunks large review prompts and feeds them to Codex CLI sequentially. Avoids the ~150s `codex exec` timeout on big diffs/plans. |

## Install

```bash
# Add this marketplace once
/plugin marketplace add tahara-san/claude-plugins

# Install the plugins you want
/plugin install planner@tahara-claude-plugins
/plugin install env-blocker@tahara-claude-plugins
/plugin install codex-chunk@tahara-claude-plugins
```

## Recommended companions (install separately)

These are **not** in this marketplace, but the planner workflow assumes them:

- **`/simplify`** — built into Claude Code itself (>= 2.x). No install step;
  appears automatically in your available-skills list.
- **`@playwright/cli`** — Microsoft's CLI + skill bundle for browser
  automation. Install via npm, then let it install its skill into Claude:

  ```bash
  npm install -g @playwright/cli@latest
  playwright-cli install --skills
  ```

- **`codex@openai-codex`** — OpenAI's Codex CLI integration. Required by the
  `codex-chunk` skill (which shells out to `codex exec`). Install with:

  ```bash
  /plugin marketplace add openai/codex-plugin-cc
  /plugin install codex@openai-codex
  ```

## Plugin composition

```
planner          ─┬──► /plan-doc       ─► /codex-chunk
                  ├──► /plan-code      ─► /codex-chunk + /simplify (Claude Code built-in)
                  ├──► /plan-clean     (standalone)
                  ├──► /plan-issues    ─► /plan-doc
                  └──► Stop hook: out-of-scope-issues reminder

env-blocker     ──── PreToolUse hook on Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Bash

codex-chunk     ─── /codex-chunk skill (depends on `codex` CLI from the codex@openai-codex plugin)
```

The planner skills (`plan-doc`, `plan-code`, `plan-issues`) have a
**Preflight** check at the top of their `SKILL.md` that fails fast if a
required dependency isn't loaded — preventing Claude from silently
substituting other skills.

## Updating

```bash
# Pull the latest version of all plugins from this marketplace
/plugin marketplace update tahara-claude-plugins
```

## License

MIT
