import SwiftUI

/// Native table of saved plans: checkbox to show in charts, inline rename, sortable numbers,
/// double-click to load into the calculator, context menu, Delete key.
struct PlanTable: View {
    @Bindable var store: LoanStore
    @State private var sortOrder = [KeyPathComparator(\Row.number)]

    struct Row: Identifiable {
        let id: LoanPlan.ID
        let number: Int
        let autoName: String
        let monthly: Double
        let interest: Double
        let totalPaid: Double
        let lowestMonthly: Bool
        let lowestInterest: Bool
    }

    var body: some View {
        Table(rows.sorted(using: sortOrder), selection: $store.selectedPlanIDs, sortOrder: $sortOrder) {
            TableColumn("显示") { row in
                VisibilityToggle(isOn: store.visibilityBinding(row.id))
            }
            .width(36)

            TableColumn("#", value: \.number) { row in
                Text("\(row.number)").foregroundStyle(.secondary).monospacedDigit()
            }
            .width(28)

            TableColumn("名称") { row in
                TextField(row.autoName, text: store.nameBinding(row.id))
                    .textFieldStyle(.plain)
                    .help(row.autoName)
            }
            .width(min: 140, ideal: 230)

            TableColumn("月供", value: \.monthly) { row in
                HStack(spacing: 4) {
                    Text(Fmt.money(row.monthly)).monospacedDigit()
                    if row.lowestMonthly { Badge(text: "最低", color: .blue) }
                }
            }
            .width(min: 96, ideal: 110)

            TableColumn("总利息", value: \.interest) { row in
                HStack(spacing: 4) {
                    Text(Fmt.compactMoney(row.interest)).monospacedDigit()
                    if row.lowestInterest { Badge(text: "最低", color: .green) }
                }
            }
            .width(min: 92, ideal: 100)

            // On iPad the columns would run past the edge; the chart cards show 总支付 anyway.
            #if os(macOS)
            TableColumn("总支付", value: \.totalPaid) { row in
                Text(Fmt.compactMoney(row.totalPaid)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            #endif
        }
        .contextMenu(forSelectionType: LoanPlan.ID.self) { ids in
            let chosen = store.plans.filter { ids.contains($0.id) }
            if chosen.count == 1, let plan = chosen.first {
                Button("载入到计算器", systemImage: "arrow.uturn.backward") { store.load(plan) }
            }
            if !chosen.isEmpty {
                let allVisible = chosen.allSatisfy(\.isVisible)
                Button(allVisible ? "在图表中隐藏" : "在图表中显示", systemImage: allVisible ? "eye.slash" : "eye") {
                    store.setVisible(!allVisible, for: ids)
                }
                Divider()
                Button("删除", systemImage: "trash", role: .destructive) { store.removePlans(ids) }
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            store.removePlans(store.selectedPlanIDs)
        }
        #endif
    }

    /// Row height + header, used to size the table inside the scrolling canvas.
    static func height(rows: Int) -> CGFloat {
        #if os(macOS)
        CGFloat(min(rows, 8)) * 24 + 50
        #else
        CGFloat(min(rows, 8)) * 44 + 60
        #endif
    }

    private var rows: [Row] {
        let summaries = Dictionary(uniqueKeysWithValues: store.plans.map { ($0.id, store.data(for: $0.inputs).summary) })
        let visible = store.plans.filter(\.isVisible)
        let lowestMonthly = visible.count > 1 ? visible.min { summaries[$0.id]!.first.total < summaries[$1.id]!.first.total }?.id : nil
        let interest = { (id: LoanPlan.ID) in summaries[id]?.totals[.interest] ?? 0 }
        let lowestInterest = visible.count > 1 ? visible.min { interest($0.id) < interest($1.id) }?.id : nil
        return store.plans.map { plan in
            let summary = summaries[plan.id]!
            return Row(
                id: plan.id,
                number: plan.number,
                autoName: plan.autoName,
                monthly: summary.first.total,
                interest: interest(plan.id),
                totalPaid: summary.totalPaid,
                lowestMonthly: plan.id == lowestMonthly,
                lowestInterest: plan.id == lowestInterest
            )
        }
    }
}

/// Checkbox on macOS; a tappable circle on touch, where a checkbox style does not exist.
private struct VisibilityToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        #if os(macOS)
        Toggle("显示", isOn: $isOn)
            .toggleStyle(.checkbox)
            .labelsHidden()
        #else
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "在图表中隐藏" : "在图表中显示")
        #endif
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
