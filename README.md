# CodeNow

Temporal awareness for Claude Code and Codex.

CodeNow injects precise timestamps into coding-agent hook context so the agent knows the current time, how long it has been since your last message, and, where the runtime supports it, when tools start and finish.

The plugin ID is `code-now` for both Claude Code and Codex.

## The problem

You're deep in a debugging session. You ask the agent to check a queue size and it reports 42. You step away for coffee, come back 20 minutes later, and ask again.

> "The queue size is 42, as I already reported."

The agent is not necessarily being lazy. Coding-agent runtimes often include a date in the system prompt, but not a live clock. Between your messages, 5 seconds and 5 hours can look identical. That encourages stale answers, skipped re-checks, and guessed durations.

This is especially painful during deployments, production debugging, queue monitoring, and parallel agent work.

## The fix

A single bash script, packaged for both Claude Code and Codex.

Example Claude Code context:

```text
Current time: 2026-04-02 15:23:45 CEST | 3h 22m since last message
[15:23:46] Bash starting
[15:24:12] Bash completed
[15:24:13] Agent (general-purpose) started
[15:24:45] Agent completed
[15:24:45] Turn ended (end_turn)
```

Example Codex context:

```text
Current time: 2026-04-02 15:23:45 CEST | 3h 22m since last message
[15:24:12] Bash completed
```

Codex currently supports model-visible hook context for `SessionStart`, `UserPromptSubmit`, and `PostToolUse`. It does not yet add `PreToolUse` `additionalContext` to model context, so CodeNow intentionally treats Codex tool-start timestamps as a no-op until the runtime supports them.

## What gets timestamped

### Claude Code

| Event | Who sees it | What the agent sees |
|---|---|---|
| Your message | Parent | Full timestamp + elapsed time since last message |
| Bash command start | Parent | `[HH:MM:SS] Bash starting` |
| Any tool completion | Parent | `[HH:MM:SS] Bash completed`, `[HH:MM:SS] Read completed`, etc. |
| Agent spawned | Subagent | `[HH:MM:SS] Agent (general-purpose) started` |
| Agent finished | Parent | `[HH:MM:SS] Agent completed` via `PostToolUse:Agent` |
| Turn ended | Parent | `[HH:MM:SS] Turn ended (end_turn)` |

### Codex

| Event | What happens |
|---|---|
| `SessionStart` | Adds current timestamp as developer context |
| `UserPromptSubmit` | Adds current timestamp + elapsed time since last message |
| `PostToolUse` | Adds `[HH:MM:SS] <tool> completed` |
| `PreToolUse` | Runs successfully but emits no model-visible context because Codex does not support it yet |
| `Stop` | Runs successfully and preserves normal Codex flow |

## Install

### Claude Code plugin

```bash
claude plugin marketplace add bdteo/code-now
claude plugin install code-now
```

Restart Claude Code.

### Claude Code script installer

```bash
git clone https://github.com/bdteo/code-now.git
cd code-now
bash install.sh
```

Restart Claude Code.

### Codex plugin

Codex plugin hooks must be enabled first:

```toml
[features]
codex_hooks = true
plugin_hooks = true
```

Then add the marketplace and install the plugin:

```bash
codex plugin marketplace add bdteo/code-now
```

Restart Codex, open `/plugins`, choose the `CodeNow` marketplace, and install `CodeNow`.

For local development from this checkout, restart Codex after changing plugin files so the plugin cache can refresh.

## Update

### Claude Code

```bash
claude plugin marketplace update code-now
claude plugin update code-now@code-now
```

Restart Claude Code.

### Codex

```bash
codex plugin marketplace upgrade code-now
```

Restart Codex.

## Uninstall

### Claude Code plugin

```bash
claude plugin remove code-now
```

### Claude Code script install

```bash
bash uninstall.sh
```

### Codex plugin

Open `/plugins`, select `CodeNow`, and choose `Uninstall plugin`. To keep it installed but disabled, set `[plugins."code-now@code-now"].enabled = false` in `~/.codex/config.toml`, then restart Codex.

## Manual Claude Code install

1. Clone the repo and make the hook executable:

```bash
git clone https://github.com/bdteo/code-now.git
chmod +x code-now/plugins/code-now/hooks/hook.sh
```

2. Add this to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CODE_NOW_RUNTIME=claude \"/absolute/path/to/code-now/plugins/code-now/hooks/hook.sh\" || true"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "CODE_NOW_RUNTIME=claude \"/absolute/path/to/code-now/plugins/code-now/hooks/hook.sh\" || true"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CODE_NOW_RUNTIME=claude \"/absolute/path/to/code-now/plugins/code-now/hooks/hook.sh\" || true"
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CODE_NOW_RUNTIME=claude \"/absolute/path/to/code-now/plugins/code-now/hooks/hook.sh\" || true"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CODE_NOW_RUNTIME=claude \"/absolute/path/to/code-now/plugins/code-now/hooks/hook.sh\" || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CODE_NOW_RUNTIME=claude \"/absolute/path/to/code-now/plugins/code-now/hooks/hook.sh\" || true"
          }
        ]
      }
    ]
  }
}
```

3. Restart Claude Code.

## Known limitations

### Codex `PreToolUse` context is not injected yet

Codex parses `additionalContext` for `PreToolUse`, but the current runtime does not add it to model context. CodeNow still registers the event for forward compatibility, but the hook intentionally exits successfully without stdout for Codex `PreToolUse`.

### Claude Code `SubagentStop` output is silently discarded

The `SubagentStop` hook fires when a subagent finishes, but Claude Code does not inject its output into the parent conversation. CodeNow keeps the hook registered for forward compatibility. Parent-side agent completion timestamps are covered by `PostToolUse:Agent`.

### Stop hooks differ by runtime

Claude Code accepts top-level `additionalContext` for `Stop`. Codex `Stop` expects JSON control output and does not use `additionalContext` as model-visible temporal context, so CodeNow returns `{"continue":true}` and leaves normal turn flow unchanged.

## How it works

The hook script receives JSON on stdin from the runtime. It extracts the hook event name, formats a timestamp, and emits runtime-specific JSON.

For user messages, it tracks elapsed time using runtime-specific state files:

- Claude Code: `~/.claude/.code-now-last`
- Codex: `${CODEX_HOME:-~/.codex}/.code-now-last`

The hook itself has no dependency on `jq`. The Claude script installer and uninstaller use `jq` to edit `~/.claude/settings.json`.

## Requirements

- bash
- Claude Code v1.0.55+ for Claude support
- Codex with `[features].codex_hooks = true` and `[features].plugin_hooks = true` for Codex support
- `jq` only for `install.sh` / `uninstall.sh`

## Why not just use AGENTS.md or CLAUDE.md?

Adding "always check the time before responding" to instruction files is unreliable. The agent may ignore it, forget after context compaction, or decide it is irrelevant. A hook runs every time and injects timestamp context before the model continues.

## References

- Codex hooks: https://developers.openai.com/codex/hooks
- Codex plugins: https://developers.openai.com/codex/plugins
- Codex plugin build guide: https://developers.openai.com/codex/plugins/build
- Claude Code hooks: https://docs.anthropic.com/en/docs/claude-code/hooks

## Prior art

- https://github.com/anthropics/claude-code/issues/2618
- https://github.com/hodgesmr/temporal-awareness
- https://github.com/veteranbv/claude-UserPromptSubmit-hook

## License

MIT
