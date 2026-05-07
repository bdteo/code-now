#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${ROOT_DIR}/hooks/hook.sh"
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

run_hook() {
    local RUNTIME="$1"
    local PAYLOAD="$2"
    HOME="$TMP_HOME" CODEX_HOME="$TMP_HOME/.codex" CODE_NOW_RUNTIME="$RUNTIME" "$HOOK" <<<"$PAYLOAD"
}

assert_contains() {
    local HAYSTACK="$1"
    local NEEDLE="$2"
    local MESSAGE="$3"
    if [[ "$HAYSTACK" != *"$NEEDLE"* ]]; then
        echo "FAIL: ${MESSAGE}" >&2
        echo "Expected to find: ${NEEDLE}" >&2
        echo "Actual output: ${HAYSTACK}" >&2
        exit 1
    fi
}

assert_empty() {
    local VALUE="$1"
    local MESSAGE="$2"
    if [[ -n "$VALUE" ]]; then
        echo "FAIL: ${MESSAGE}" >&2
        echo "Expected empty output, got: ${VALUE}" >&2
        exit 1
    fi
}

assert_json() {
    local VALUE="$1"
    local MESSAGE="$2"
    if ! jq empty >/dev/null 2>&1 <<<"$VALUE"; then
        echo "FAIL: ${MESSAGE}" >&2
        echo "Invalid JSON output: ${VALUE}" >&2
        exit 1
    fi
}

CLAUDE_USER=$(run_hook claude '{"hook_event_name":"UserPromptSubmit"}')
assert_json "$CLAUDE_USER" "Claude user prompt output should be JSON"
assert_contains "$CLAUDE_USER" '"hookEventName":"UserPromptSubmit"' "Claude user prompt should emit hook-specific context"
assert_contains "$CLAUDE_USER" 'Current time:' "Claude user prompt should include current time"

echo 1 > "$TMP_HOME/.claude/.code-now-last"
CLAUDE_USER_ELAPSED=$(run_hook claude '{"hook_event_name":"UserPromptSubmit"}')
assert_json "$CLAUDE_USER_ELAPSED" "Claude elapsed output should be JSON"
assert_contains "$CLAUDE_USER_ELAPSED" 'since last message' "Claude state file should produce elapsed time"

CLAUDE_PRE=$(run_hook claude '{"hook_event_name":"PreToolUse","tool_name":"Bash"}')
assert_json "$CLAUDE_PRE" "Claude PreToolUse output should be JSON"
assert_contains "$CLAUDE_PRE" '"hookEventName":"PreToolUse"' "Claude PreToolUse should emit hook-specific context"
assert_contains "$CLAUDE_PRE" 'Bash starting' "Claude PreToolUse should include tool start"

CLAUDE_POST=$(run_hook claude '{"hook_event_name":"PostToolUse","tool_name":"Read"}')
assert_json "$CLAUDE_POST" "Claude PostToolUse output should be JSON"
assert_contains "$CLAUDE_POST" '"hookEventName":"PostToolUse"' "Claude PostToolUse should emit hook-specific context"
assert_contains "$CLAUDE_POST" 'Read completed' "Claude PostToolUse should include tool completion"

CLAUDE_STOP=$(run_hook claude '{"hook_event_name":"Stop","stop_reason":"end_turn"}')
assert_json "$CLAUDE_STOP" "Claude Stop output should be JSON"
assert_contains "$CLAUDE_STOP" '"additionalContext"' "Claude Stop should emit top-level additionalContext"
assert_contains "$CLAUDE_STOP" 'Turn ended (end_turn)' "Claude Stop should include stop reason"

CODEX_SESSION=$(run_hook codex '{"hook_event_name":"SessionStart","source":"startup","model":"gpt-5.5"}')
assert_json "$CODEX_SESSION" "Codex SessionStart output should be JSON"
assert_contains "$CODEX_SESSION" '"hookEventName":"SessionStart"' "Codex SessionStart should emit hook-specific context"
assert_contains "$CODEX_SESSION" 'Current time:' "Codex SessionStart should include current time"

mkdir -p "$TMP_HOME/.codex"
echo 1 > "$TMP_HOME/.codex/.code-now-last"
CODEX_USER=$(run_hook codex '{"hook_event_name":"UserPromptSubmit","turn_id":"turn-1","model":"gpt-5.5","prompt":"hi"}')
assert_json "$CODEX_USER" "Codex UserPromptSubmit output should be JSON"
assert_contains "$CODEX_USER" '"hookEventName":"UserPromptSubmit"' "Codex UserPromptSubmit should emit hook-specific context"
assert_contains "$CODEX_USER" 'since last message' "Codex state file should produce elapsed time"

CODEX_POST=$(run_hook codex '{"hook_event_name":"PostToolUse","turn_id":"turn-1","model":"gpt-5.5","tool_name":"Bash"}')
assert_json "$CODEX_POST" "Codex PostToolUse output should be JSON"
assert_contains "$CODEX_POST" '"hookEventName":"PostToolUse"' "Codex PostToolUse should emit hook-specific context"
assert_contains "$CODEX_POST" 'Bash completed' "Codex PostToolUse should include tool completion"

CODEX_PRE=$(run_hook codex '{"hook_event_name":"PreToolUse","turn_id":"turn-1","model":"gpt-5.5","tool_name":"Bash"}')
assert_empty "$CODEX_PRE" "Codex PreToolUse should no-op because additionalContext is unsupported"

CODEX_STOP=$(run_hook codex '{"hook_event_name":"Stop","turn_id":"turn-1","model":"gpt-5.5"}')
assert_json "$CODEX_STOP" "Codex Stop output should be JSON"
assert_contains "$CODEX_STOP" '"continue":true' "Codex Stop should preserve normal flow"

UNKNOWN=$(run_hook codex '{"hook_event_name":"UnknownEvent","model":"gpt-5.5"}')
assert_empty "$UNKNOWN" "Unknown Codex events should no-op"

echo "All hook tests passed."
