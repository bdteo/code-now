#!/usr/bin/env bash
# CodeNow uninstaller
# Removes all hooks from ~/.claude/settings.json

set -euo pipefail

SETTINGS_FILE="${HOME}/.claude/settings.json"
STATE_FILE="${HOME}/.claude/.code-now-last"
LEGACY_STATE_FILE="${HOME}/.claude/.claude-code-now-last"
EVENTS=("UserPromptSubmit" "PreToolUse" "PostToolUse" "SubagentStart" "SubagentStop" "Stop")

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "No settings file found at ${SETTINGS_FILE}. Nothing to uninstall."
    exit 0
fi

if ! grep -Eq "code-now|CodeNow|claude-code-now" "$SETTINGS_FILE" 2>/dev/null; then
    echo "CodeNow is not installed in ${SETTINGS_FILE}. Nothing to uninstall."
    exit 0
fi

if ! command -v jq &>/dev/null; then
    echo "jq is required to uninstall. Please remove the CodeNow hook entries"
    echo "from ${SETTINGS_FILE} manually."
    exit 1
fi

TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

# Build a jq filter that removes CodeNow entries from all events
FILTER=""
for EVENT in "${EVENTS[@]}"; do
    FILTER+="
        .hooks.${EVENT} //= [] |
        .hooks.${EVENT} = [
            .hooks.${EVENT}[] |
            select(.hooks | all(.command | test(\"code-now|CodeNow|claude-code-now\") | not))
        ] |
        if .hooks.${EVENT} == [] then del(.hooks.${EVENT}) else . end |"
done
FILTER+="
    if .hooks == {} then del(.hooks) else . end"

jq "$FILTER" "$SETTINGS_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$SETTINGS_FILE"

# Clean up state file
rm -f "$STATE_FILE" "$LEGACY_STATE_FILE"

echo "Uninstalled CodeNow successfully (6 hooks removed)."
echo "Restart Claude Code for the change to take effect."
