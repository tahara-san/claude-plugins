#!/usr/bin/env python3
"""PreToolUse hook — block access to .env / .env.* files.

Bundled in the env-blocker Claude Code plugin. Allowed exceptions:
.env.example, .env.sample, .env_example, .env_sample. Source files like
env.ts / env.js / env.mjs (no leading dot) are NOT blocked.

Wiring lives in this plugin's hooks/hooks.json — the matcher is
"Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Bash". Uses only Python stdlib.
"""
import json
import re
import sys

ALLOWED_BASENAMES = {
    ".env.example",
    ".env.sample",
    ".env_example",
    ".env_sample",
}

# A path's basename is "blocked" when it is exactly ".env",
# starts with ".env." (e.g. .env.local, .env.production), or
# starts with ".env_" (e.g. .env_local) — minus the allowed exceptions.
BLOCKED_BASENAME_RE = re.compile(r"^\.env(\..+|_.+)?$")

# Bash-command scanner: find ".env" tokens that are real filename references.
# Negative lookbehind avoids matching "app.env" or ".envrc" / ".environment".
BASH_TOKEN_RE = re.compile(
    r"(?<![A-Za-z0-9_\-])\.env(\.[A-Za-z0-9_\-]+|_[A-Za-z0-9_\-]+)?(?![A-Za-z0-9_\-])"
)


def is_blocked_basename(base: str) -> bool:
    if not base:
        return False
    if base in ALLOWED_BASENAMES:
        return False
    return bool(BLOCKED_BASENAME_RE.match(base))


def deny(reason: str) -> int:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    return 0


REASON_SUFFIX = (
    " env-blocker plugin policy forbids access to .env and .env.* files. "
    "Allowed: .env.example, .env.sample, .env_example, .env_sample. "
    "Source files like env.ts / env.js / env.mjs are allowed."
)


def check_path(path: str) -> int | None:
    if not path:
        return None
    base = path.rsplit("/", 1)[-1]
    if is_blocked_basename(base):
        return deny(f"Blocked env-file access: {path}.{REASON_SUFFIX}")
    return None


def check_glob_pattern(pattern: str) -> int | None:
    if not pattern:
        return None
    base = pattern.rsplit("/", 1)[-1]
    # Allowed exact glob targets pass through.
    if base in ALLOWED_BASENAMES:
        return None
    # Block patterns whose basename starts with ".env" (covers .env, .env.*,
    # .env_*, .env*, etc.). This is intentionally broad — globbing into env
    # files is not a workflow we need to support.
    if base.startswith(".env"):
        return deny(f"Blocked glob targets env files: {pattern}.{REASON_SUFFIX}")
    return None


def check_bash_command(cmd: str) -> int | None:
    if not cmd:
        return None
    for m in BASH_TOKEN_RE.finditer(cmd):
        token = m.group(0)
        if token in ALLOWED_BASENAMES:
            continue
        return deny(
            f"Blocked: Bash command references env file '{token}'.{REASON_SUFFIX}"
        )
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    tool_name = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}

    if tool_name in ("Read", "Edit", "Write", "MultiEdit"):
        rc = check_path(tool_input.get("file_path") or "")
        if rc is not None:
            return rc
    elif tool_name == "NotebookEdit":
        rc = check_path(tool_input.get("notebook_path") or "")
        if rc is not None:
            return rc
    elif tool_name == "Glob":
        rc = check_glob_pattern(tool_input.get("pattern") or "")
        if rc is not None:
            return rc
    elif tool_name == "Bash":
        rc = check_bash_command(tool_input.get("command") or "")
        if rc is not None:
            return rc

    return 0


if __name__ == "__main__":
    sys.exit(main())
