import SwiftUI

/// Parts of a monthly payment. Declaration order = chart stacking order, bottom → top.
public enum Component: String, CaseIterable, Identifiable, Sendable {
    case tax
    case insurance
    case hoa
    case specialTax
    case earthquake
    case maintenance
    case utilities
    case principal
    case interest
    case pmi

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .tax: "房产税"
        case .insurance: "房屋保险"
        case .hoa: "HOA"
        case .specialTax: "特别税"
        case .earthquake: "地震险"
        case .maintenance: "维护"
        case .utilities: "水电"
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
        case .specialTax: .indigo
        case .earthquake: .brown
        case .maintenance: .yellow
        case .utilities: .cyan
        case .principal: .blue
        case .interest: .orange
        case .pmi: .red
        }
    }
}
