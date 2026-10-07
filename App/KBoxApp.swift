import KBoxKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct KBoxApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var loanStore = LaunchOptions.current.makeLoanStore()
    @State private var mailStore = MailStore()

    init() {
        LaunchOptions.current.applyDefaults()
    }

    var body: some Scene {
        #if os(macOS)
        Window("kBox", id: "main") {
            RootView(loanStore: loanStore, mailStore: mailStore)
                .frame(minWidth: 1000, minHeight: 640)
                .task { await DebugHooks.run(loanStore: loanStore, mailStore: mailStore) }
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
        #else
        WindowGroup {
            RootView(loanStore: loanStore, mailStore: mailStore)
                .task { await DebugHooks.openMailbox(mailStore) }
        }
        #endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable rather than from kBox.app.
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
#endif

/// Environment variables for checking the UI from the command line (debug builds only).
/// Not launch arguments: AppKit treats stray arguments as documents to open and then skips the main window.
///   KBOX_DEMO=1                preset plans, nothing read or saved
///   KBOX_APPEARANCE=dark|light force an appearance (macOS)
///   KBOX_FETCH=1               fetch live rates on launch
///   KBOX_CHART_MODE=monthly    start the demo in 月供构成 mode
///   KBOX_HOVER_YEAR=12         show the chart crosshair at year 12
///   KBOX_CARD_ACTIONS=1        show the per-card hover actions
///   KBOX_EXTRAS=1              turn on the extra-cost section in the demo
///   KBOX_SNAPSHOT=<file.png>   save the window to a PNG a few seconds after launch, then quit (macOS)
///   KBOX_SNAPSHOT_SIZE=WxH     resize the window before the snapshot (e.g. 1400x1500)
///   KBOX_TOOL=mail             start on this tool (not saved)
///   KBOX_MBOX=<file>           open this mailbox on launch (macOS and iOS)
///   KBOX_MAIL_SEARCH=<text>    …then search for this
///   KBOX_MAIL_SELECT=<n>       …then select the n-th message in the list (0 = first)
///   KBOX_MAIL_FOCUS_SEARCH=1   focus the mail search field (shows the search scopes)
///   KBOX_UI=<steps>            synthesize clicks and keys before the snapshot (macOS), see UIScript
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

    /// KBOX_TOOL goes in the argument domain, which outranks and never touches the saved selection.
    func applyDefaults() {
        #if DEBUG
        if let tool = ProcessInfo.processInfo.environment["KBOX_TOOL"] {
            UserDefaults.standard.setVolatileDomain(["selectedTool": tool], forName: UserDefaults.argumentDomain)
        }
        #endif
    }

    @MainActor
    func makeLoanStore() -> LoanStore {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        DebugOverrides.hoverYear = env["KBOX_HOVER_YEAR"].flatMap(Double.init)
        DebugOverrides.showCardActions = env["KBOX_CARD_ACTIONS"] == "1"
        DebugOverrides.focusMailSearch = env["KBOX_MAIL_FOCUS_SEARCH"] == "1"
        return demo ? .demo(chartMode: chartMode, extras: env["KBOX_EXTRAS"] == "1") : .live()
        #else
        return .live()
        #endif
    }
}

@MainActor
enum DebugHooks {
    static func openMailbox(_ store: MailStore) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let path = env["KBOX_MBOX"] else { return }
        store.open(URL(fileURLWithPath: path))
        while case .loading = store.phase { try? await Task.sleep(for: .milliseconds(50)) }
        if let search = env["KBOX_MAIL_SEARCH"] {
            store.searchText = search
            try? await Task.sleep(for: .milliseconds(500))
        }
        if let index = env["KBOX_MAIL_SELECT"].flatMap(Int.init), store.results.indices.contains(index) {
            store.selectedID = store.results[index].id
        }
        #endif
    }

    #if os(macOS)
    static func run(loanStore: LoanStore, mailStore: MailStore) async {
        #if DEBUG
        let options = LaunchOptions.current
        if options.fetch { await loanStore.fetchRates() }
        await openMailbox(mailStore)
        let env = ProcessInfo.processInfo.environment
        let script = env["KBOX_UI"]
        guard options.snapshot != nil || script != nil else { return }
        try? await Task.sleep(for: .seconds(1.5))
        if let size = env["KBOX_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }),
           size.count == 2, let window = NSApp.windows.first(where: \.isVisible) {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - size[1], width: size[0], height: size[1]), display: true)
        }
        if let script { await UIScript.run(script, mailStore: mailStore) }
        guard let path = options.snapshot else { return }
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
    #endif
}

