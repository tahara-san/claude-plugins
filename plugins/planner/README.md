# planner

Plan-driven workflow plugin. Bundles four skills and one Stop hook.

## Skills

| Skill | Purpose |
|-------|---------|
| `/plan-doc` | Writes a `spec.md` + `todo.md` (or phase-split `progress.md` + `todo-phase-N.md`) for a task. Surfaces open architectural decisions and manual-handling needs to the user via a mandatory ask gate before drafting. Document-only — no code is written. Finalizes drafts through a parallel review round: `/codex-chunk` + a Claude Code Fable5 Review (background `general-purpose` subagent on `model: "fable"`); both lanes must be clean. |
| `/plan-code` | Implements a plan phase-by-phase with mandatory `/simplify` → parallel review rounds per phase (`/codex-chunk` + Claude Code Fable5 Review run concurrently — a background subagent, `code-reviewer` type for code if available else `general-purpose`; both lanes must be clean), a holistic review across all phases, and `npm run build` verification. |
| `/plan-clean` | Scans `tasks/` for completed task directories and resolved out-of-scope issue articles. Classifies each as complete / incomplete / ambiguous and removes only the complete ones after explicit confirmation. |
| `/plan-issues` | Scans `tasks/out-of-scope-issues/` (priority-bucketed, legacy flat, or single-file layout), groups issues, batch-asks the user about each group's open decisions and manual-handling needs upfront, then routes each group through `/plan-doc` to produce task plans. |

`plan-doc`, `plan-code`, and `plan-issues` start with a **Preflight** block
that verifies their dependencies (`/simplify`, `/codex-chunk`, `/plan-doc`)
are loaded. They fail fast with an install hint if a dependency is missing
and explicitly forbid substituting other skills/agents.

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
- **Claude Code Fable5 Review** — no install needed: the second review lane
  uses Claude Code's built-in Agent tool (background subagent,
  `model: "fable"`; falls back to the newest flagship selector if `"fable"`
  is unavailable — the skills must tell the user about the substitution,
  never fall back silently).

## Install

```bash
/plugin install planner@tahara-claude-plugins
```
