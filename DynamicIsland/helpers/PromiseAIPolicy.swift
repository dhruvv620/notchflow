// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// A message waiting to be checked for a promise by the AI.
struct PromiseAIMessage: Equatable, Sendable {
    let id: Int
    let text: String
    let fromMe: Bool
    let person: String
    /// The other side's message this one answers ("let's meet Friday 5 pm" for "ok bhai").
    var replyingTo: String? = nil
}

/// Promise detection in any language (English, Hindi, Gujarati, Marathi, and
/// mixes like Hinglish), with the user's AI provider. The local check picks
/// which messages are worth asking about, so small talk never leaves the Mac.
/// Foundation only, so Build.command can check it alone.
enum PromiseAIPolicy {
    // MARK: Worth asking?

    /// Words that often carry a commitment or a time, written in Latin letters.
    private static let latinMarkers: [String] = [
        // English
        "i'll", "ill", "i will", "will do", "gonna", "let me", "promise", "tomorrow", "tonight", "later", "by", "asap",
        // Hindi / Hinglish
        "karunga", "karungi", "karoonga", "kar dunga", "kar dungi", "kar deta", "kar deti", "kar leta", "kar leti",
        "dunga", "dungi", "doonga", "de dunga", "de dungi", "bhejta", "bhejti", "bhejunga", "bhejungi", "bhej dunga",
        "bhej dungi", "bhej deta", "bhej deti", "aaunga", "aaungi", "aunga", "aungi", "aata hu", "aati hu",
        "bataunga", "bataungi", "bata dunga", "bata dungi", "bata deta", "bata deti", "dekhta hu", "dekhti hu",
        "dekh leta", "dekh leti", "dekhunga", "dekhungi", "lunga", "lungi", "le aaunga", "milta hu", "milti hu",
        "milunga", "milungi", "call karta", "call karti", "phone karta", "phone karti", "pakka", "kal", "aaj",
        "raat", "shaam", "sham", "subah", "dopahar", "baad mein", "baad me", "baadme", "abhi", "thodi der",
        "ghante", "ghanta", "parso", "agle hafte", "hafte", "tak",
        // Gujarati / Gujlish
        "karish", "kari dais", "kari daish", "kari didhu", "moklish", "mokli dais", "mokli daish", "aapish",
        "aapi dais", "aavish", "avish", "kahish", "kai daish", "joish", "joi laish", "jaish", "malish", "phone karish",
        "kale", "kaale", "aaje", "aje", "raate", "saanje", "sanje", "savare", "pachhi", "pachi", "hamna", "hamnaj",
        "thodi vaar", "kalak", "kalake", "sudhi", "pakku",
        // Marathi
        "karen", "karto", "karte", "karin", "pathavto", "pathavte", "pathaven", "pathvin", "deto", "dete", "deyin",
        "yeto", "yete", "sangto", "sangte", "sangen", "baghto", "baghte", "udya", "udyaa", "ratri", "sandhyakali",
        "sakali", "nantar", "thodyavelat", "tasat", "paryant", "nakki",
        // Days and plans
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "weekend", "let's",
        "lets", "shall we", "how about", "chalo", "milte", "meet", "somvar", "mangalvar", "budhvar", "guruvar",
        "shukravar", "shanivar", "ravivar",
    ]

    /// The same, in Devanagari (Hindi, Marathi) and Gujarati script.
    private static let scriptMarkers: [String] = [
        // Hindi
        "करूंगा", "करूँगा", "करुंगा", "करूंगी", "करूँगी", "कर दूंगा", "कर दूँगा", "दूंगा", "दूँगा", "दूंगी", "दूँगी",
        "भेज", "बताऊंगा", "बताऊँगा", "आऊंगा", "आऊँगा", "देखता हूं", "देखता हूँ", "पक्का", "कल", "आज", "रात", "शाम",
        "सुबह", "बाद में", "अभी", "घंटे", "तक",
        // Marathi
        "करेन", "करतो", "करते", "पाठवतो", "पाठवते", "पाठवेन", "देतो", "देते", "सांगतो", "सांगते", "येतो", "येते",
        "उद्या", "नंतर", "रात्री", "संध्याकाळी", "सकाळी", "तासात", "पर्यंत", "नक्की",
        // Gujarati
        "કરીશ", "મોકલીશ", "આપીશ", "આવીશ", "કહીશ", "જોઈશ", "કરી દઈશ", "મોકલી દઈશ", "કાલે", "આજે", "રાત્રે",
        "સાંજે", "સવારે", "પછી", "હમણાં", "કલાક", "સુધી", "પાક્કું",
    ]

