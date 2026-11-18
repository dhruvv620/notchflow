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

## Agents

Connect each one in **Settings > AI Agents**. NotchFlow adds its hooks to the agent's own settings
file, keeps everything else, and saves a backup next to it (`<file>.notchflow-backup-<date>`).
Disconnect removes only hooks whose command contains `hook <agent>`.

| Agent | Settings file | From the notch |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | Approve (PermissionRequest), answer questions (AskUserQuestion), **reply after a turn**, progress, done |
| Codex CLI | `~/.codex/hooks.json` | Approve (PermissionRequest), progress, done. Trust the hooks once in Codex's `/hooks`. |
| Cursor (editor and cursor-agent) | `~/.cursor/hooks.json` | Approve risky shell commands and MCP tools (`beforeShellExecution`, `beforeMCPExecution`); ordinary commands follow Cursor's own rules. Progress, done. |
| Gemini CLI | `~/.gemini/settings.json` | Progress, "needs you" and done. Gemini's hooks can't hand a decision back to its own prompt, so approvals stay in its terminal. |
| Claude and ChatGPT apps | none | Their notifications appear in Notifications & Calls. They can't be approved from another app. |

Waiting hooks run `notchflow hook <agent>`; status hooks run `notchflow hook <agent> status`, so a
status copy of an event can never open a second approval. Claude Code also gets
`notchflow hook claude-code reply` on Stop with `asyncRewake: true`: it waits in the background
after each turn, and a reply typed in the notch wakes Claude with it (exit code 2). A new prompt
typed in the terminal cancels the wait.

Formats: Claude Code (https://code.claude.com/docs/en/hooks), Gemini CLI (docs/hooks/reference.md in
google-gemini/gemini-cli). Codex and Cursor follow their published hook formats as described in
third-party guides; their official pages could not be checked when this was written, so both fail
safe: an answer they don't understand leaves the agent's own prompt in place.

## New task

**New task** in the AI Agents tab: pick the agent (Claude Code, Codex, Gemini CLI, Cursor Agent) and
a project folder, type the task, and it opens in a new Terminal or iTerm window
(`cd <folder> && claude '<task>'`). Its approvals and progress come back to the notch through the
hooks above.

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
3. Add a `Connector` in `AgentSetup.connectors`; Settings > AI Agents lists it automatically.

