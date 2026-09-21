import SwiftUI

/// Parts of a monthly payment. Declaration order = chart stacking order, bottom → top.
public enum Component: String, CaseIterable, Identifiable, Sendable {
    case tax
    case insurance
    case hoa
    case principal
    case interest
    case pmi

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .tax: "房产税"
        case .insurance: "房屋保险"
        case .hoa: "HOA"
        case .principal: "本金"
        case .interest: "利息"
        case .pmi: "PMI"
        }
    }

    var color: Color {
        switch self {
        case .tax: .green
        case .insurance: .purple
        case .hoa: .teal
        case .principal: .blue
        case .interest: .orange
        case .pmi: .red
        }
    }
}
