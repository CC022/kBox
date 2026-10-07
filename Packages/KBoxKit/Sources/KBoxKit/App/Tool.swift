import SwiftUI

/// Tool registry. To add a tool: add a case, fill in its metadata, and return its view in `RootView`.
public enum Tool: String, CaseIterable, Identifiable, Sendable {
    case loan
    case mail

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .loan: "贷款计算器"
        case .mail: "邮件查看器"
        }
    }

    var subtitle: String {
        switch self {
        case .loan: "月供、最新利率与多方案对比"
        case .mail: "打开 mbox 文件，浏览和搜索邮件"
        }
    }

    var symbol: String {
        switch self {
        case .loan: "house"
        case .mail: "envelope"
        }
    }

    var section: String {
        switch self {
        case .loan: "金融"
        case .mail: "文件"
        }
    }
}
