import SwiftUI

#if os(macOS)
/// macOS: form on the left, results and comparison canvas on the right, draggable divider between.
struct LoanCalculatorView: View {
    let store: LoanStore

    var body: some View {
        HSplitView {
            LoanFormView(store: store)
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 560)
            LoanCanvasView(store: store)
                .frame(minWidth: 520, maxWidth: .infinity)
        }
        .navigationTitle(Tool.loan.title)
        .navigationSubtitle(Tool.loan.subtitle)
    }
}

#Preview {
    LoanCalculatorView(store: .demo())
        .frame(width: 1200, height: 860)
}
#endif

/// Monthly payment summary + plan comparison. Its own column on iPadOS.
struct LoanCanvasView: View {
    let store: LoanStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PaymentSummaryView(store: store)
                ComparisonView(store: store)
            }
            .padding(canvasPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.canvasBackground)
        .loanToolbar(store: store)
        #if os(iOS)
        .navigationTitle(Tool.loan.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var canvasPadding: CGFloat {
        #if os(macOS)
        24
        #else
        20
        #endif
    }
}

extension View {
    /// 获取最新利率（⌘R）and 加入图表（⌘↩）, shown in the window / navigation bar.
    func loanToolbar(store: LoanStore) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.fetchRates() }
                } label: {
                    if store.isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("获取最新利率", systemImage: "arrow.clockwise")
                    }
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
