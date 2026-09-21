import AppKit
import KBoxKit
import SwiftUI

@main
struct KBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var loanStore = LaunchOptions.current.makeLoanStore()

    var body: some Scene {
        Window("kBox", id: "main") {
            RootView(loanStore: loanStore)
                .frame(minWidth: 1000, minHeight: 640)
                .task { await DebugHooks.run(loanStore: loanStore) }
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from kBox.app.
        NSApp.setActivationPolicy(.regular)
        if let appearance = LaunchOptions.current.appearance {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Environment variables for checking the UI from the command line (debug builds only).
/// Not launch arguments: AppKit treats stray arguments as documents to open and then skips the main window.
///   KBOX_DEMO=1                preset plans, nothing read or saved
///   KBOX_APPEARANCE=dark|light force an appearance
///   KBOX_FETCH=1               fetch live rates on launch
///   KBOX_CHART_MODE=monthly    start the demo in 月供构成 mode
///   KBOX_HOVER_YEAR=12         show the chart crosshair at year 12
///   KBOX_CARD_ACTIONS=1        show the per-card hover actions
///   KBOX_SNAPSHOT=<file.png>   save the window to a PNG a few seconds after launch, then quit
///   KBOX_SNAPSHOT_SIZE=WxH     resize the window before the snapshot (e.g. 1400x1500)
struct LaunchOptions {
    var demo = false
    var appearance: String?
    var fetch = false
    var snapshot: String?
    var chartMode = ChartMode.cumulative

    static let current: LaunchOptions = {
        var options = LaunchOptions()
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        options.demo = env["KBOX_DEMO"] == "1"
        options.appearance = env["KBOX_APPEARANCE"]
        options.fetch = env["KBOX_FETCH"] == "1"
        options.snapshot = env["KBOX_SNAPSHOT"]
        options.chartMode = env["KBOX_CHART_MODE"].flatMap(ChartMode.init(rawValue:)) ?? .cumulative
        #endif
        return options
    }()

    @MainActor
    func makeLoanStore() -> LoanStore {
        #if DEBUG
        DebugOverrides.hoverYear = ProcessInfo.processInfo.environment["KBOX_HOVER_YEAR"].flatMap(Double.init)
        DebugOverrides.showCardActions = ProcessInfo.processInfo.environment["KBOX_CARD_ACTIONS"] == "1"
        #endif
        return demo ? .demo(chartMode: chartMode) : .live()
    }
}

@MainActor
enum DebugHooks {
    static func run(loanStore: LoanStore) async {
        #if DEBUG
        let options = LaunchOptions.current
        if options.fetch { await loanStore.fetchRates() }
        guard let path = options.snapshot else { return }
        try? await Task.sleep(for: .seconds(1.5))
        if let size = ProcessInfo.processInfo.environment["KBOX_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }),
           size.count == 2, let window = NSApp.windows.first(where: \.isVisible) {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - size[1], width: size[0], height: size[1]), display: true)
        }
        try? await Task.sleep(for: .seconds(1.5))
        guard let window = NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            let windows = NSApp.windows.map { "\($0.className) visible=\($0.isVisible) \($0.frame)" }
            FileHandle.standardError.write(Data("snapshot failed; windows: \(windows)\n".utf8))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        NSApp.terminate(nil)
        #endif
    }
}
