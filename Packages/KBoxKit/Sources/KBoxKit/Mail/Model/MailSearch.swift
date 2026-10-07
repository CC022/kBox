import Foundation

public enum MailSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, from, to, subject, body

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .from: "发件人"
        case .to: "收件人"
        case .subject: "主题"
        case .body: "正文"
        }
    }
}

/// Per-message text for searching, folded once when the mailbox is read.
struct SearchFields: Sendable {
    var subject: String
    var from: String
    var to: String
    var body: String

    /// Body text beyond this is not searched, so one huge message cannot blow up memory.
    static let bodyLimit = 50_000

    init(subject: String, from: String, to: String, body: String) {
        self.subject = MailSearch.fold(subject)
        self.from = MailSearch.fold(from)
        self.to = MailSearch.fold(to)
        self.body = MailSearch.fold(String(body.prefix(Self.bodyLimit)))
    }

    init(summary: MailSummary, body: String) {
        func describe(_ addresses: [MailAddress]) -> String {
            addresses.map { "\($0.name) \($0.email)" }.joined(separator: " ")
        }
        self.init(
            subject: summary.subject,
            from: summary.from.map { describe([$0]) } ?? "",
            to: describe(summary.to + summary.cc),
            body: body
        )
    }
}

enum MailSearch {
    static let foldingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// Case-, accent- and width-insensitive form, stored as native UTF-8 so `contains` can use memmem.
    static func fold(_ text: String) -> String {
        var folded = text.folding(options: foldingOptions, locale: nil)
        folded.makeContiguousUTF8()
        return folded
    }

    /// Words of the query as typed (for highlighting).
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A message matches when every word occurs somewhere in the scope.
    static func matches(_ fields: SearchFields, terms: [String], scope: MailSearchScope) -> Bool {
        terms.allSatisfy { term in
            switch scope {
            case .all:
                contains(fields.subject, term) || contains(fields.from, term)
                    || contains(fields.to, term) || contains(fields.body, term)
            case .from: contains(fields.from, term)
            case .to: contains(fields.to, term)
            case .subject: contains(fields.subject, term)
            case .body: contains(fields.body, term)
            }
        }
    }

    /// Byte search over folded UTF-8 text.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        let haystackCount = haystack.utf8.count, needleCount = needle.utf8.count
        guard needleCount > 0 else { return true }
        guard haystackCount >= needleCount else { return false }
        let found = haystack.utf8.withContiguousStorageIfAvailable { hay in
            needle.utf8.withContiguousStorageIfAvailable { word in
                memmem(hay.baseAddress, hay.count, word.baseAddress, word.count) != nil
            }
        }
        return found.flatMap { $0 } ?? haystack.contains(needle)
    }
}
