import Foundation

/// Display formatting. Dollar amounts always use en_US grouping ($2,500,000) regardless of system locale.
enum Fmt {
    static let us = Locale(identifier: "en_US")

    /// Plain grouped number for input fields: 2,500,000
    static let wholeNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(us)
    /// Percent-style input fields: 20, 17.5, 1.25
    static let decimalNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3)).locale(us)
    /// Interest-rate input field: 6.95, 7.038
    static let rateNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2...3)).locale(us)

    /// $1,234 (whole dollars, never "-$0")
    static func money(_ value: Double) -> String {
        let rounded = value.rounded()
        return (rounded == 0 ? 0 : rounded)
            .formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(us))
    }

    /// $2.5M, $13.24K, $950
    static func compactMoney(_ value: Double, maxFraction: Int = 2) -> String {
        let magnitude = abs(value)
        let (divisor, suffix): (Double, String) =
            magnitude >= 1e9 ? (1e9, "B") : magnitude >= 1e6 ? (1e6, "M") : magnitude >= 1e3 ? (1e3, "K") : (1, "")
        let number = (magnitude / divisor).formatted(.number.precision(.fractionLength(0...maxFraction)).locale(us))
        return "\(value < 0 ? "-" : "")$\(number)\(suffix)"
    }

    /// 6.95%, 7.038%
    static func rate(_ value: Double) -> String {
        value.formatted(rateNumber) + "%"
    }

    /// 20%, 17.5%
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(us)) + "%"
    }

    /// "9/16" from "2026-09-16"
    static func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return iso }
        return "\(month)/\(day)"
    }

    /// Calendar month N months from now: "2056 年 9 月"
    static func monthsFromNow(_ months: Int, now: Date = .now) -> String {
        let date = Calendar.current.date(byAdding: .month, value: months, to: now) ?? now
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月"
    }

    private static let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]

    /// Message-list date, as Mail shows it: "21:21" today, "昨天", "星期一" within a week, else "2026/9/21".
    static func mailListDate(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        switch days {
        case 0: return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        case 1: return "昨天"
        case 2..<7: return weekdays[((parts.weekday ?? 1) - 1) % 7]
        default: return "\(parts.year ?? 0)/\(parts.month ?? 0)/\(parts.day ?? 0)"
        }
    }

    /// "2026年9月21日 星期一 21:21"
    static func mailFullDate(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日 \(weekdays[((parts.weekday ?? 1) - 1) % 7]) "
            + String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
