import SwiftUI

/// Form on the left, results and comparison canvas on the right, with a draggable divider.
struct LoanCalculatorView: View {
    let store: LoanStore

    var body: some View {
        HSplitView {
            LoanFormView(store: store)
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 560)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    PaymentSummaryView(store: store)
                    ComparisonView(store: store)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 520, maxWidth: .infinity)
        }
        .navigationTitle(Tool.loan.title)
        .navigationSubtitle(Tool.loan.subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.fetchRates() }
                } label: {
                    Label("获取最新利率", systemImage: "arrow.clockwise")
                }
                .help("从 FRED 获取最新按揭利率（⌘R）")
                .keyboardShortcut("r")
                .disabled(store.isFetching)

                Button {
                    store.addPlan()
                } label: {
                    Label("加入图表", systemImage: "chart.line.uptrend.xyaxis")
                }
                .help("把当前方案加入对比图表（⌘↩）")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

#Preview {
    LoanCalculatorView(store: .demo())
        .frame(width: 1200, height: 860)
}
