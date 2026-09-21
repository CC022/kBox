import Foundation

/// A frozen copy of the calculator inputs, shown in the comparison table and charts.
public struct LoanPlan: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var number: Int
    public var customName = ""
    public var isVisible = true
    public var inputs: LoanInputs
    public var rateNote: String
    public var createdAt = Date()

    public init(number: Int, inputs: LoanInputs, rateNote: String) {
        self.number = number
        self.inputs = inputs
        self.rateNote = rateNote
    }

    var autoName: String {
        "\(Fmt.compactMoney(inputs.price)) · \(inputs.term.years)年 · \(Fmt.rate(inputs.rate)) · 首付\(Fmt.percent(inputs.downPct))"
    }

    var displayName: String {
        customName.trimmingCharacters(in: .whitespaces).isEmpty ? autoName : customName
    }
}
