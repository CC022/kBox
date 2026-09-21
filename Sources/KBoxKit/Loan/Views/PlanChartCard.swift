import Charts
import SwiftUI

/// One plan as a Swift Charts stacked area, on axes shared with the other cards.
struct PlanChartCard: View {
    let plan: LoanPlan
    let summary: LoanSummary
    let series: PlanSeries
    let mode: ChartMode
    let xMax: Double
    let yMax: Double
    let yTicks: [Double]
    @Binding var hoverYear: Double?
    let isSelected: Bool
    let onLoad: () -> Void
    let onHide: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text("#\(plan.number)  ").foregroundStyle(.secondary) + Text(plan.displayName))
                        .font(.headline)
                        .lineLimit(1)
                    Text("总利息 \(Fmt.compactMoney(summary.totals[.interest] ?? 0)) · 总支付 \(Fmt.compactMoney(summary.totalPaid))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(mode == .monthly ? Fmt.money(summary.first.total) : Fmt.compactMoney(summary.totalPaid))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(mode == .monthly ? "/ 月" : "总计")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Reserved width keeps the header from shifting when the button fades in.
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除这个方案")
                .frame(width: 18)
                .opacity(isHovering || DebugOverrides.showCardActions ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            chart.frame(height: 220)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("载入到计算器", systemImage: "arrow.uturn.backward", action: onLoad)
            Button("在图表中隐藏", systemImage: "eye.slash", action: onHide)
            Divider()
            Button("删除方案", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series.plot) { point in
                AreaMark(
                    x: .value("年", point.x),
                    y: .value("金额", point.value),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("构成", point.component.label))
            }
            if let hoverYear {
                RuleMark(x: .value("年", hoverYear))
                    .foregroundStyle(Color.gray.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: hoverYear > xMax * 0.55 ? .leading : .trailing,
                        alignment: .top,
                        spacing: 8,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltip(at: hoverYear)
                    }
            }
        }
        .chartForegroundStyleScale(domain: Component.allCases.map(\.label), range: Component.allCases.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: .stride(by: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let year = value.as(Double.self) {
                        Text(year == 0 ? "0" : "\(Int(year))年")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: yTicks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount == 0 ? "$0" : Fmt.compactMoney(amount, maxFraction: 1))
                    }
                }
            }
        }
        .chartXSelection(value: $hoverYear)
    }

    private func tooltip(at x: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let k = series.index(nearest: x) {
                let values = series.values[k]
                Text(series.labels[k]).fontWeight(.semibold).foregroundStyle(.secondary)
                ForEach(Array(series.components.reversed())) { component in
                    let value = values[Component.allCases.firstIndex(of: component)!]
                    if value > 0 {
                        HStack(spacing: 6) {
                            Circle().fill(component.color).frame(width: 7, height: 7)
                            Text(component.label)
                            Spacer(minLength: 12)
                            Text(Fmt.money(value)).monospacedDigit()
                        }
                    }
                }
                Divider()
                HStack {
                    Text("合计")
                    Spacer()
                    Text(Fmt.money(values.reduce(0, +))).monospacedDigit()
                }
                .fontWeight(.semibold)
            } else {
                Text("第 \(min(Int(xMax), Int(x) + 1)) 年").fontWeight(.semibold).foregroundStyle(.secondary)
                Text(mode.endNote)
            }
        }
        .font(.caption)
        .padding(8)
        .frame(width: 186)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
