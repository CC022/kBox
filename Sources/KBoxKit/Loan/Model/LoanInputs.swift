import Foundation

public enum LoanTerm: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fifteen = 15
    case twenty = 20
    case thirty = 30

    public var id: Int { rawValue }
    public var years: Int { rawValue }
    var label: String { "\(rawValue) 年" }
}

public enum LoanType: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case conforming
    case jumbo

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "自动"
        case .conforming: "常规"
        case .jumbo: "巨额"
        }
    }
}

/// Everything the calculator needs. A plan is a frozen copy of this.
public struct LoanInputs: Codable, Hashable, Sendable {
    public var price: Double = 2_500_000
    public var downPct: Double = 20
    public var term: LoanTerm = .thirty
    public var rate: Double = 6.95
    public var loanType: LoanType = .auto
    public var includeTaxes = true
    public var taxRate: Double = 1.2
    public var insurance: Double = 3600 // per year
    public var hoa: Double = 0 // per month
    public var pmiRate: Double = 0.5
    /// Maintenance, earthquake insurance, special taxes, utilities and closing costs.
    public var includeExtras = false
    public var maintenanceRate: Double = 1.0 // % of price per year
    public var earthquakeInsurance: Double = 0 // per year
    public var specialTax: Double = 0 // Mello-Roos etc., per year
    public var utilities: Double = 0 // per month
    public var closingCostPct: Double = 2.0 // one-time, % of price

    public init() {}

    var downPayment: Double { price * downPct / 100 }

    // Tolerate files written by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LoanInputs()
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? d.price
        downPct = try c.decodeIfPresent(Double.self, forKey: .downPct) ?? d.downPct
        term = try c.decodeIfPresent(LoanTerm.self, forKey: .term) ?? d.term
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? d.rate
        loanType = try c.decodeIfPresent(LoanType.self, forKey: .loanType) ?? d.loanType
        includeTaxes = try c.decodeIfPresent(Bool.self, forKey: .includeTaxes) ?? d.includeTaxes
        taxRate = try c.decodeIfPresent(Double.self, forKey: .taxRate) ?? d.taxRate
        insurance = try c.decodeIfPresent(Double.self, forKey: .insurance) ?? d.insurance
        hoa = try c.decodeIfPresent(Double.self, forKey: .hoa) ?? d.hoa
        pmiRate = try c.decodeIfPresent(Double.self, forKey: .pmiRate) ?? d.pmiRate
        includeExtras = try c.decodeIfPresent(Bool.self, forKey: .includeExtras) ?? d.includeExtras
        maintenanceRate = try c.decodeIfPresent(Double.self, forKey: .maintenanceRate) ?? d.maintenanceRate
        earthquakeInsurance = try c.decodeIfPresent(Double.self, forKey: .earthquakeInsurance) ?? d.earthquakeInsurance
        specialTax = try c.decodeIfPresent(Double.self, forKey: .specialTax) ?? d.specialTax
        utilities = try c.decodeIfPresent(Double.self, forKey: .utilities) ?? d.utilities
        closingCostPct = try c.decodeIfPresent(Double.self, forKey: .closingCostPct) ?? d.closingCostPct
    }
}
