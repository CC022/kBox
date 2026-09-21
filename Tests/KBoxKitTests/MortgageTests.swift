import Foundation
import Testing
@testable import KBoxKit

struct MortgageTests {
    @Test func thirtyYearPrincipalAndInterest() {
        let payment = Mortgage.monthlyPI(principal: 2_000_000, annualRate: 6.95, years: 30)
        #expect(abs(payment - 13_238.96) < 0.01)
    }

    @Test func fifteenYearTotalMonthlyPayment() {
        var inputs = LoanInputs()
        inputs.term = .fifteen
        inputs.rate = 6.427
        let summary = Mortgage.summarize(Mortgage.amortize(inputs), inputs)
        #expect(abs(summary.first.total - 20_141.99) < 0.01) // P&I 17,341.99 + tax 2,500 + insurance 300
    }

    @Test func pmiAppliesUntilBalanceReaches78Percent() {
        var inputs = LoanInputs()
        inputs.downPct = 10
        inputs.rate = 7.038
        let summary = Mortgage.summarize(Mortgage.amortize(inputs), inputs)
        #expect(abs(summary.first.pmi - 937.5) < 0.001) // 2,250,000 × 0.5% / 12
        #expect(summary.pmiMonths == 116)
    }

    @Test func noPmiWithTwentyPercentDown() {
        let inputs = LoanInputs()
        #expect(Mortgage.summarize(Mortgage.amortize(inputs), inputs).pmiMonths == 0)
    }

    @Test func scheduleRepaysTheWholeLoan() {
        let inputs = LoanInputs()
        let rows = Mortgage.amortize(inputs)
        #expect(rows.count == 360)
        #expect(rows.last?.balance == 0)
        #expect(abs(rows.reduce(0) { $0 + $1.principal } - 2_000_000) < 0.01)
    }

    @Test func zeroRateSplitsPrincipalEvenly() {
        #expect(Mortgage.monthlyPI(principal: 1_200, annualRate: 0, years: 1) == 100)
    }

    @Test func taxesCanBeExcluded() {
        var inputs = LoanInputs()
        inputs.includeTaxes = false
        let first = Mortgage.amortize(inputs)[0]
        #expect(first.tax == 0 && first.insurance == 0 && first.hoa == 0)
    }

    @Test func extrasAreOffByDefault() {
        let inputs = LoanInputs()
        let summary = Mortgage.summarize(Mortgage.amortize(inputs), inputs)
        #expect(summary.closingCosts == 0)
        #expect(summary.cashToClose == 500_000)
        for component in [Component.maintenance, .earthquake, .specialTax, .utilities] {
            #expect(summary.totals[component] == 0)
        }
    }

    @Test func extrasAddToTheMonthlyPaymentAndCash() {
        var inputs = LoanInputs()
        inputs.rate = 6.95
        inputs.includeExtras = true          // maintenance 1%/yr, closing 2%
        inputs.earthquakeInsurance = 6_000   // $500/mo
        inputs.specialTax = 3_600            // $300/mo
        inputs.utilities = 400               // $400/mo
        let summary = Mortgage.summarize(Mortgage.amortize(inputs), inputs)
        let first = summary.first
        #expect(abs(first.maintenance - 2_083.33) < 0.01) // 2.5M × 1% / 12
        #expect(first.earthquake == 500)
        #expect(first.specialTax == 300)
        #expect(first.utilities == 400)
        // 13,238.96 P&I + 2,500 tax + 300 insurance + the four extras above
        #expect(abs(first.total - 19_322.29) < 0.01)
        #expect(summary.closingCosts == 50_000)
        #expect(summary.cashToClose == 550_000)
    }

    @Test func autoLoanTypeUsesConformingLimit() {
        var inputs = LoanInputs()
        #expect(Mortgage.resolvedType(inputs) == .jumbo) // $2M loan
        inputs.price = 1_000_000 // $800K loan
        #expect(Mortgage.resolvedType(inputs) == .conforming)
        inputs.loanType = .jumbo
        #expect(Mortgage.resolvedType(inputs) == .jumbo)
    }

    @Test func inputsDecodeWithMissingKeys() throws {
        let decoded = try JSONDecoder().decode(LoanInputs.self, from: Data(#"{"price": 900000}"#.utf8))
        #expect(decoded.price == 900_000)
        #expect(decoded.term == .thirty)
    }
}
