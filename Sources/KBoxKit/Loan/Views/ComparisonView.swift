import SwiftUI

/// Plan table + a grid of stacked-area charts that share axes and a hover crosshair.
struct ComparisonView: View {
    @Bindable var store: LoanStore
    @State private var hoverYear: Double? = DebugOverrides.hoverYear
    @State private var confirmingClear = false

    var body: some View {
        let visible = store.plans.filter(\.isVisible)
        let series = visible.map { store.series(for: $0, mode: store.chartMode) }
        let present = Component.allCases.filter { c in series.contains { $0.components.contains(c) } }
        let yScale = NiceScale.ticks(max: series.map(\.peak).max() ?? 0)
        let xMax = Double(max(15, visible.map(\.inputs.term.years).max() ?? 30))

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text("方案对比").font(.title2.weight(.semibold))
                if !store.plans.isEmpty {
                    Picker("图表模式", selection: $store.chartMode) {
                        ForEach(ChartMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                if !store.plans.isEmpty {
                    Button("全部清空", role: .destructive) { confirmingClear = true }
                }
            }

            if store.plans.isEmpty {
                ContentUnavailableView {
                    Label("还没有方案", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("调整左侧参数后点击「加入图表」（⌘↩），把当前方案加进来和其他方案对比。")
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            } else {
                PlanTable(store: store)
                    .frame(height: CGFloat(min(store.plans.count, 8)) * 24 + 50)

                if visible.isEmpty {
                    ContentUnavailableView("没有显示的方案", systemImage: "eye.slash",
                                           description: Text("在表格中勾选方案即可显示图表。"))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ChartLegend(components: present)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        ForEach(Array(zip(visible, series)), id: \.0.id) { plan, planSeries in
                            PlanChartCard(
                                plan: plan,
                                summary: store.data(for: plan.inputs).summary,
                                series: planSeries,
                                mode: store.chartMode,
                                xMax: xMax,
                                yMax: yScale.top,
                                yTicks: yScale.ticks,
                                hoverYear: $hoverYear,
                                isSelected: store.selectedPlanIDs.contains(plan.id),
                                onLoad: { store.load(plan) },
                                onHide: { store.setVisible(false, for: [plan.id]) },
                                onDelete: { store.removePlans([plan.id]) }
                            )
                        }
                    }
                    .animation(.smooth, value: visible.map(\.id))
                    .animation(.smooth, value: store.chartMode)
                }
            }
        }
        .confirmationDialog("删除全部 \(store.plans.count) 个方案？", isPresented: $confirmingClear) {
            Button("全部删除", role: .destructive) { store.removeAllPlans() }
        } message: {
            Text("此操作无法撤销。")
        }
    }
}

/// One shared legend instead of a legend under every chart.
struct ChartLegend: View {
    let components: [Component]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(components) { component in
                HStack(spacing: 5) {
                    Circle().fill(component.color).frame(width: 8, height: 8)
                    Text(component.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
