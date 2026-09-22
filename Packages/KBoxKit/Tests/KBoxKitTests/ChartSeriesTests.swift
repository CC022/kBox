import Foundation
import Testing
@testable import KBoxKit

struct ChartSeriesTests {
    let inputs = LoanInputs()
    var rows: [MonthRow] { Mortgage.amortize(inputs) }

    @Test func cumulativeSeriesEndsAtTotalPaid() {
        let series = PlanSeries.build(rows: rows, mode: .cumulative)
        let summary = Mortgage.summarize(rows, inputs)
        #expect(series.xs.count == 361)
        #expect(series.values.first!.allSatisfy { $0 == 0 })
        #expect(abs(series.values.last!.reduce(0, +) - summary.totalPaid) < 0.01)
    }

    @Test func monthlySeriesClosesAtPayoff() {
        let series = PlanSeries.build(rows: rows, mode: .monthly)
        #expect(series.xs.count == 361)
        #expect(series.lastX == 30)
        #expect(series.labels.last == "第 30 年 12 月")
        #expect(series.components == [.tax, .insurance, .principal, .interest]) // no HOA, no PMI
    }

    @Test func extrasBecomeChartComponents() {
        var withExtras = inputs
        withExtras.includeExtras = true
        withExtras.specialTax = 3_600
        let series = PlanSeries.build(rows: Mortgage.amortize(withExtras), mode: .monthly)
        #expect(series.components == [.tax, .insurance, .specialTax, .maintenance, .principal, .interest])
        #expect(Set(series.plot.map(\.id)).count == series.plot.count) // ids stay unique
    }

    @Test func plotIsDownsampledEveryThreeMonths() {
        let series = PlanSeries.build(rows: rows, mode: .monthly)
        #expect(series.plot.count == 121 * 4)
        #expect(series.plot.last?.x == 30)
    }

    @Test func hoverPastPayoffHasNoPoint() {
        var fifteen = inputs
        fifteen.term = .fifteen
        let series = PlanSeries.build(rows: Mortgage.amortize(fifteen), mode: .monthly)
        #expect(series.index(nearest: 0.04) == 0)
        #expect(series.index(nearest: 15) == 180)
        #expect(series.index(nearest: 20) == nil)
    }

    @Test func niceScaleIsTight() {
        #expect(NiceScale.ticks(max: 20_142).top == 25_000)
        #expect(NiceScale.ticks(max: 20_142).ticks == [0, 5_000, 10_000, 15_000, 20_000, 25_000])
        #expect(NiceScale.ticks(max: 5_820_000).top == 6_000_000)
    }
}

@MainActor
struct LoanStoreTests {
    @Test func fetchedRateFollowsTermUntilEditedByHand() {
        let store = LoanStore.demo()
        store.update(\.term, .fifteen)
        #expect(store.inputs.rate == 6.427)
        store.setRate(6.5)
        store.update(\.term, .twenty)
        #expect(store.inputs.rate == 6.5)
        #expect(store.rateSource == .custom)
    }

    @Test func addingTheSamePlanTwiceKeepsOneCopy() {
        let store = LoanStore(persistence: nil)
        store.addPlan()
        store.setVisible(false, for: store.selectedPlanIDs)
        store.addPlan()
        #expect(store.plans.count == 1)
        #expect(store.plans[0].isVisible)
    }

    @Test func demoHasThreePlans() {
        #expect(LoanStore.demo().plans.map(\.inputs.term) == [.thirty, .twenty, .fifteen])
    }

    @Test func downPaymentAmountSetsPercentage() {
        let store = LoanStore(persistence: nil)
        store.downPaymentBinding.wrappedValue = 250_000
        #expect(store.inputs.downPct == 10)
    }

    @Test func loadingAPlanRestoresItsInputs() {
        let store = LoanStore.demo()
        let fifteen = store.plans[2]
        store.load(fifteen)
        #expect(store.inputs == fifteen.inputs)
        #expect(store.rateSource == .fetched)
    }

    @Test func plansPersistAcrossLaunches() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kbox-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LoanStore(persistence: JSONFileStore(url: url))
        store.update(\.price, 1_800_000)
        store.addPlan()
        try await Task.sleep(for: .milliseconds(600))
        let reloaded = LoanStore(persistence: JSONFileStore(url: url))
        #expect(reloaded.plans.count == 1)
        #expect(reloaded.inputs.price == 1_800_000)
    }
}
