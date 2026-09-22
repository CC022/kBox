import Charts
import SwiftUI

/// Monthly payment donut, breakdown, lifetime totals and the "加入图表" button.
struct PaymentSummaryView: View {
    let store: LoanStore
    @State private var angleSelection: Double?

    private struct Segment: Identifiable {
        let id: String
        let label: String
        let value: Double
        let color: Color
    }

    var body: some View {
        let summary = store.current.summary
        let first = summary.first
        let segments = ([
            Segment(id: "pi", label: "本金和利息", value: first.principalAndInterest, color: Component.principal.color)
        ] + [Component.tax, .insurance, .hoa, .specialTax, .earthquake, .maintenance, .utilities, .pmi].map {
            Segment(id: $0.rawValue, label: $0.label, value: first[$0], color: $0.color)
        }).filter { $0.value > 0 }
        let selected = selectedSegment(in: segments)

        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 24) {
                    donut(segments, total: first.total, selected: selected)
                        .frame(width: donutSize, height: donutSize)

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("预计月供").font(.headline)
                            Text("\(store.inputs.term.years) 年固定 · \(Fmt.rate(store.inputs.rate)) · \(store.resolvedType.label)贷款")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 0) {
                            ForEach(segments) { segment in
                                breakdownRow(segment, first: first)
                                if segment.id != segments.last?.id { Divider() }
                            }
                        }
                    }
                    .frame(maxWidth: 420)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12, alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    stat("贷款额", Fmt.money(summary.loan))
                    stat("首付", Fmt.money(summary.down))
                    if summary.closingCosts > 0 {
                        stat("成交费用", Fmt.money(summary.closingCosts))
                        stat("上车现金", Fmt.money(summary.cashToClose))
                    }
                    stat("总利息", Fmt.money(summary.totals[.interest] ?? 0))
                    stat("总支付", Fmt.money(summary.totalPaid))
                    stat("还清时间", Fmt.monthsFromNow(summary.months))
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    store.addPlan()
                } label: {
                    Label("加入图表", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(8)
        }
    }

    private var donutSize: CGFloat {
        #if os(macOS)
        180
        #else
        150
        #endif
    }

    private func donut(_ segments: [Segment], total: Double, selected: Segment?) -> some View {
        Chart(segments) { segment in
            SectorMark(angle: .value("金额", segment.value), innerRadius: .ratio(0.64), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(segment.color)
                .opacity(selected == nil || selected?.id == segment.id ? 1 : 0.35)
        }
        .chartAngleSelection(value: $angleSelection)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    VStack(spacing: 2) {
                        Text(Fmt.money(selected?.value ?? total))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(selected?.label ?? "每月")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .animation(.smooth, value: total)
    }

    private func breakdownRow(_ segment: Segment, first: MonthRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(segment.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(segment.label)
                if segment.id == "pi" {
                    Text("首月利息 \(Fmt.money(first.interest)) · 本金 \(Fmt.money(first.principal))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Fmt.money(segment.value))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Maps the angle selection (a cumulative value) back to its segment.
    private func selectedSegment(in segments: [Segment]) -> Segment? {
        guard let angleSelection else { return nil }
        var running = 0.0
        return segments.first { segment in
            running += segment.value
            return angleSelection <= running
        }
    }
}