    /// Whether a message is worth asking the AI about: long enough, and with
    /// a word that suggests a commitment, a plan or a time.
    static func mightBePromise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...600).contains(trimmed.count), trimmed.contains(where: \.isLetter) else { return false }
        if scriptMarkers.contains(where: { trimmed.contains($0) }) { return true }
        let lower = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        let words = lower.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
        guard !words.isEmpty else { return false }
        let padded = " " + words.joined(separator: " ") + " "
        if latinMarkers.contains(where: { padded.contains(" \($0) ") }) { return true }
        // A clock time: "5pm", "5 pm", "17:30".
        return lower.range(of: #"\b\d{1,2}(:\d{2})?\s?(am|pm)\b|\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil
    }

    // MARK: Asking

    static let system = """
    You find promises in chat messages. Messages can be in English, Hindi, Gujarati or Marathi, in their own \
    script or in Latin letters, and often mix them with English (Hinglish, Gujlish). A promise is the writer \
    committing to do something, for example "main kal shaam tak bhej dunga", "kal call karti hu", \
    "હું સાંજે ફોન કરીશ", "hu kale moklish", "मी उद्या पाठवतो", "will send it tonight". Not promises: questions, \
    asking someone else to do something, vague plans, things already done, jokes, greetings.
    Answer with only a JSON array, one object per promise (an empty array if there are none):
    {"id": <message id>, "task": "<what will be done, in short English, starting with a verb>", \
    "due": "<YYYY-MM-DDTHH:MM in the local time given, or null if no time was said>"}
    A short yes ("ok", "okay bhai", "pakka", "haan chalo", "thik che", "ho nakki", "done") to a plan in the \
    message it answers is a promise too: the task is the plan ("Coffee with Rahul", "Call Riya"), due when the plan is.
    For a message from me, write the task as what I will do, naming the other person instead of "you" \
    ("Send Sam the deck"). For a message to me, write what they will do for me ("Send me the invoice").
    Vague times: morning 09:00, afternoon 15:00, evening or shaam/saanje/sandhyakali 19:00, \
    night or raat/raate/ratri 21:00, tomorrow (kal/kale/udya) with no time 10:00, "in a while" one hour from now.
    """

    static let dueFormat = "yyyy-MM-dd'T'HH:mm"

    static func userPrompt(_ messages: [PromiseAIMessage], now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE " + dueFormat
        var lines = ["Now: \(formatter.string(from: now)) (local time)", "", "Messages:"]
        for message in messages {
            let text = message.text.replacingOccurrences(of: "\n", with: " ").prefix(600)
            let who = message.fromMe ? "Me to \(name(message.person))" : "\(name(message.person)) to me"
            if let answered = message.replyingTo?.replacingOccurrences(of: "\n", with: " ").prefix(300) {
                lines.append("[\(message.id)] \(who), answering \u{201C}\(answered)\u{201D}: \(text)")
            } else {
                lines.append("[\(message.id)] \(who): \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func name(_ person: String) -> String {
        let trimmed = person.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "them" : trimmed
    }

    // MARK: Reading the answer

    /// The promises in the AI's answer, one per message at most.
    static func promises(fromAnswer text: String, messages: [PromiseAIMessage], now: Date,
                         calendar: Calendar = .current) -> [(messageID: Int, candidate: PromiseCandidate)] {
        guard let items = AIProviderPolicy.jsonPayload(in: text) as? [Any] else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dueFormat
        var found: [(messageID: Int, candidate: PromiseCandidate)] = []
        var seen = Set<Int>()
        for case let item as [String: Any] in items {
            let id = (item["id"] as? Int) ?? Int(item["id"] as? String ?? "")
            guard let id, !seen.contains(id), let message = messages.first(where: { $0.id == id }),
                  let rawTask = item["task"] as? String else { continue }
            let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            guard (2...120).contains(task.count) else { continue }
            var due = now.addingTimeInterval(86_400)
            var explicit = false
            if let dueText = item["due"] as? String, let parsed = formatter.date(from: String(dueText.prefix(16))) {
                // A time that already passed (a misread "kal" as yesterday) becomes an hour from now.
                due = parsed > now ? parsed : now.addingTimeInterval(3600)
                explicit = true
            }
            seen.insert(id)
            let title = task.prefix(1).uppercased() + task.dropFirst()
            // An agreed plan is on my calendar whoever proposed it.
            let kind: PromiseCandidate.Kind = message.fromMe || message.replyingTo != nil ? .mine : .theirs
            found.append((id, PromiseCandidate(kind: kind, title: title, due: due, hasExplicitTime: explicit)))
        }
        return found
    }
}
