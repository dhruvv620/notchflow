// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Installs the `notchflow` command and connects agents to it.
///
/// The command is a small bash script in ~/.local/bin that forwards to the
/// app's local bridge with curl (both ship with macOS). When NotchFlow is not
/// running it prints nothing and exits 0, so an agent's hook never gets in
/// the way.
enum AgentSetup {
    static let scriptVersion = 2

    enum SetupError: LocalizedError {
        case invalidSettings(URL)
        var errorDescription: String? {
            switch self {
            case .invalidSettings(let url):
                return "\(url.path) is not valid JSON, so NotchFlow left it alone. Fix it and try again."
            }
        }
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var commandURL: URL { home.appendingPathComponent(".local/bin/notchflow") }
    static var claudeSettingsURL: URL { home.appendingPathComponent(".claude/settings.json") }

    // MARK: The notchflow command

    static var isCommandCurrent: Bool {
        guard let text = try? String(contentsOf: commandURL, encoding: .utf8) else { return false }
        return text.contains("NF_SCRIPT_VERSION=\(scriptVersion)\n")
    }

    static func installCommand() throws {
        let directory = commandURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try script.write(to: commandURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandURL.path)
    }

    static func removeCommand() throws {
        if FileManager.default.fileExists(atPath: commandURL.path) {
            try FileManager.default.removeItem(at: commandURL)
        }
    }

    // MARK: Agents

    /// An agent NotchFlow can connect to: where its hook settings live and what to tell the user.
    struct Connector: Identifiable {
        let agent: AgentKind
        let target: AgentHookPolicy.HookTarget
        /// Path under the home folder.
        let relativePath: String
        let summary: String
        /// Shown after connecting (e.g. Codex's trust step).
        let afterConnecting: String?
        var id: String { target.id }
        var settingsURL: URL { home.appendingPathComponent(relativePath) }
        var displayPath: String { "~/" + relativePath }
    }

    static let connectors: [Connector] = [
        Connector(agent: .claudeCode, target: AgentHookPolicy.claudeCode, relativePath: ".claude/settings.json",
                  summary: "Approve, answer questions, reply after a turn, and follow progress.",
                  afterConnecting: "Restart running Claude Code sessions to pick it up."),
        Connector(agent: .codex, target: AgentHookPolicy.codex, relativePath: ".codex/hooks.json",
                  summary: "Approve and follow progress.",
                  afterConnecting: "Open Codex and trust the NotchFlow hooks in /hooks; Codex only runs hooks you have reviewed."),
        Connector(agent: .cursor, target: AgentHookPolicy.cursor, relativePath: ".cursor/hooks.json",
                  summary: "Approve risky commands and MCP tools; follow progress. Other commands follow Cursor's own rules.",
                  afterConnecting: "Restart Cursor (and cursor-agent) to pick it up."),
        Connector(agent: .gemini, target: AgentHookPolicy.gemini, relativePath: ".gemini/settings.json",
                  summary: "Follow progress and see when it needs you. Gemini's own prompt handles approvals.",
                  afterConnecting: "Restart Gemini CLI to pick it up."),
    ]

    static func connector(for agent: AgentKind) -> Connector? { connectors.first { $0.agent == agent } }

    static func readSettings(_ connector: Connector) throws -> [String: Any] {
        let url = connector.settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SetupError.invalidSettings(url)
        }
        return object
    }

    static func isConnected(_ connector: Connector) -> Bool {
        (try? readSettings(connector)).map { AgentHookPolicy.isInstalled($0, target: connector.target) } ?? false
    }

    /// Adds NotchFlow's hooks to the agent's settings (keeping everything else)
    /// and installs the command they call. Returns the backup's location.
    @discardableResult
    static func connect(_ connector: Connector, waitSeconds: Int) throws -> URL? {
        try installCommand()
        let settings = try readSettings(connector)
        let backup = try backup(connector)
        let updated = AgentHookPolicy.installing(into: settings, executable: commandURL.path,
                                                 waitSeconds: waitSeconds, target: connector.target)
        try write(updated, to: connector)
        return backup
    }

    /// Removes only NotchFlow's hooks; the user's own hooks and settings stay.
    @discardableResult
    static func disconnect(_ connector: Connector) throws -> URL? {
        let settings = try readSettings(connector)
        guard AgentHookPolicy.isInstalled(settings, target: connector.target) else { return nil }
        let backup = try backup(connector)
        try write(AgentHookPolicy.removing(from: settings, target: connector.target), to: connector)
        return backup
    }

    /// A readable list of what connecting adds, shown before the user confirms.
    static func changeSummary(_ connector: Connector) -> String {
        let events = connector.target.plan.map { entry -> String in
            let what: String
            switch entry.mode {
            case .waits: what = "waits for your answer"
            case .status: what = "status only"
            case .reply: what = "after each turn, waits in the background for a reply from the notch"
            }
            return "• \(entry.event)\(entry.matcher.map { " (\($0))" } ?? ""): \(what)"
        }
        return "Adds these hooks to \(connector.displayPath), each running \(commandURL.path):\n" + events.joined(separator: "\n")
    }

