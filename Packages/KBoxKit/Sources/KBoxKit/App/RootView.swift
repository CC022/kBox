import SwiftUI

/// Sidebar of tools + the selected tool.
/// macOS: two columns (the tool's detail splits itself). iPadOS: three columns
/// (tools | form | charts), which collapses on its own in portrait and compact widths.
public struct RootView: View {
    let loanStore: LoanStore

    @AppStorage("selectedTool") private var selectedToolID = Tool.loan.id
    @State private var search = ""

    public init(loanStore: LoanStore) {
        self.loanStore = loanStore
    }

    public var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
        } detail: {
            switch selectedTool {
            case .loan?: LoanCalculatorView(store: loanStore)
            case nil: noSelection
            }
        }
        #else
        NavigationSplitView {
            sidebar
        } content: {
            switch selectedTool {
            case .loan?: LoanFormView(store: loanStore).navigationTitle("参数")
            case nil: noSelection
            }
        } detail: {
            switch selectedTool {
            case .loan?: LoanCanvasView(store: loanStore)
            case nil: noSelection
            }
        }
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.tools) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(tool)
                    }
                }
            }
        }
        .searchable(text: $search, placement: searchPlacement, prompt: "搜索工具")
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        #if os(iOS)
        .navigationTitle("kBox")
        #endif
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
    }

    private var noSelection: some View {
        ContentUnavailableView("选择一个工具", systemImage: "square.grid.2x2")
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .sidebar
        #else
        .automatic
        #endif
    }

    private var selectedTool: Tool? { Tool(rawValue: selectedToolID) }

    private var selection: Binding<Tool?> {
        Binding(
            get: { Tool(rawValue: selectedToolID) },
            set: { if let tool = $0 { selectedToolID = tool.id } }
        )
    }

    private var sections: [(title: String, tools: [Tool])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = Tool.allCases.filter {
            query.isEmpty || "\($0.title) \($0.subtitle) \($0.section)".lowercased().contains(query)
        }
        var result: [(title: String, tools: [Tool])] = []
        for tool in matching {
            if let i = result.firstIndex(where: { $0.title == tool.section }) {
                result[i].tools.append(tool)
            } else {
                result.append((tool.section, [tool]))
            }
        }
        return result
    }
}
