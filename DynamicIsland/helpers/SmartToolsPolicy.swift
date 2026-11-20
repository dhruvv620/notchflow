// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

// Pure logic for the Smart Tools (Foundation only), so Build.command can
// check it alone: the distraction meter, copy-to-action, smart replies and
// the build watcher.

// MARK: - Distraction meter

enum FocusGuardPolicy {
    static let defaultSites = ["youtube.com", "x.com", "twitter.com", "instagram.com", "reddit.com",
                               "facebook.com", "tiktok.com", "netflix.com", "twitch.tv"]
    static let defaultApps = ["com.hnc.Discord", "com.tinyspeck.slackmacgap.games", "com.valvesoftware.steam", "tv.twitch.studio"]

    /// Splits a comma- or newline-separated list, lowercased and de-duplicated.
    static func list(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Whether a host is one of the sites or a subdomain of one ("m.youtube.com").
    static func isDistractingHost(_ host: String, sites: [String]) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return sites.contains { site in
            let site = site.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return host == site || host.hasSuffix("." + site)
        }
    }

    static func isDistracting(bundleID: String?, url: URL?, apps: [String], sites: [String]) -> Bool {
        if let bundleID, apps.contains(bundleID.lowercased()) { return true }
        if let host = url?.host { return isDistractingHost(host, sites: sites) }
        return false
    }

    /// "3 min off track", "45 s off track".
    static func offTrackLabel(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total < 60 ? "\(total)s off track" : "\(total / 60) min off track"
    }
}

// MARK: - Copy-to-action

enum CopyAction: Equatable, Sendable {
    case trackPackage(number: String, carrier: String, url: URL)
    case call(number: String)
    case email(address: String)
    case flight(code: String, url: URL)
    case calculate(expression: String, result: String)

    var title: String {
        switch self {
        case .trackPackage(_, let carrier, _): return carrier.isEmpty ? "Track package" : "Track \(carrier) package"
        case .call: return "Call"
        case .email: return "Email"
        case .flight(let code, _): return "Track flight \(code)"
        case .calculate(_, let result): return "= \(result)"
        }
    }

    var symbol: String {
        switch self {
        case .trackPackage: return "shippingbox.fill"
        case .call: return "phone.fill"
        case .email: return "envelope.fill"
        case .flight: return "airplane"
        case .calculate: return "equal.circle.fill"
        }
    }
}