#if os(macOS) && DEBUG
/// KBOX_UI: steps separated by ";", posted as real events so focus and key handling behave as with a person.
///   click:x,y   points from the window's top-left (the same as in a snapshot)
///   key:name    down, up, left, right, return, space, escape, tab, pageup, pagedown or a letter;
///               prefix cmd+ / shift+ / opt+ / ctrl+ for shortcuts (key:cmd+f)
///   wait:ms     pause
///   log         first responder (and where it is), tool and selected message, to stderr
@MainActor
enum UIScript {
    static func run(_ script: String, mailStore: MailStore) async {
        // A key press in the sidebar would save a different tool; put the saved one back afterwards.
        let domain = Bundle.main.bundleIdentifier ?? ""
        let savedTool = UserDefaults.standard.persistentDomain(forName: domain)?["selectedTool"]
        defer {
            var defaults = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            defaults["selectedTool"] = savedTool
            UserDefaults.standard.setPersistentDomain(defaults, forName: domain)
        }

        // Launched from a shell the app may not be frontmost, and a first click would only activate it.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))

        for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1] : ""
            switch parts.first ?? "" {
            case "click": click(argument, in: window)
            case "key": key(argument, in: window)
            case "wait": try? await Task.sleep(for: .milliseconds(Int(argument) ?? 300))
            case "log": log(window, mailStore: mailStore, savedToolDomain: domain)
            default: FileHandle.standardError.write(Data("UI: unknown step \(step)\n".utf8))
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func click(_ argument: String, in window: NSWindow) {
        let numbers = argument.split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 2 else { return }
        let location = NSPoint(x: numbers[0], y: window.frame.height - numbers[1])
        // Both go on the queue: a table's mouse-down runs a tracking loop that waits for the mouse-up.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static let specialKeys: [String: (code: UInt16, character: String)] = [
        "down": (125, "\u{F701}"), "up": (126, "\u{F700}"), "left": (123, "\u{F702}"), "right": (124, "\u{F703}"),
        "pageup": (116, "\u{F72C}"), "pagedown": (121, "\u{F72D}"),
        "return": (36, "\r"), "space": (49, " "), "escape": (53, "\u{1B}"), "tab": (48, "\t"),
    ]

    /// ANSI key codes; shortcuts are matched on characters, but AppKit expects a plausible code.
    private static let letterCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
    ]

    private static func key(_ argument: String, in window: NSWindow) {
        var names = argument.lowercased().split(separator: "+").map(String.init)
        guard let name = names.popLast() else { return }
        var flags: NSEvent.ModifierFlags = []
        for modifier in names {
            switch modifier {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt", "alt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        let code: UInt16, character: String
        if let special = specialKeys[name] {
            (code, character) = special
            if ["down", "up", "left", "right", "pageup", "pagedown"].contains(name) { flags.formUnion([.numericPad, .function]) }
        } else if let letter = name.first, name.count == 1, let letterCode = letterCodes[letter] {
            (code, character) = (letterCode, name)
        } else {
            FileHandle.standardError.write(Data("UI: unknown key \(argument)\n".utf8))
            return
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static func log(_ window: NSWindow, mailStore: MailStore, savedToolDomain domain: String) {
        let responder = window.firstResponder
        var place = ""
        if let view = responder as? NSView {
            let frame = view.convert(view.bounds, to: nil)
            place = " at x=\(Int(frame.minX)) w=\(Int(frame.width))"
        }
        let tool = UserDefaults.standard.persistentDomain(forName: domain)?["selectedTool"] ?? "-"
        let selected = mailStore.selectedSummary.map { "#\($0.id) \($0.subject)" } ?? "none"
        let line = "UI log: firstResponder=\(responder.map { String(describing: type(of: $0)) } ?? "nil")\(place)"
            + " savedTool=\(tool) selected=\(selected) active=\(NSApp.isActive) key=\(window.isKeyWindow)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
#endif
