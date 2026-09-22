import Observation
import SwiftUI

public enum RateSource: String, Codable, Sendable {
    case `default`
    case fetched
    case custom
}

public struct PlanData: Sendable {
    public let rows: [MonthRow]
    public let summary: LoanSummary
}

/// All state and behaviour of the loan calculator.
@MainActor @Observable
public final class LoanStore {
    public private(set) var inputs = LoanInputs()
    public private(set) var rateSource: RateSource = .default
    public private(set) var rates: MarketRates?
    public private(set) var isFetching = false
    public private(set) var fetchError: String?
    public private(set) var plans: [LoanPlan] = []
    public var chartMode: ChartMode = .cumulative {
        didSet { scheduleSave() }
    }
    public var selectedPlanIDs: Set<LoanPlan.ID> = []
    private var nextNumber = 1

    @ObservationIgnored private let persistence: JSONFileStore?
    @ObservationIgnored private let rateService: RateService
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dataCache: [LoanInputs: PlanData] = [:]
    @ObservationIgnored private var seriesCache: [SeriesKey: PlanSeries] = [:]

    private struct SeriesKey: Hashable {
        let inputs: LoanInputs
        let mode: ChartMode
    }

    private struct Snapshot: Codable {
        var inputs: LoanInputs
        var rateSource: RateSource
        var rates: MarketRates?
        var plans: [LoanPlan]
        var chartMode: ChartMode
        var nextNumber: Int
    }

    /// Pass `nil` persistence for a throwaway store (previews, demo, tests).
    public init(persistence: JSONFileStore?, rateService: RateService = RateService()) {
        self.persistence = persistence
        self.rateService = rateService
        if let snapshot = persistence?.load(Snapshot.self) {
            inputs = snapshot.inputs
            rateSource = snapshot.rateSource
            rates = snapshot.rates
            plans = snapshot.plans
            chartMode = snapshot.chartMode
            nextNumber = max(snapshot.nextNumber, (plans.map(\.number).max() ?? 0) + 1)
        }
    }

    public static func live() -> LoanStore {
        LoanStore(persistence: .appSupport("loan.json"))
    }

    /// Default inputs plus 30 / 20 / 15-year plans at the 2026-09-16 rates. Never saved.
    public static func demo(chartMode: ChartMode = .cumulative, extras: Bool = false) -> LoanStore {
        let store = LoanStore(persistence: nil)
        store.chartMode = chartMode
        store.rates = .sample
        store.rateSource = .fetched
        if extras {
            store.update(\.includeExtras, true)
            store.update(\.earthquakeInsurance, 6_000)
            store.update(\.specialTax, 3_600)
            store.update(\.utilities, 400)
        }
        for term in [LoanTerm.thirty, .twenty, .fifteen] {
            store.update(\.term, term)
            store.addPlan()
        }
        store.update(\.term, .thirty)
        store.selectedPlanIDs = []
        return store
    }

    // MARK: - Derived values

    public var current: PlanData { data(for: inputs) }
    public var resolvedType: LoanType { Mortgage.resolvedType(inputs) }

    public func data(for inputs: LoanInputs) -> PlanData {
        if let cached = dataCache[inputs] { return cached }
        let rows = Mortgage.amortize(inputs)
        let data = PlanData(rows: rows, summary: Mortgage.summarize(rows, inputs))
        if dataCache.count > 64 { dataCache.removeAll() }
        dataCache[inputs] = data
        return data
    }

    public func series(for plan: LoanPlan, mode: ChartMode) -> PlanSeries {
        let key = SeriesKey(inputs: plan.inputs, mode: mode)
        if let cached = seriesCache[key] { return cached }
        let series = PlanSeries.build(rows: data(for: plan.inputs).rows, mode: mode)
        if seriesCache.count > 64 { seriesCache.removeAll() }
        seriesCache[key] = series
        return series
    }

    /// "最新 · 巨额 30 年 · Optimal Blue 9/16" / "自定义利率" / "默认值 …"
    public var rateStatus: String {
        if rateSource == .fetched, let rates {
            let type = resolvedType
            let estimated = rates.rate(for: type, term: inputs.term)?.estimated == true
            return "最新 · \(type.label) \(inputs.term.years) 年\(estimated ? "（估算）" : "") · \(rates.source) \(Fmt.shortDate(rates.asOf))"
        }
        return rateSource == .custom ? "自定义利率" : "默认值 · 可获取最新市场利率"
    }

    // MARK: - Editing inputs

    public func binding<Value>(_ keyPath: WritableKeyPath<LoanInputs, Value> & Sendable) -> Binding<Value> {
        Binding(get: { self.inputs[keyPath: keyPath] }, set: { self.update(keyPath, $0) })
    }

