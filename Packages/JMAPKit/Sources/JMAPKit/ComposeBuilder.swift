import Foundation

public enum ComposeMode: String, Sendable, Hashable {
    case new, reply, replyAll, forward
}

/// The prefilled fields of the compose screen.
public struct ComposeSeed: Sendable, Equatable {
    public var to: [EmailAddress] = []
    public var cc: [EmailAddress] = []
    public var subject = ""
    public var body = ""
    public var inReplyTo: [String] = []
    public var references: [String] = []
    public var attachments: [EmailBodyPart] = []
}

public enum ComposeBuilder {
    /// Builds the reply, reply-all or forward fields from `original`. `myAddresses` are the account's identities, which are never replied to.
    public static func seed(mode: ComposeMode, original: Email?, myAddresses: [String], locale: Locale = .current) -> ComposeSeed {
        guard let original, mode != .new else { return ComposeSeed() }
        var seed = ComposeSeed()
        let mine = Set(myAddresses.map { $0.lowercased() })
        let sender = (original.replyTo?.isEmpty == false ? original.replyTo : original.from) ?? []
        let quoted = quote(original, locale: locale)

        switch mode {
        case .new:
            break
        case .reply, .replyAll:
            seed.subject = prefixed("Re:", original.subject)
            seed.inReplyTo = original.messageId ?? []
            seed.references = (original.references ?? []) + (original.messageId ?? [])
            seed.body = "\n\n" + quoted
            // A reply to a message I sent goes to its recipients instead.
            let fromMe = (original.from ?? []).contains { mine.contains($0.email.lowercased()) }
            seed.to = fromMe ? (original.to ?? []) : sender
            if mode == .replyAll {
                let taken = Set(seed.to.map { $0.email.lowercased() })
                seed.cc = unique(((original.to ?? []) + (original.cc ?? [])).filter { !mine.contains($0.email.lowercased()) && !taken.contains($0.email.lowercased()) })
            }
            let others = seed.to.filter { !mine.contains($0.email.lowercased()) }
            if !others.isEmpty { seed.to = others }
        case .forward:
            seed.subject = prefixed("Fwd:", original.subject)
            seed.attachments = original.fileAttachments
            seed.body = "\n\n---------- Forwarded message ----------\n" + header(original, locale: locale) + "\n" + original.bestPlainText
        }
        return seed
    }

    /// `Re: Re: x` stays `Re: x`.
    static func prefixed(_ prefix: String, _ subject: String?) -> String {
        let s = (subject ?? "").trimmingCharacters(in: .whitespaces)
        return s.lowercased().hasPrefix(prefix.lowercased()) ? s : "\(prefix) \(s)".trimmingCharacters(in: .whitespaces)
    }

    private static func unique(_ list: [EmailAddress]) -> [EmailAddress] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.email.lowercased()).inserted }
    }

    private static func dateString(_ date: Date?, locale: Locale) -> String {
        guard let date else { return "" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    private static func name(_ a: EmailAddress) -> String { a.name.map { $0.isEmpty ? a.email : "\($0) <\(a.email)>" } ?? a.email }

    private static func header(_ e: Email, locale: Locale) -> String {
        var lines = ["From: " + (e.from ?? []).map(name).joined(separator: ", ")]
        lines.append("Date: " + dateString(e.sentAt ?? e.receivedAt, locale: locale))
        lines.append("Subject: " + (e.subject ?? ""))
        lines.append("To: " + (e.to ?? []).map(name).joined(separator: ", "))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func quote(_ e: Email, locale: Locale) -> String {
        let who = e.from?.first.map { $0.displayName } ?? "the sender"
        let text = e.bestPlainText.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        return "On \(dateString(e.sentAt ?? e.receivedAt, locale: locale)), \(who) wrote:\n\(text)"
    }
}

extension Email {
    /// The plain-text body, or the HTML body with its tags stripped when the message has no text part.
    public var bestPlainText: String {
        let text = plainText
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        guard let html = htmlText else { return "" }
        var s = html.replacingOccurrences(of: #"(?is)<(style|script|head)\b.*?</\1>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</tr>|</li>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
