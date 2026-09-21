import Foundation

/// One month of the amortization schedule.
public struct MonthRow: Sendable, Equatable {
    public var month: Int
    public var tax: Double
    public var insurance: Double
    public var hoa: Double
    public var principal: Double
    public var interest: Double
    public var pmi: Double
    public var balance: Double

    public subscript(component: Component) -> Double {
        switch component {
        case .tax: tax
        case .insurance: insurance
        case .hoa: hoa
        case .principal: principal
        case .interest: interest
        case .pmi: pmi
        }
    }

    public var total: Double { Component.allCases.reduce(0) { $0 + self[$1] } }
    public var principalAndInterest: Double { principal + interest }

    static let zero = MonthRow(month: 0, tax: 0, insurance: 0, hoa: 0, principal: 0, interest: 0, pmi: 0, balance: 0)
}

public struct LoanSummary: Sendable, Equatable {
    public var loan: Double
    public var down: Double
    public var months: Int
    public var pmiMonths: Int
    public var first: MonthRow
    public var totals: [Component: Double]
    public var totalPaid: Double
}

/// Pure mortgage math — no UI.
public enum Mortgage {
    /// 2026 FHFA baseline conforming loan limit (one-unit).
    public static let conformingLimit: Double = 832_750

    public static func loanAmount(_ i: LoanInputs) -> Double {
        max(0, i.price * (1 - min(100, max(0, i.downPct)) / 100))
    }

    /// `.auto` resolved to conforming / jumbo by loan amount.
    public static func resolvedType(_ i: LoanInputs) -> LoanType {
        switch i.loanType {
        case .auto: loanAmount(i) > conformingLimit ? .jumbo : .conforming
        case let t: t
        }
    }

    /// Fixed-rate principal & interest payment.
    public static func monthlyPI(principal: Double, annualRate: Double, years: Int) -> Double {
        let n = Double(years * 12)
        guard principal > 0, n > 0 else { return 0 }
        let r = annualRate / 1200
        guard r > 0 else { return principal / n }
        return principal * r / (1 - pow(1 + r, -n))
    }

    /// Month-by-month schedule. PMI applies when the down payment is under 20% and stops once
    /// the balance reaches 78% of the original price (automatic termination).
    public static func amortize(_ i: LoanInputs) -> [MonthRow] {
        let principal0 = loanAmount(i)
        let n = i.term.years * 12
        guard n > 0 else { return [] }
        let r = max(0, i.rate) / 1200
        let payment = monthlyPI(principal: principal0, annualRate: i.rate, years: i.term.years)
        let tax = i.includeTaxes ? i.price * i.taxRate / 100 / 12 : 0
        let insurance = i.includeTaxes ? i.insurance / 12 : 0
        let hoa = i.includeTaxes ? i.hoa : 0
        let pmiOn = i.downPct < 20 && principal0 > 0 && i.pmiRate > 0
        let pmiMonthly = pmiOn ? principal0 * i.pmiRate / 1200 : 0
        let pmiStop = 0.78 * i.price

        var rows: [MonthRow] = []
        rows.reserveCapacity(n)
        var balance = principal0
        for month in 1...n {
            let interest = balance * r
            let principal = month == n ? balance : min(payment - interest, balance)
            let pmi = pmiOn && balance > pmiStop ? pmiMonthly : 0
            balance = max(0, balance - principal)
            rows.append(MonthRow(month: month, tax: tax, insurance: insurance, hoa: hoa,
                                 principal: principal, interest: interest, pmi: pmi, balance: balance))
        }
        return rows
    }

    public static func summarize(_ rows: [MonthRow], _ i: LoanInputs) -> LoanSummary {
        var totals = Dictionary(uniqueKeysWithValues: Component.allCases.map { ($0, 0.0) })
        for row in rows {
            for c in Component.allCases { totals[c, default: 0] += row[c] }
        }
        return LoanSummary(
            loan: loanAmount(i),
            down: i.downPayment,
            months: rows.count,
            pmiMonths: rows.filter { $0.pmi > 0 }.count,
            first: rows.first ?? .zero,
            totals: totals,
            totalPaid: totals.values.reduce(0, +)
        )
    }
}
