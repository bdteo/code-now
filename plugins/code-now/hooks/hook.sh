#!/usr/bin/env bash
# shellcheck shell=bash
# code-now - Temporal awareness for Claude Code and Codex
# https://github.com/bdteo/code-now
#
# Multi-event hook that injects precise timestamps into coding-agent context.

set -euo pipefail

CLAUDE_STATE_FILE="${HOME}/.claude/.code-now-last"
CODEX_STATE_FILE="${CODEX_HOME:-${HOME}/.codex}/.code-now-last"

# Single date call, extract all formats via string manipulation.
NOW_ALL=$(date '+%s %Y-%m-%d %H:%M:%S %Z')
NOW_EPOCH="${NOW_ALL%% *}"
NOW_HUMAN="${NOW_ALL#* }"
NOW_TIME="${NOW_HUMAN:11:8}"

# Read stdin (hook input JSON).
INPUT=$(cat)

# Simple JSON string field extractor (no jq dependency).
json_field() {
    echo "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true
}

EVENT=$(json_field "hook_event_name")

detect_runtime() {
    if [[ "${CODE_NOW_RUNTIME:-}" == "codex" || "${CODEX_CODE_NOW_RUNTIME:-}" == "codex" ]]; then
        echo "codex"
    elif [[ "${CODE_NOW_RUNTIME:-}" == "claude" || "${CLAUDE_CODE_NOW_RUNTIME:-}" == "claude" ]]; then
        echo "claude"
    elif [[ "$EVENT" == "SessionStart" || "$INPUT" == *'"turn_id"'* || "$INPUT" == *'"model"'* ]]; then
        echo "codex"
    else
        echo "claude"
    fi
}

RUNTIME=$(detect_runtime)
case "$RUNTIME" in
    codex) STATE_FILE="$CODEX_STATE_FILE" ;;
    *) STATE_FILE="$CLAUDE_STATE_FILE" ;;
esac

json_escape() {
    local VALUE="$1"
    VALUE=${VALUE//\\/\\\\}
    VALUE=${VALUE//\"/\\\"}
    VALUE=${VALUE//$'\n'/\\n}
    VALUE=${VALUE//$'\r'/\\r}
    VALUE=${VALUE//$'\t'/\\t}
    printf '%s' "$VALUE"
}

emit_context_json() {
    local HOOK_EVENT_NAME="$1"
    local ADDITIONAL_CONTEXT="$2"
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
        "$(json_escape "$HOOK_EVENT_NAME")" \
        "$(json_escape "$ADDITIONAL_CONTEXT")"
}

emit_top_level_context_json() {
    local ADDITIONAL_CONTEXT="$1"
    printf '{"additionalContext":"%s"}\n' "$(json_escape "$ADDITIONAL_CONTEXT")"
}

# Format elapsed time since last user message.
format_elapsed() {
    local DIFF="$1"
    if (( DIFF >= 86400 )); then
        echo " | $((DIFF / 86400))d $(( (DIFF % 86400) / 3600 ))h since last message"
    elif (( DIFF >= 3600 )); then
        echo " | $((DIFF / 3600))h $(( (DIFF % 3600) / 60 ))m since last message"
    elif (( DIFF >= 60 )); then
        echo " | $((DIFF / 60))m $((DIFF % 60))s since last message"
    elif (( DIFF > 5 )); then
        echo " | ${DIFF}s since last message"
    fi
}

current_time_context() {
    local TRACK_ELAPSED="${1:-yes}"
    local ELAPSED=""
    if [[ "$TRACK_ELAPSED" == "yes" && -f "$STATE_FILE" ]]; then
        LAST_EPOCH=$(<"$STATE_FILE")
        if [[ "$LAST_EPOCH" =~ ^[0-9]+$ ]]; then
            ELAPSED=$(format_elapsed "$((NOW_EPOCH - LAST_EPOCH))")
        fi
    fi
    if [[ "$TRACK_ELAPSED" == "yes" ]]; then
        mkdir -p "$(dirname "$STATE_FILE")"
        echo "${NOW_EPOCH}" > "${STATE_FILE}"
    fi
    echo "Current time: ${NOW_HUMAN}${ELAPSED}"
}

build_context() {
    case "$EVENT" in
        SessionStart)
            current_time_context no
            ;;
        UserPromptSubmit)
            current_time_context yes
            ;;
        PreToolUse)
            TOOL_NAME=$(json_field "tool_name")
            echo "[${NOW_TIME}] ${TOOL_NAME} starting"
            ;;
        PostToolUse)
            TOOL_NAME=$(json_field "tool_name")
            echo "[${NOW_TIME}] ${TOOL_NAME} completed"
            ;;
        SubagentStart)
            AGENT_TYPE=$(json_field "agent_type")
            echo "[${NOW_TIME}] Agent (${AGENT_TYPE}) started"
            ;;
        SubagentStop)
            AGENT_TYPE=$(json_field "agent_type")
            echo "[${NOW_TIME}] Agent (${AGENT_TYPE}) finished"
            ;;
        Stop)
            STOP_REASON=$(json_field "stop_reason")
            echo "[${NOW_TIME}] Turn ended (${STOP_REASON})"
            ;;
        *)
            echo "[${NOW_TIME}] ${EVENT}"
            ;;
    esac
}

CONTEXT=$(build_context)

if [[ "$RUNTIME" == "codex" ]]; then
    case "$EVENT" in
        SessionStart|UserPromptSubmit|PostToolUse)
            emit_context_json "$EVENT" "$CONTEXT"
            ;;
        PreToolUse)
            # Codex currently parses additionalContext for PreToolUse but does
            # not add it to model context, so this hook intentionally succeeds
            # without output rather than emitting misleading JSON.
            exit 0
            ;;
        Stop)
            # Codex Stop expects JSON but does not use additionalContext as
            # model-visible temporal context. Continue without altering flow.
            printf '{"continue":true}\n'
            ;;
        *)
            exit 0
            ;;
    esac
    exit 0
fi

# Inject temporal context into Claude's awareness.
#
# hookSpecificOutput is supported by: PreToolUse, PostToolUse,
# UserPromptSubmit, SubagentStart. Top-level additionalContext is used for:
# Stop (and other events).
#
# SubagentStop: hook fires but Claude Code does not inject output into the
# parent conversation regardless of format. We still emit hookSpecificOutput
# for forward compatibility in case Anthropic adds support.
case "$EVENT" in
    PreToolUse|PostToolUse|UserPromptSubmit|SubagentStart|SubagentStop)
        emit_context_json "$EVENT" "$CONTEXT"
        ;;
    *)
        emit_top_level_context_json "$CONTEXT"
        ;;
esac