    // Claude Code shorthands.
    static var claudeCode: Connector { connectors[0] }
    static var isClaudeCodeConnected: Bool { isConnected(claudeCode) }
    static var anyAgentConnected: Bool { connectors.contains(where: isConnected) }

    private static func backup(_ connector: Connector) throws -> URL? {
        let url = connector.settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).notchflow-backup-\(formatter.string(from: Date()))")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }

    private static func write(_ settings: [String: Any], to connector: Connector) throws {
        let url = connector.settingsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    // MARK: The script

    static let script = #"""
    #!/bin/bash
    # notchflow: lets AI agents and scripts talk to NotchFlow, the notch app.
    # Installed by NotchFlow (Settings > AI Agents); reinstalling replaces this file.
    NF_SCRIPT_VERSION=2
    BRIDGE="$HOME/Library/Application Support/NotchFlow/agent-bridge.env"

    nf_value() { /usr/bin/sed -n "s/^$1=//p" "$BRIDGE" 2>/dev/null | /usr/bin/head -n 1; }

    nf_call() {
      local method="$1" path="$2" port token
      shift 2
      port="$(nf_value NOTCHFLOW_PORT)"
      token="$(nf_value NOTCHFLOW_TOKEN)"
      [ -n "$port" ] && [ -n "$token" ] || return 7
      /usr/bin/curl -sS --fail --connect-timeout 2 -X "$method" \
        -H "Authorization: Bearer $token" \
        -H "X-NotchFlow-App: ${__CFBundleIdentifier:-}" \
        -H "X-NotchFlow-Terminal: ${TERM_PROGRAM:-}" \
        "$@" "http://127.0.0.1:$port$path"
    }

    usage() {
      cat <<'USAGE'
    notchflow: talk to NotchFlow from AI agents and scripts

      notchflow ask "Deploy to production?" [--options "Deploy,Cancel"] [--title "Release"]
          Asks in the notch and prints the answer.
          Exit 1 if dismissed or unanswered, 2 if NotchFlow is not running.
      notchflow notify "Backup finished" [--title "Backup"]
          Shows a message under the notch.
      notchflow status
          Checks that NotchFlow is running.
      notchflow hook <claude-code|codex|cursor|gemini>
          Used by the agents' hooks (connect them in NotchFlow > Settings > AI Agents).
    USAGE
    }

    cmd="${1:-help}"
    [ $# -gt 0 ] && shift

    case "$cmd" in
      hook)
        agent="${1:-claude-code}"
        path="/v1/hook/$agent"
        if [ "${2:-}" = "reply" ]; then
          # Runs in the background after a turn (asyncRewake). A reply typed in
          # the notch comes back here; exit 2 hands it to the agent.
          reply="$(nf_call POST "$path/reply" --max-time 3600 -H "Content-Type: application/json" --data-binary @- 2>/dev/null)"
          if [ -n "$reply" ]; then printf '%s\n' "$reply" >&2; exit 2; fi
          exit 0
        fi
        [ "${2:-}" = "status" ] && path="$path/status"
        # Never get in the agent's way: if NotchFlow is not running or anything
        # fails, print nothing, and the agent carries on as if there were no hook.
        nf_call POST "$path" --max-time 900 -H "Content-Type: application/json" --data-binary @- 2>/dev/null || true
        exit 0
        ;;
      ask)
        question="${1:-}"
        [ $# -gt 0 ] && shift
        options="Yes,No"
        title=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --options) options="${2:-}"; shift 2 ;;
            --title) title="${2:-}"; shift 2 ;;
            *) shift ;;
          esac
        done
        [ -n "$question" ] || { usage; exit 64; }
        answer="$(nf_call POST /v1/ask --max-time 900 --data-urlencode "question=$question" \
          --data-urlencode "options=$options" --data-urlencode "title=$title")"
        if [ $? -ne 0 ]; then echo "notchflow: NotchFlow is not running" >&2; exit 2; fi
        [ -n "$answer" ] || exit 1
        printf '%s\n' "$answer"
        ;;
      notify)
        message="${1:-}"
        [ $# -gt 0 ] && shift
        title=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --title) title="${2:-}"; shift 2 ;;
            *) shift ;;
          esac
        done
        nf_call POST /v1/notify --max-time 5 --data-urlencode "message=$message" \
          --data-urlencode "title=$title" >/dev/null || { echo "notchflow: NotchFlow is not running" >&2; exit 2; }
        ;;
      status)
        if ! nf_call GET /v1/health --max-time 3; then
          echo "notchflow: NotchFlow is not running (or AI Agents is off in its settings)" >&2
          exit 2
        fi
        ;;
      version|--version) echo "notchflow $NF_SCRIPT_VERSION" ;;
      *) usage ;;
    esac
    """#
}