    public var rateBinding: Binding<Double> {
        Binding(get: { self.inputs.rate }, set: { self.setRate($0) })
    }

    /// Down payment in dollars; edits it by adjusting the percentage.
    public var downPaymentBinding: Binding<Double> {
        Binding(
            get: { self.inputs.downPayment },
            set: { amount in
                let price = self.inputs.price
                self.update(\.downPct, price > 0 ? min(100, max(0, amount / price * 100)) : 0)
            }
        )
    }

    public func update<Value>(_ keyPath: WritableKeyPath<LoanInputs, Value>, _ value: Value) {
        var next = inputs
        next[keyPath: keyPath] = value
        apply(next)
    }

    public func setRate(_ rate: Double) {
        rateSource = .custom
        var next = inputs
        next.rate = rate
        apply(next)
    }

    /// While the rate comes from a fetch, it follows term / loan-type changes.
    private func apply(_ proposed: LoanInputs) {
        var next = proposed
        if rateSource == .fetched, let picked = rates?.rate(for: Mortgage.resolvedType(next), term: next.term) {
            next.rate = picked.rate
        }
        if next != inputs { inputs = next }
        scheduleSave()
    }

    // MARK: - Rates

    public func fetchRates() async {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        do {
            rates = try await rateService.fetch()
            rateSource = .fetched
            apply(inputs)
        } catch {
            fetchError = error.localizedDescription
        }
        isFetching = false
    }

    // MARK: - Plans

    /// Adds the current inputs as a plan. Re-adding an identical plan just re-shows and selects it.
    public func addPlan() {
        if let index = plans.firstIndex(where: { $0.inputs == inputs }) {
            plans[index].isVisible = true
            selectedPlanIDs = [plans[index].id]
        } else {
            let plan = LoanPlan(number: nextNumber, inputs: inputs, rateNote: rateStatus)
            nextNumber += 1
            plans.append(plan)
            selectedPlanIDs = [plan.id]
        }
        scheduleSave()
    }

    public func load(_ plan: LoanPlan) {
        inputs = plan.inputs
        let fetched = rates?.rate(for: Mortgage.resolvedType(plan.inputs), term: plan.inputs.term)?.rate
        rateSource = fetched == plan.inputs.rate ? .fetched : .custom
        scheduleSave()
    }

    public func removePlans(_ ids: Set<LoanPlan.ID>) {
        plans.removeAll { ids.contains($0.id) }
        selectedPlanIDs.subtract(ids)
        scheduleSave()
    }

    public func removeAllPlans() {
        removePlans(Set(plans.map(\.id)))
    }

    public func setVisible(_ visible: Bool, for ids: Set<LoanPlan.ID>) {
        for index in plans.indices where ids.contains(plans[index].id) {
            plans[index].isVisible = visible
        }
        scheduleSave()
    }

    public func visibilityBinding(_ id: LoanPlan.ID) -> Binding<Bool> {
        Binding(
            get: { self.plans.first { $0.id == id }?.isVisible ?? false },
            set: { self.setVisible($0, for: [id]) }
        )
    }

    /// Shows the display name; clearing the field (or typing the automatic name) reverts to it.
    public func nameBinding(_ id: LoanPlan.ID) -> Binding<String> {
        Binding(
            get: { self.plans.first { $0.id == id }?.displayName ?? "" },
            set: { name in
                guard let index = self.plans.firstIndex(where: { $0.id == id }) else { return }
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                self.plans[index].customName = trimmed == self.plans[index].autoName ? "" : trimmed
                self.scheduleSave()
            }
        )
    }

    // MARK: - Persistence

    private func scheduleSave() {
        guard let persistence else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let snapshot = Snapshot(inputs: inputs, rateSource: rateSource, rates: rates,
                                    plans: plans, chartMode: chartMode, nextNumber: nextNumber)
            try? persistence.save(snapshot)
        }
    }
}

extension MarketRates {
    /// Values fetched on 2026-09-16 — used by the demo store and previews.
    static let sample = MarketRates(
        asOf: "2026-09-16",
        source: "Optimal Blue",
        conforming: ["15": 6.436, "20": 6.64, "30": 7.047],
        jumbo: ["15": 6.427, "20": 6.631, "30": 7.038],
        estimated: ["conforming.20", "jumbo.15", "jumbo.20"],
        weekly: .init(asOf: "2026-09-17", rate30: 6.95, rate15: 6.26),
        fetchedAt: Date(timeIntervalSince1970: 1_789_700_000)
    )
}
