#!/usr/bin/env bash
# CodeNow installer
# Adds all hooks to ~/.claude/settings.json

set -euo pipefail

HOOK_SCRIPT="$(cd "$(dirname "$0")" && pwd)/hooks/hook.sh"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# Ensure hook script is executable
chmod +x "${HOOK_SCRIPT}"

# Ensure ~/.claude directory exists
mkdir -p "${HOME}/.claude"

# Create settings file if it doesn't exist
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# Check if hook is already installed
if grep -Eq "code-now|CodeNow|claude-code-now" "$SETTINGS_FILE" 2>/dev/null; then
    echo "CodeNow is already installed in ${SETTINGS_FILE}"
    echo "Run uninstall.sh first if you want to reinstall."
    exit 0
fi

# Use a temporary file for safe in-place editing
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

HOOK_CMD="CODE_NOW_RUNTIME=claude \"${HOOK_SCRIPT}\" || true"

# Check if jq is available
if command -v jq &>/dev/null; then
    # Generic hook entry (all events except PreToolUse)
    ALL_ENTRY=$(cat <<HOOKJSON
{
    "matcher": "",
    "hooks": [
        {
            "type": "command",
            "command": "${HOOK_CMD}"
        }
    ]
}
HOOKJSON
    )

    # Bash-only hook entry (PreToolUse)
    BASH_ENTRY=$(cat <<HOOKJSON
{
    "matcher": "Bash",
    "hooks": [
        {
            "type": "command",
            "command": "${HOOK_CMD}"
        }
    ]
}
HOOKJSON
    )

    # Add all hooks to settings
    jq --argjson all "$ALL_ENTRY" --argjson bash "$BASH_ENTRY" '
        .hooks //= {} |
        .hooks.UserPromptSubmit //= [] | .hooks.UserPromptSubmit += [$all] |
        .hooks.PreToolUse //= []       | .hooks.PreToolUse += [$bash] |
        .hooks.PostToolUse //= []      | .hooks.PostToolUse += [$all] |
        .hooks.SubagentStart //= []    | .hooks.SubagentStart += [$all] |
        .hooks.SubagentStop //= []     | .hooks.SubagentStop += [$all] |
        .hooks.Stop //= []             | .hooks.Stop += [$all]
    ' "$SETTINGS_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$SETTINGS_FILE"

    echo "Installed CodeNow successfully (6 hooks registered)."
    echo ""
    echo "  Hook script: ${HOOK_SCRIPT}"
    echo "  Settings:    ${SETTINGS_FILE}"
    echo ""
    echo "  Events: UserPromptSubmit, PreToolUse (Bash), PostToolUse,"
    echo "          SubagentStart, SubagentStop, Stop"
    echo ""
    echo "Restart Claude Code for the hooks to take effect."
else
    echo "jq is not installed. Please add the hooks manually to ${SETTINGS_FILE}."
    echo "See the README for the full manual configuration."
    echo ""
    echo "Install jq (brew install jq / apt install jq) for automatic installation."
    exit 1
fi
