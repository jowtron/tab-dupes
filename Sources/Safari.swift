import AppKit
import Foundation

struct SafariTab: Identifiable, Hashable, Sendable {
    let windowID: Int
    let windowNumber: Int   // 1-based, front to back, for display
    let tabIndex: Int       // 0-based position within its window
    let url: String
    let title: String
    let isCurrent: Bool

    var id: String { "\(windowID)-\(tabIndex)" }
    var isEmpty: Bool { URLKey.isEmptyTab(url) }
}

enum SafariError: LocalizedError {
    case notRunning
    case notAuthorized
    case noDiskAccess
    case script(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "Safari isn't running."
        case .notAuthorized: "Tab Dupes isn't allowed to control Safari."
        case .noDiskAccess: "Safari is closed, and Tab Dupes can't read its saved tabs."
        case .script(let msg): msg
        }
    }
}

/// Talks to Safari via JXA run through /usr/bin/osascript. Running it as a child process keeps
/// the work off the main thread, and macOS attributes the Automation permission to this app.
enum Safari {
    static let bundleID = "com.apple.Safari"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static let listScript = """
    function run() {
      const s = Application('Safari');
      const out = [];
      const wins = s.windows();
      for (let i = 0; i < wins.length; i++) {
        const w = wins[i];
        try {
          const urls = w.tabs.url();
          const names = w.tabs.name();
          let cur = -1;
          try { cur = w.currentTab.index() - 1; } catch (e) {}
          out.push({ id: w.id(), urls: urls, names: names, cur: cur });
        } catch (e) { /* not a browser window, e.g. Settings */ }
      }
      return JSON.stringify(out);
    }
    """

    /// Closes tabs given as [{w: windowID, i: tabIndex, url}]. Each tab's URL is re-checked first
    /// so a tab that moved since the last scan is skipped rather than closed by mistake.
    private static let closeScript = """
    function run(argv) {
      const s = Application('Safari');
      const items = JSON.parse(argv[0]);
      let closed = 0, skipped = 0;
      for (const it of items) {
        try {
          const t = s.windows.byId(it.w).tabs[it.i];
          const u = t.url() || '';
          if (u === it.url) { t.close(); closed++; } else { skipped++; }
        } catch (e) { skipped++; }
      }
      return JSON.stringify({ closed: closed, skipped: skipped });
    }
    """

    private static let revealScript = """
    function run(argv) {
      const s = Application('Safari');
      const w = s.windows.byId(parseInt(argv[0]));
      w.currentTab = w.tabs[parseInt(argv[1])];
      w.index = 1;
      s.activate();
      return '';
    }
    """

    private struct RawWindow: Decodable {
        let id: Int
        let urls: [String?]
        let names: [String?]
        let cur: Int
    }

    private struct CloseResult: Decodable {
        let closed: Int
        let skipped: Int
    }

    static func fetchTabs() async throws -> [SafariTab] {
        guard isRunning else { throw SafariError.notRunning }
        let json = try await runJXA(listScript)
        let windows = try JSONDecoder().decode([RawWindow].self, from: Data(json.utf8))
        var tabs: [SafariTab] = []
        for (w, win) in windows.enumerated() {
            for i in win.urls.indices {
                tabs.append(SafariTab(
                    windowID: win.id,
                    windowNumber: w + 1,
                    tabIndex: i,
                    url: win.urls[i] ?? "",
                    title: (i < win.names.count ? win.names[i] : nil) ?? "",
                    isCurrent: i == win.cur
                ))
            }
        }
        return tabs
    }

    /// Returns (closed, skipped).
    static func close(_ tabs: [SafariTab]) async throws -> (Int, Int) {
        // Close from the highest index down within each window so earlier indices stay valid.
        let ordered = tabs.sorted { a, b in
            a.windowID != b.windowID ? a.windowID < b.windowID : a.tabIndex > b.tabIndex
        }
        let items = ordered.map { ["w": $0.windowID, "i": $0.tabIndex, "url": $0.url] as [String: Any] }
        let arg = String(decoding: try JSONSerialization.data(withJSONObject: items), as: UTF8.self)
        let json = try await runJXA(closeScript, args: [arg])
        let r = try JSONDecoder().decode(CloseResult.self, from: Data(json.utf8))
        return (r.closed, r.skipped)
    }

    static func reveal(_ tab: SafariTab) async throws {
        _ = try await runJXA(revealScript, args: [String(tab.windowID), String(tab.tabIndex)])
    }

    private static func runJXA(_ script: String, args: [String] = []) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-l", "JavaScript", "-e", script] + args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let stderr = String(decoding: errData, as: UTF8.self)
                if p.terminationStatus != 0 {
                    if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") {
                        cont.resume(throwing: SafariError.notAuthorized)
                    } else {
                        cont.resume(throwing: SafariError.script(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    return
                }
                cont.resume(returning: String(decoding: outData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
