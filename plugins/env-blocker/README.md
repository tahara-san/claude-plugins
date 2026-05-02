# env-blocker

PreToolUse hook that blocks Claude from reading, editing, writing, globbing,
or shelling out to `.env` and `.env.*` files.

## What it blocks

- `Read`, `Edit`, `Write`, `MultiEdit` on any path whose basename matches
  `.env`, `.env.*` (e.g. `.env.local`, `.env.production`), or `.env_*`
  (e.g. `.env_local`).
- `NotebookEdit` on the same set of basenames.
- `Glob` patterns whose basename starts with `.env`.
- `Bash` commands that reference `.env`-style filenames as tokens
  (e.g. `cat .env`, `cp .env.local /tmp/`). Source files like `env.ts`,
  `app.env`, `.envrc`, and `.environment` are NOT matched.

## What it allows

These exact basenames pass through unblocked:

- `.env.example`
- `.env.sample`
- `.env_example`
- `.env_sample`

## How it works

`hooks.json` registers a `PreToolUse` matcher for
`Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Bash`. When Claude is about to
call one of those tools, the hook script runs (`block-env-files.sh`, a
Python stdlib script) and returns a JSON `permissionDecision: "deny"` for
matches. Pure stdlib — no external dependencies, no `jq`.

## Install

```bash
/plugin install env-blocker@tahara-claude-plugins
```

## Disable temporarily

```bash
/plugin disable env-blocker@tahara-claude-plugins
```

(re-enable with `/plugin enable env-blocker@tahara-claude-plugins`)
