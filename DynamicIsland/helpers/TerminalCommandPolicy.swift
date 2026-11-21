// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// When a command in the notch's terminal finishing is worth telling you
/// about, and how to say it (Foundation only, so Build.command can check it
/// alone).
enum TerminalCommandPolicy {
    /// Programs you sit in and quit yourself (editors, pagers, REPLs,
    /// remote shells, agents): leaving one isn't "a command finished".
    static let interactive: Set<String> = [
        "vim", "nvim", "vi", "nano", "emacs", "micro", "hx", "less", "more", "man", "top", "htop", "btop",
        "ssh", "mosh", "tmux", "screen", "zsh", "bash", "fish", "sh", "python", "python3", "node", "irb",
        "ruby", "psql", "mysql", "sqlite3", "redis-cli", "lazygit", "tig", "fzf", "watch", "claude", "codex",
        "gemini", "aider", "ollama", "ipython", "bun", "deno", "lua", "ghci", "iex", "erl", "sftp", "ftp", "telnet",
    ]

    /// The program's name as `ps` shows it ("-zsh" → "zsh", "/usr/bin/git" → "git").
    static func programName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("-") { name.removeFirst() }
        return (name as NSString).lastPathComponent.lowercased()
    }

    /// Tell you when: notifications are on, it ran at least `threshold`
    /// seconds, it isn't something interactive, and you weren't watching it.
    static func shouldNotify(command: String, duration: TimeInterval, threshold: TimeInterval,
                             isWatching: Bool, enabled: Bool) -> Bool {
        guard enabled, !isWatching, duration >= max(0, threshold) else { return false }
        return !interactive.contains(programName(command))
    }

    /// "45s", "2m 13s", "1h 4m".
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// The notification's text.
    static func message(command: String, duration: TimeInterval, session: String) -> (title: String, body: String) {
        let name = programName(command)
        return ("\(name.isEmpty ? "Command" : name) finished", "\(session) · after \(durationText(duration))")
    }

    /// A session's tab label: the title the shell set, else "Terminal 2".
    static func tabTitle(_ title: String, index: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Terminal" { return index == 0 ? "Terminal" : "Terminal \(index + 1)" }
        return trimmed.count > 24 ? String(trimmed.prefix(23)) + "…" : trimmed
    }

    /// Terminal apps "Open in" can use: name and bundle id. Those with
    /// scripting open at the folder you're in.
    static let externalApps: [(name: String, bundleID: String)] = [
        ("iTerm2", "com.googlecode.iterm2"), ("Terminal", "com.apple.Terminal"), ("Ghostty", "com.mitchellh.ghostty"),
        ("Warp", "dev.warp.Warp-Stable"), ("WezTerm", "com.github.wez.wezterm"), ("Alacritty", "org.alacritty"),
        ("kitty", "net.kovidgoyal.kitty"), ("Hyper", "co.zeit.hyper"),
    ]

    /// AppleScript that opens a new window at `directory`, for the apps that can be told to.
    static func openScript(bundleID: String, directory: String) -> String? {
        let quoted = "'" + directory.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = ("cd " + quoted).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch bundleID {
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text "\(command)"
            end tell
            """
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
        default:
            return nil
        }
    }
}