enum CopyActionPolicy {
    /// Text worth looking at: short, single-purpose clipboard contents.
    static func candidate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return nil }
        return trimmed
    }

    static func detect(_ text: String) -> [CopyAction] {
        guard let text = candidate(text) else { return [] }
        var actions: [CopyAction] = []
        if let tracking = trackingNumber(in: text) { actions.append(tracking) }
        if let flight = flight(in: text) { actions.append(flight) }
        if let result = calculate(text) { actions.append(.calculate(expression: text, result: result)) }
        if let email = singleEmail(text) { actions.append(.email(address: email)) }
        if actions.isEmpty, let phone = phoneNumber(text) { actions.append(.call(number: phone)) }
        return actions
    }

    static func trackingNumber(in text: String) -> CopyAction? {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        func url(_ string: String) -> URL? { URL(string: string) }
        if compact.range(of: #"^1Z[0-9A-Z]{16}$"#, options: .regularExpression) != nil,
           let link = url("https://www.ups.com/track?tracknum=\(compact)") {
            return .trackPackage(number: compact, carrier: "UPS", url: link)
        }
        if compact.range(of: #"^TBA[0-9]{12}$"#, options: .regularExpression) != nil,
           let link = url("https://track.amazon.com/tracking/\(compact)") {
            return .trackPackage(number: compact, carrier: "Amazon", url: link)
        }
        if compact.range(of: #"^(94|93|92|95)[0-9]{18,20}$"#, options: .regularExpression) != nil,
           let link = url("https://tools.usps.com/go/TrackConfirmAction?tLabels=\(compact)") {
            return .trackPackage(number: compact, carrier: "USPS", url: link)
        }
        if compact.range(of: #"^[0-9]{12}$|^[0-9]{15}$"#, options: .regularExpression) != nil,
           let link = url("https://www.fedex.com/fedextrack/?trknbr=\(compact)") {
            return .trackPackage(number: compact, carrier: "FedEx", url: link)
        }
        if compact.range(of: #"^[A-Z]{2}[0-9]{9}[A-Z]{2}$"#, options: .regularExpression) != nil,
           let link = url("https://parcelsapp.com/en/tracking/\(compact)") {
            return .trackPackage(number: compact, carrier: "", url: link)
        }
        return nil
    }

    static func flight(in text: String) -> CopyAction? {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.range(of: #"^[A-Z][A-Z0-9][0-9]{1,4}$"#, options: .regularExpression) != nil,
              compact.prefix(2).contains(where: \.isLetter),
              let link = URL(string: "https://www.google.com/search?q=\(compact)+flight+status") else { return nil }
        return .flight(code: compact, url: link)
    }

    static func singleEmail(_ text: String) -> String? {
        text.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil ? text : nil
    }

    static func phoneNumber(_ text: String) -> String? {
        let allowed = Set("0123456789+()-. ")
        let digits = text.filter(\.isNumber)
        guard text.allSatisfy({ allowed.contains($0) }), (7...15).contains(digits.count),
              text.contains(where: { "+()- ".contains($0) }) || digits.count >= 10 else { return nil }
        return (text.hasPrefix("+") ? "+" : "") + digits
    }

    /// Evaluates + - * / ^ % and parentheses. Needs at least one operator, so a
    /// plain number is not "calculated"; returns nil on anything else.
    static func calculate(_ text: String) -> String? {
        let expression = text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
        guard expression.contains(where: { "+-*/^%".contains($0) }),
              expression.allSatisfy({ "0123456789.+-*/^%() ".contains($0) }),
              expression.contains(where: \.isNumber) else { return nil }
        var parser = ArithmeticParser(Array(expression.filter { $0 != " " }))
        guard let value = parser.parse(), parser.isAtEnd, value.isFinite else { return nil }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let formatted = String(format: "%.6f", value)
        return formatted.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

/// Recursive-descent arithmetic, no NSExpression (which raises on bad input).
private struct ArithmeticParser {
    let chars: [Character]
    var index = 0
    init(_ chars: [Character]) { self.chars = chars }
    var isAtEnd: Bool { index >= chars.count }

    mutating func parse() -> Double? { expression() }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while !isAtEnd, chars[index] == "+" || chars[index] == "-" {
            let op = chars[index]; index += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }
    private mutating func term() -> Double? {
        guard var value = power() else { return nil }
        while !isAtEnd, "*/%".contains(chars[index]) {
            let op = chars[index]; index += 1
            guard let rhs = power() else { return nil }
            switch op {
            case "*": value *= rhs
            case "/": guard rhs != 0 else { return nil }; value /= rhs
            default: guard rhs != 0 else { return nil }; value = value.truncatingRemainder(dividingBy: rhs)
            }
        }
        return value
    }
    private mutating func power() -> Double? {
        guard let base = unary() else { return nil }
        if !isAtEnd, chars[index] == "^" {
            index += 1
            guard let exponent = power() else { return nil }
            return pow(base, exponent)
        }
        return base
    }
    private mutating func unary() -> Double? {
        if !isAtEnd, chars[index] == "-" { index += 1; return unary().map { -$0 } }
        if !isAtEnd, chars[index] == "+" { index += 1; return unary() }
        return primary()
    }
    private mutating func primary() -> Double? {
        guard !isAtEnd else { return nil }
        if chars[index] == "(" {
            index += 1
            guard let value = expression(), !isAtEnd, chars[index] == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        while !isAtEnd, chars[index].isNumber || chars[index] == "." { index += 1 }
        guard index > start else { return nil }
        return Double(String(chars[start..<index]))
    }
}

// MARK: - Smart replies

enum SmartReplyPolicy {
    static func prompt(sender: String, message: String, context: [String]) -> (system: String, user: String) {
        let history = context.suffix(6).joined(separator: "\n")
        let system = """
        You suggest replies to a chat message. Answer with only a JSON array of exactly three short replies \
        (each under 10 words) from the perspective of the person replying. Match the message's language, script \
        and tone: Hinglish or Gujlish written in Latin letters stays in Latin letters, Hindi, Gujarati or Marathi \
        in their own script stays in that script, English stays English. No explanations.
        """
        var user = "Message from \(sender): \(message)"
        if !history.isEmpty { user = "Recent conversation:\n\(history)\n\n" + user }
        return (system, user)
    }

    /// Reads three suggestions from an OpenAI-style response, tolerating
    /// reasoning in `<think>` tags and replies given as lines instead of JSON.
    static func suggestions(fromResponse data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return [] }
        return suggestions(fromText: content)
    }

    static func suggestions(fromText raw: String) -> [String] {
        var text = raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
           let data = String(text[start...end]).data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let strings = array.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !strings.isEmpty { return Array(strings.prefix(3)) }
        }
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^([0-9]+[.)]|[-*•])\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }.filter { !$0.isEmpty && $0.count <= 120 }
        return Array(lines.prefix(3))
    }
}

// MARK: - Build watcher

struct WatchedRun: Equatable, Sendable, Identifiable {
    enum State: String, Sendable { case running, success, failure, cancelled }
    let id: String
    let title: String
    let detail: String
    let state: State
    let url: URL?
    let updatedAt: Date
}

enum BuildWatchPolicy {
    /// GitHub `GET /repos/{owner}/{repo}/actions/runs`.
    static func githubRuns(from data: Data, repository: String) -> [WatchedRun] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = object["workflow_runs"] as? [[String: Any]] else { return [] }
        return runs.compactMap { run in
            guard let id = run["id"] as? Int else { return nil }
            let status = run["status"] as? String ?? ""
            let conclusion = run["conclusion"] as? String
            let state: WatchedRun.State
            if status != "completed" { state = .running }
            else if conclusion == "success" { state = .success }
            else if conclusion == "cancelled" || conclusion == "skipped" { state = .cancelled }
            else { state = .failure }
            let name = run["name"] as? String ?? "Workflow"
            let branch = run["head_branch"] as? String ?? ""
            let updated = ISO8601DateFormatter().date(from: run["updated_at"] as? String ?? "") ?? Date.distantPast
            return WatchedRun(id: "gh-\(id)", title: name, detail: branch.isEmpty ? repository : "\(repository) · \(branch)",
                              state: state, url: (run["html_url"] as? String).flatMap(URL.init(string:)), updatedAt: updated)
        }
    }

    /// A job file written by the `nf` shell function.
    static func terminalJob(from data: Data, id: String) -> WatchedRun? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String else { return nil }
        let status = object["status"] as? String ?? "running"
        let code = object["code"] as? Int ?? 0
        let state: WatchedRun.State = status == "running" ? .running : (code == 0 ? .success : .failure)
        let ended = (object["ended"] as? Double) ?? (object["started"] as? Double) ?? 0
        return WatchedRun(id: "job-\(id)", title: name, detail: state == .failure ? "Exited with \(code)" : "Terminal",
                          state: state, url: nil, updatedAt: Date(timeIntervalSince1970: ended))
    }

    /// Runs that were running before and have finished now: the ones to announce.
    static func newlyFinished(previous: [WatchedRun], current: [WatchedRun]) -> [WatchedRun] {
        let wasRunning = Set(previous.filter { $0.state == .running }.map(\.id))
        return current.filter { $0.state != .running && wasRunning.contains($0.id) }
    }

    static func repositories(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil }
    }

    /// The shell function users add to ~/.zshrc: `nf <command>` runs the
    /// command and reports it to NotchFlow through a small JSON file.
    static let shellFunction = #"""
    nf() {
      local dir="$HOME/Library/Application Support/NotchFlow/Jobs"
      mkdir -p "$dir"
      local id="$(date +%s)-$$-$RANDOM"
      local name; name=$(printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g')
      local started; started=$(date +%s)
      printf '{"name":"%s","status":"running","started":%s}' "$name" "$started" > "$dir/$id.json"
      "$@"; local code=$?
      printf '{"name":"%s","status":"done","code":%s,"started":%s,"ended":%s}' "$name" "$code" "$started" "$(date +%s)" > "$dir/$id.json"
      return $code
    }
    """#
}
