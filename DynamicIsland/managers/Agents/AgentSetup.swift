// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Installs the `notchflow` command and connects agents to it.
///
/// The command is a small bash script in ~/.local/bin that forwards to the
/// app's local bridge with curl (both ship with macOS). When NotchFlow is not
/// running it prints nothing and exits 0, so an agent's hook never gets in
/// the way.
enum AgentSetup {
    static let scriptVersion = 1

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

    // MARK: Claude Code

    static func readClaudeSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return [:] }
        let data = try Data(contentsOf: claudeSettingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SetupError.invalidSettings(claudeSettingsURL)
        }
        return object
    }

    static var isClaudeCodeConnected: Bool {
        (try? readClaudeSettings()).map(AgentHookPolicy.isInstalled) ?? false
    }

    /// Adds NotchFlow's hooks to ~/.claude/settings.json (keeping everything
    /// else) and installs the command they call. Returns the backup's location.
    @discardableResult
    static func connectClaudeCode(waitSeconds: Int) throws -> URL? {
        try installCommand()
        let settings = try readClaudeSettings()
        let backup = try backupClaudeSettings()
        let updated = AgentHookPolicy.installing(into: settings, executable: commandURL.path, waitSeconds: waitSeconds)
        try writeClaudeSettings(updated)
        return backup
    }

    /// Removes only NotchFlow's hooks; the user's own hooks and settings stay.
    @discardableResult
    static func disconnectClaudeCode() throws -> URL? {
        let settings = try readClaudeSettings()
        guard AgentHookPolicy.isInstalled(settings) else { return nil }
        let backup = try backupClaudeSettings()
        try writeClaudeSettings(AgentHookPolicy.removing(from: settings))
        return backup
    }

    /// A readable list of what connecting adds, shown before the user confirms.
    static var claudeCodeChangeSummary: String {
        let events = AgentHookPolicy.hookPlan.map { entry -> String in
            let what = entry.waits ? "waits for your answer" : "status, runs in the background"
            return "• \(entry.event)\(entry.matcher.map { " (\($0))" } ?? ""): \(what)"
        }
        return "Adds these hooks to ~/.claude/settings.json, each running \(commandURL.path):\n" + events.joined(separator: "\n")
    }

    private static func backupClaudeSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = claudeSettingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.notchflow-backup-\(formatter.string(from: Date()))")
        try FileManager.default.copyItem(at: claudeSettingsURL, to: backup)
        return backup
    }

    private static func writeClaudeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeSettingsURL, options: .atomic)
    }

    // MARK: The script

    static let script = #"""
    #!/bin/bash
    # notchflow: lets AI agents and scripts talk to NotchFlow, the notch app.
    # Installed by NotchFlow (Settings > AI Agents); reinstalling replaces this file.
    NF_SCRIPT_VERSION=1
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
      notchflow hook claude-code
          Used by Claude Code's hooks (connect it in NotchFlow > Settings > AI Agents).
    USAGE
    }

    cmd="${1:-help}"
    [ $# -gt 0 ] && shift

    case "$cmd" in
      hook)
        agent="${1:-claude-code}"
        path="/v1/hook/$agent"
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
