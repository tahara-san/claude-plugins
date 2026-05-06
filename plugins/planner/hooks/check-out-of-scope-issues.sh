#!/usr/bin/env python3
"""Stop hook — reminds the agent to log out-of-scope issues before finishing.

Bundled in the planner Claude Code plugin. Enforces the user-level
"Out-of-Scope Issue Tracking (MANDATORY)" rule by soft-blocking the Stop
event when the last assistant turn mentions issue-like keywords AND did not
write any new files under tasks/out-of-scope-issues/. Uses only the Python
stdlib — no jq dependency.
"""
import json
import re
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    # Loop guard: skip if we were already invoked in response to a previous block.
    if payload.get("stop_hook_active"):
        return 0

    transcript_path = payload.get("transcript_path")
    if not transcript_path:
        return 0

    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return 0

    # Scan backward from the end. Stop at the first *real* user message
    # (which delimits the current assistant turn). A real user message has
    # content as a plain string OR a list containing at least one {type: text}
    # item. Synthetic user entries that wrap tool_result objects are NOT turn
    # boundaries — they're tool outputs returning to the agent mid-turn.
    last_turn_entries = []
    for raw in reversed(lines):
        raw = raw.strip()
        if not raw:
            continue
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError:
            continue

        if entry.get("type") == "user":
            msg = entry.get("message") or {}
            content = msg.get("content")
            is_real_user = False
            if isinstance(content, str):
                is_real_user = True
            elif isinstance(content, list):
                is_real_user = any(
                    isinstance(c, dict) and c.get("type") == "text" for c in content
                )
            if is_real_user:
                break

        last_turn_entries.append(entry)

    last_turn_entries.reverse()

    if not last_turn_entries:
        return 0

    # Collect all assistant text and any Write/Edit tool-use file_paths in the
    # current turn.
    text_chunks = []
    tool_file_paths = []
    for entry in last_turn_entries:
        if entry.get("type") != "assistant":
            continue
        msg = entry.get("message") or {}
        content = msg.get("content") or []
        if isinstance(content, str):
            text_chunks.append(content)
            continue
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text":
                t = item.get("text")
                if isinstance(t, str):
                    text_chunks.append(t)
            elif item.get("type") == "tool_use":
                name = item.get("name")
                if name in ("Write", "Edit"):
                    fp = (item.get("input") or {}).get("file_path")
                    if isinstance(fp, str):
                        tool_file_paths.append(fp)

    last_text = "\n".join(text_chunks)

    # Keyword check — focused set to minimize false positives.
    keyword_re = re.compile(
        r"(pre-existing|out[- ]of[- ]scope|follow-up|no-op|\bskipped\b|code smell)",
        re.IGNORECASE,
    )
    if not keyword_re.search(last_text):
        return 0

    # Was any Write/Edit in this turn targeting tasks/out-of-scope-issues/ ?
    touched = any("tasks/out-of-scope-issues/" in p for p in tool_file_paths)
    if touched:
        return 0

    # Block with a reminder — Claude Code re-invokes the agent with the reason.
    json.dump(
        {
            "decision": "block",
            "reason": (
                "You mentioned potential issues, pre-existing problems, skipped "
                "items, or follow-ups in your response but did not log "
                "a new issue file in this turn. Per the "
                "MANDATORY Out-of-Scope Issue Tracking rule (see your global "
                "CLAUDE.md), every out-of-scope warning, code smell, bug, or "
                "potential problem encountered during a task MUST be logged as "
                "a separate markdown file at "
                "<project_dir>/tasks/out-of-scope-issues/<priority>/<YYYYMMDD>_<short-kebab>.md "
                "before finishing. The <YYYYMMDD>_ date prefix is the file's "
                "creation date and is MANDATORY at creation time. Do NOT leave "
                "the literal text 'YYYYMMDD' in the filename — substitute "
                "today's date. Review your most recent response. If any items "
                "are not yet logged, create the file(s) now using the Write tool. "
                "If an issue cannot be auto-fixed and needs manual investigation "
                "or intervention, file it at "
                "tasks/out-of-scope-issues/<priority>/manual/<YYYYMMDD>_<short-kebab>.md "
                "instead of the priority root so it is parked, not auto-planned. "
                "(Illustrative example: "
                "tasks/out-of-scope-issues/medium/20260506_missing-error-handling.md "
                "— substitute today's date and an issue-specific kebab.) "
                "If everything mentioned is either already logged or is not "
                "actually an out-of-scope issue, briefly acknowledge that and stop."
            ),
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
