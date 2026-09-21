import SwiftUI

/// System Settings–style grouped form with every calculator input.
struct LoanFormView: View {
    let store: LoanStore

    var body: some View {
        let inputs = store.inputs
        let summary = store.current.summary

        Form {
            Section("房屋") {
                LabeledContent("房价") {
                    NumberField(value: store.binding(\.price), format: Fmt.wholeNumber, width: 110, prefix: "$")
                }
                Slider(value: priceSlider, in: 100_000...5_000_000) {
                    Text("房价")
                } minimumValueLabel: {
                    Text("$100K").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("$5M").font(.caption).foregroundStyle(.secondary)
                }
                .labelsHidden()
                LabeledContent {
                    HStack(spacing: 8) {
                        NumberField(value: store.downPaymentBinding, format: Fmt.wholeNumber, width: 96, prefix: "$")
                        NumberField(value: store.binding(\.downPct), format: Fmt.decimalNumber, width: 44, suffix: "%")
                    }
                } label: {
                    Text("首付")
                    Text(summary.loan > 0 ? "贷款额 \(Fmt.money(summary.loan))" : "全款购房")
                }
            }

            Section {
                Picker("期限", selection: store.binding(\.term)) {
                    ForEach(LoanTerm.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent {
                    HStack(spacing: 6) {
                        NumberField(value: store.rateBinding, format: Fmt.rateNumber, width: 54, suffix: "%")
                        Stepper("利率", value: store.rateBinding, in: 0...20, step: 0.125)
                            .labelsHidden()
                        Button {
                            Task { await store.fetchRates() }
                        } label: {
                            if store.isFetching {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("获取最新", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(store.isFetching)
                    }
                } label: {
                    Text("利率")
                    Text(store.rateStatus)
                }

                Picker(selection: store.binding(\.loanType)) {
                    ForEach(LoanType.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("贷款类型")
                    Text(loanTypeHint)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("贷款")
            } footer: {
                rateFooter.sectionFooterStyle()
            }

            Section {
                Toggle("包含房产税、保险与 HOA", isOn: store.binding(\.includeTaxes))
                Group {
                    LabeledContent {
                        NumberField(value: store.binding(\.taxRate), format: Fmt.decimalNumber, width: 48, suffix: "% / 年")
                    } label: {
                        Text("房产税")
                        Text("\(Fmt.money(inputs.price * inputs.taxRate / 1200)) / 月")
                    }
                    LabeledContent {
                        NumberField(value: store.binding(\.insurance), format: Fmt.wholeNumber, width: 70, prefix: "$", suffix: "/ 年")
                    } label: {
                        Text("房屋保险")
                        Text("\(Fmt.money(inputs.insurance / 12)) / 月")
                    }
                    LabeledContent {
                        NumberField(value: store.binding(\.hoa), format: Fmt.wholeNumber, width: 70, prefix: "$", suffix: "/ 月")
                    } label: {
                        Text("HOA")
                        Text(inputs.hoa > 0 ? "\(Fmt.money(inputs.hoa * 12)) / 年" : "无")
                    }
                }
                .disabled(!inputs.includeTaxes)
                LabeledContent {
                    NumberField(value: store.binding(\.pmiRate), format: Fmt.decimalNumber, width: 48, suffix: "% / 年")
                } label: {
                    Text("PMI")
                    Text(pmiHint(summary))
                }
            } header: {
                Text("税费与保险")
            } footer: {
                Text("首付低于 20% 时需缴纳 PMI（按贷款额计），余额降至房价 78% 时自动取消。")
                    .sectionFooterStyle()
            }
        }
        .formStyle(.grouped)
    }

    private var priceSlider: Binding<Double> {
        Binding(
            get: { min(max(store.inputs.price, 100_000), 5_000_000) },
            set: { store.update(\.price, ($0 / 10_000).rounded() * 10_000) }
        )
    }

    private var loanTypeHint: String {
        let type = store.resolvedType
        guard store.inputs.loanType == .auto else { return "手动选择 · 获取利率时使用\(type.label)利率" }
        return "\(type.label)（贷款额\(type == .jumbo ? "超过" : "未超过")上限 \(Fmt.money(Mortgage.conformingLimit))）"
    }

    private func pmiHint(_ summary: LoanSummary) -> String {
        if summary.pmiMonths > 0 {
            return "\(Fmt.money(summary.first.pmi)) / 月 · 持续 \((summary.pmiMonths + 11) / 12) 年"
        }
        return store.inputs.downPct >= 20 ? "首付 ≥ 20%，无需 PMI" : "无"
    }

    @ViewBuilder private var rateFooter: some View {
        if let error = store.fetchError {
            Text(error).foregroundStyle(Color.red)
        } else if let rates = store.rates {
            let reference = rates.weekly.map {
                "；参考 Freddie Mac 周度均值（\(Fmt.shortDate($0.asOf))）30 年 \(Fmt.rate($0.rate30)) · 15 年 \(Fmt.rate($0.rate15))"
            } ?? ""
            Text("利率来源 FRED：\(rates.source)\(reference)。20 年及巨额 15/20 年为按期限插值估算。")
        } else {
            Text("点击「获取最新」（⌘R）从 FRED 拉取当日按揭利率；也可以直接输入。")
        }
    }
}

extension View {
    func sectionFooterStyle() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Right-aligned numeric field with optional prefix/suffix. Commits on Return or focus change.
struct NumberField: View {
    @Binding var value: Double
    var format: FloatingPointFormatStyle<Double>
    var width: CGFloat
    var prefix: String?
    var suffix: String?

    var body: some View {
        HStack(spacing: 3) {
            if let prefix { Text(prefix).foregroundStyle(.secondary) }
            TextField("", value: $value, format: format)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
    }
}
