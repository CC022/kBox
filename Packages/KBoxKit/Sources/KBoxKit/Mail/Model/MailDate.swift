import Foundation

/// RFC 5322 `Date:` values and mbox envelope dates (asctime, `Mon Sep 21 21:21:13 2026`).
/// Hand-rolled: tolerant of the variants real mail contains, and cheap enough to run on every message.
enum MailDate {
    static func parse(_ value: String) -> Date? {
        var day: Int?, month: Int?, year: Int?
        var hour = 0, minute = 0, second = 0
        var offset: Int?

        for token in tokens(stripComments(value)) {
            let lower = token.lowercased()
            // Zones first: "+08:00" and "GMT+08:00" contain a colon too.
            if let sign = token.first, sign == "+" || sign == "-" {
                if let seconds = offsetSeconds(token.dropFirst()) { offset = sign == "-" ? -seconds : seconds }
                continue
            }
            if lower.hasPrefix("gmt") || lower.hasPrefix("utc"), let sign = token.dropFirst(3).first, sign == "+" || sign == "-" {
                if let seconds = offsetSeconds(token.dropFirst(4)) { offset = sign == "-" ? -seconds : seconds }
                continue
            }
            if token.contains(":") {
                let parts = token.split(separator: ":").map { Int($0) }
                guard parts.count >= 2, let h = parts[0], let m = parts[1] else { continue }
                hour = h
                minute = m
                second = parts.count > 2 ? parts[2] ?? 0 : 0
            } else if let zone = zones[lower] {
                offset = offset ?? zone * 3600
            } else if let monthIndex = months.firstIndex(where: { lower.hasPrefix($0) }), lower.count >= 3 {
                month = monthIndex + 1
            } else if token.allSatisfy(\.isNumber), let number = Int(token) {
                if day == nil, token.count <= 2, (1...31).contains(number) {
                    day = number
                } else if year == nil {
                    year = token.count <= 2 ? (number < 50 ? 2000 + number : 1900 + number) : token.count == 3 ? 1900 + number : number
                }
            }
        }

        guard let day, let month, let year, (1900...2200).contains(year),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
        else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - (offset ?? 0)
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// `Received: from mx.example.com by …; Mon, 21 Sep 2026 21:21:13 -0700` → the date after the last ";".
    static func parseReceived(_ value: String) -> Date? {
        guard let semicolon = value.lastIndex(of: ";") else { return nil }
        return parse(String(value[value.index(after: semicolon)...]))
    }

    /// `From sender@example.com Mon Sep 21 21:21:13 2026` → the date after the sender.
    static func parseEnvelope(_ line: String) -> Date? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == "From" else { return nil }
        return parse(String(parts[2]))
    }

    // MARK: - Helpers

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Named zones that still show up (RFC 822 obsolete names plus a few common ones), in hours.
    private static let zones: [String: Int] = [
        "ut": 0, "utc": 0, "gmt": 0, "z": 0,
        "est": -5, "edt": -4, "cst": -6, "cdt": -5, "mst": -7, "mdt": -6, "pst": -8, "pdt": -7,
        "bst": 1, "cet": 1, "cest": 2, "jst": 9, "kst": 9, "hkt": 8, "sgt": 8,
    ]

    /// "0800", "08:00" or "8" (hours) after the sign.
    private static func offsetSeconds(_ digits: Substring) -> Int? {
        let plain = digits.replacingOccurrences(of: ":", with: "")
        guard !plain.isEmpty, plain.allSatisfy(\.isASCII), let number = Int(plain) else { return nil }
        let (hours, minutes) = plain.count <= 2 ? (number, 0) : (number / 100, number % 100)
        guard plain.count <= 4, hours <= 14, minutes < 60 else { return nil }
        return hours * 3600 + minutes * 60
    }

    private static func stripComments(_ value: String) -> String {
        var output = ""
        var depth = 0
        for character in value {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                output.append(character)
            }
        }
        return output
    }

    private static func tokens(_ value: String) -> [String] {
        value.split { $0.isWhitespace || $0 == "," }.map(String.init)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthIndex = (month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
