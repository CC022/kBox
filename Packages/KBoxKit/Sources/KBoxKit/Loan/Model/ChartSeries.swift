import Foundation

public enum ChartMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case monthly
    case cumulative

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: "月供构成"
        case .cumulative: "累计支付"
        }
    }

    var endNote: String {
        switch self {
        case .monthly: "贷款已还清"
        case .cumulative: "贷款已还清，累计金额不再增加"
        }
    }
}

public struct ChartPoint: Identifiable, Sendable {
    public let id: Int
    public let x: Double
    public let component: Component
    public let value: Double
}

/// A plan's stacked-area data: one point per month, x in years.
public struct PlanSeries: Sendable {
    public let xs: [Double]
    /// values[point][component], indexed like `Component.allCases`
    public let values: [[Double]]
    public let labels: [String]
    /// Components that are non-zero somewhere in this plan.
    public let components: [Component]
    /// Down-sampled marks for plotting (every 3 months plus the last point); tooltips use the full data.
    public let plot: [ChartPoint]

    init(xs: [Double], values: [[Double]], labels: [String], components: [Component]) {
        self.xs = xs
        self.values = values
        self.labels = labels
        self.components = components
        self.plot = Self.plotPoints(xs: xs, values: values, components: components, step: 3)
    }

    public var lastX: Double { xs.last ?? 0 }
    public var peak: Double { values.map { $0.reduce(0, +) }.max() ?? 0 }

    /// - monthly: point k covers month k+1; an extra closing point sits at the payoff date.
    /// - cumulative: point k is the running total after k payments (k = 0 is the start).
    public static func build(rows: [MonthRow], mode: ChartMode) -> PlanSeries {
        let n = rows.count
        guard n > 0 else { return PlanSeries(xs: [], values: [], labels: [], components: []) }
        var xs: [Double] = []
        var values: [[Double]] = []
        var labels: [String] = []
        xs.reserveCapacity(n + 1)
        values.reserveCapacity(n + 1)
        labels.reserveCapacity(n + 1)

        switch mode {
        case .monthly:
            for k in 0...n {
                let row = rows[min(k, n - 1)]
                xs.append(Double(k) / 12)
                values.append(Component.allCases.map { row[$0] })
                labels.append(yearMonth(min(k, n - 1) + 1))
            }
        case .cumulative:
            var running = Array(repeating: 0.0, count: Component.allCases.count)
            xs.append(0)
            values.append(running)
            labels.append("起始")
            for k in 1...n {
                for (i, c) in Component.allCases.enumerated() { running[i] += rows[k - 1][c] }
                xs.append(Double(k) / 12)
                values.append(running)
                labels.append("截至" + yearMonth(k))
            }
        }

        let components = Component.allCases.enumerated()
            .filter { i, _ in values.contains { $0[i] > 0 } }
            .map(\.element)
        return PlanSeries(xs: xs, values: values, labels: labels, components: components)
    }

    static func plotPoints(xs: [Double], values: [[Double]], components: [Component], step: Int) -> [ChartPoint] {
        guard !xs.isEmpty else { return [] }
        var indices = Array(Swift.stride(from: 0, to: xs.count, by: max(1, step)))
        if indices.last != xs.count - 1 { indices.append(xs.count - 1) }
        let componentIndex = Dictionary(uniqueKeysWithValues: Component.allCases.enumerated().map { ($0.element, $0.offset) })
        var points: [ChartPoint] = []
        points.reserveCapacity(indices.count * components.count)
        for k in indices {
            for c in components {
                let ci = componentIndex[c]!
                points.append(ChartPoint(id: k * Component.allCases.count + ci, x: xs[k], component: c, value: values[k][ci]))
            }
        }
        return points
    }

    /// Nearest point to x (years), or nil once x is past the payoff date.
    public func index(nearest x: Double) -> Int? {
        guard !xs.isEmpty, x <= lastX + 1.0 / 24 else { return nil }
        return min(xs.count - 1, max(0, Int((x * 12).rounded())))
    }

    static func yearMonth(_ month: Int) -> String {
        "第 \((month - 1) / 12 + 1) 年 \((month - 1) % 12 + 1) 月"
    }
}

enum NiceScale {
    /// Tightest 1/2/2.5/5 step that covers `max` in 3–6 intervals.
    static func ticks(max: Double) -> (top: Double, ticks: [Double]) {
        guard max > 0 else { return (1, [0, 1]) }
        var best: (step: Double, top: Double)?
        let e0 = Int(floor(log10(max)))
        for e in (e0 - 2)...(e0 + 1) {
            for m in [1, 2, 2.5, 5] {
                let step = m * pow(10, Double(e))
                let intervals = ceil(max / step - 1e-9)
                guard (3...6).contains(intervals) else { continue }
                let top = intervals * step
                if best == nil || top < best!.top || (top == best!.top && step > best!.step) {
                    best = (step, top)
                }
            }
        }
        guard let best else { return (max, [0, max]) }
        let ticks = Swift.stride(from: 0, through: best.top + best.step / 2, by: best.step)
            .map { ($0 * 1e6).rounded() / 1e6 }
        return (best.top, ticks)
    }
}
