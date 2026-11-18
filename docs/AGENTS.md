# AI agents in the notch

NotchFlow shows what AI agents are doing and lets you approve them from the notch.
Claude Code is connected from **Settings > AI Agents > Connect**. This page explains how it
works and how to connect other agents and scripts.

## How it works

```
agent hook ──runs──> notchflow (~/.local/bin) ──HTTP, 127.0.0.1 + token──> NotchFlow ──> notch
            <──────── answer (allow / deny / nothing) ─────────────────────────
```

- NotchFlow listens on 127.0.0.1 only, on a random port. The port and a random token are in
  `~/Library/Application Support/NotchFlow/agent-bridge.env` (readable only by you), and every
  request must carry the token.
- `notchflow` is a bash script that uses curl. If NotchFlow is not running, hooks print nothing
  and exit 0, so the agent behaves as if there were no hook.
- Nothing is approved on its own. Unanswered requests time out (Settings > AI Agents) and the
  agent asks in its own window.

## Claude Code

Connecting adds these hooks to `~/.claude/settings.json` (your own hooks stay; a backup is
saved next to it as `settings.json.notchflow-backup-<date>`):

| Event | Waits for you | Used for |
|---|---|---|
| `PermissionRequest` | yes | Allow / Always allow / Deny from the notch |
| `PreToolUse` on `AskUserQuestion` | yes | Answering Claude's multiple-choice questions |
| `PreToolUse`, `PostToolUse` | no (async) | "Running npm test", "Editing auth.swift" |
| `UserPromptSubmit`, `Notification`, `Stop`, `SessionStart`, `SessionEnd` | no (async) | Working / needs you / done |

Waiting hooks run `notchflow hook claude-code`; status hooks run `notchflow hook claude-code status`,
so a status copy of an event can never open a second approval. Disconnecting removes only hooks
whose command contains `hook claude-code`. Reference: https://code.claude.com/docs/en/hooks

## Scripts and any other tool

```bash
notchflow ask "Deploy to production?" --options "Deploy,Cancel" --title "Release"
# prints the choice; exit 1 if dismissed or unanswered, 2 if NotchFlow is not running

notchflow notify "Backup finished" --title "Backup"
notchflow status
```

Any agent whose hooks can run a command can use `notchflow ask` to get a decision from the notch
today.

## Adding another agent (for contributors)

1. Add its hook format to `AgentHookPolicy` (parse its events, build its answers) with checks in
   `tests/AgentHookRegression.swift`.
2. Handle `POST /v1/hook/<agent>` (and `/status`) in `AgentHub.handle`.
3. Add Connect / Disconnect for its config file in `AgentSetup`, and a row in `AgentsSettings`.

Next up: Codex CLI (hooks.json, PermissionRequest), Gemini CLI (BeforeTool) and Cursor hooks.
