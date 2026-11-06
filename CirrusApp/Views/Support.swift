import SwiftUI
import JMAPKit

extension Color {
    /// `#RRGGBB` label colours from the server (`cirrusColor`).
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Mailbox {
    var symbolName: String {
        if isLabel { return "tag" }
        switch role {
        case "inbox": return "tray"
        case "drafts": return "doc"
        case "sent": return "paperplane"
        case "archive": return "archivebox"
        case "trash": return "trash"
        case "junk": return "xmark.bin"
        default: return name.lowercased() == "scheduled" ? "clock" : "folder"
        }
    }

    /// Drafts show how many exist; everything else shows unread threads.
    var badgeCount: Int { (role == "drafts" ? totalThreads : unreadThreads) ?? 0 }
}

extension Email {
    var senderName: String { from?.first?.displayName ?? "Unknown sender" }
    var displaySubject: String { (subject ?? "").isEmpty ? "(no subject)" : subject! }
}

extension Date {
    /// Time today, weekday this week, otherwise a short date.
    var listStamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if let days = cal.dateComponents([.day], from: self, to: .now).day, days < 6 { return formatted(.dateTime.weekday(.abbreviated)) }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Splits "Ada <ada@x.org>, bob@y.org" into addresses; entries without an @ are ignored.
func parseAddresses(_ text: String) -> [EmailAddress] {
    text.split(whereSeparator: { ",;\n".contains($0) }).compactMap { piece in
        let s = piece.trimmingCharacters(in: .whitespaces)
        if let open = s.lastIndex(of: "<"), let close = s.lastIndex(of: ">"), open < close {
            let email = String(s[s.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            let name = s[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return email.contains("@") ? EmailAddress(name: name.isEmpty ? nil : name, email: email) : nil
        }
        return s.contains("@") && !s.contains(" ") ? EmailAddress(email: s) : nil
    }
}

func formatAddresses(_ list: [EmailAddress]) -> String {
    list.map { a in a.name.flatMap { $0.isEmpty ? nil : "\($0) <\(a.email)>" } ?? a.email }.joined(separator: ", ")
}
