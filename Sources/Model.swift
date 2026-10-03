import Foundation
import Observation

struct DuplicateGroup: Identifiable {
    let key: String
    let tabs: [SafariTab]
    var id: String { key }
    var isEmptyTabs: Bool { key == URLKey.emptyKey }

    var title: String {
        if isEmptyTabs { return "Empty / start page tabs" }
        return tabs.first(where: { !$0.title.isEmpty })?.title ?? key
    }
}

@MainActor
@Observable
final class Model {
    var tabs: [SafariTab] = []
    var groups: [DuplicateGroup] = []
    var error: SafariError?
    var isLoading = false
    var lastScan: Date?
    var status: String?
    /// True when the tabs came from Safari's saved session because Safari wasn't running.
    var isSaved = false
    /// The tab chosen to survive in each group, keyed by group key.
    var keepers: [String: String] = [:]

    var ignoreFragment = UserDefaults.standard.bool(forKey: "ignoreFragment") {
        didSet { UserDefaults.standard.set(ignoreFragment, forKey: "ignoreFragment"); regroup() }
    }
    var ignoreQuery = UserDefaults.standard.bool(forKey: "ignoreQuery") {
        didSet { UserDefaults.standard.set(ignoreQuery, forKey: "ignoreQuery"); regroup() }
    }
    var includeEmptyTabs = UserDefaults.standard.object(forKey: "includeEmptyTabs") as? Bool ?? true {
        didSet { UserDefaults.standard.set(includeEmptyTabs, forKey: "includeEmptyTabs"); regroup() }
    }

    var excludeGoogleSearches = UserDefaults.standard.object(forKey: "excludeGoogleSearches") as? Bool ?? true {
        didSet { UserDefaults.standard.set(excludeGoogleSearches, forKey: "excludeGoogleSearches"); regroup() }
    }

    var windowCount: Int { Set(tabs.map(\.windowID)).count }
    var extraCount: Int { groups.reduce(0) { $0 + $1.tabs.count - 1 } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if Safari.isRunning {
                tabs = try await Safari.fetchTabs()
                isSaved = false
            } else {
                tabs = try await Task.detached { try SavedTabs.fetchTabs() }.value
                isSaved = true
            }
            error = nil
        } catch let e as SafariError {
            tabs = []
            error = e
        } catch {
            tabs = []
            self.error = .script(error.localizedDescription)
        }
        lastScan = Date()
        regroup()
    }

    private func regroup() {
        var buckets: [String: [SafariTab]] = [:]
        var order: [String] = []
        for tab in tabs {
            // A titled tab with no URL is something we can't identify, so never call it a duplicate.
            if tab.url.isEmpty && !tab.title.isEmpty { continue }
            let key = URLKey.key(for: tab.url, ignoreFragment: ignoreFragment, ignoreQuery: ignoreQuery)
            if key == URLKey.emptyKey && !includeEmptyTabs { continue }
            if excludeGoogleSearches && URLKey.isGoogleSearch(tab.url) { continue }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(tab)
        }
        groups = order.compactMap { key in
            guard let t = buckets[key], t.count > 1 else { return nil }
            return DuplicateGroup(key: key, tabs: t)
        }
        .sorted { $0.tabs.count != $1.tabs.count ? $0.tabs.count > $1.tabs.count : $0.title < $1.title }

        // Keep an existing choice if that tab is still in the group; otherwise prefer a tab
        // that's currently showing in its window, then the frontmost one.
        var next: [String: String] = [:]
        for g in groups {
            if let k = keepers[g.key], g.tabs.contains(where: { $0.id == k }) {
                next[g.key] = k
            } else {
                next[g.key] = (g.tabs.first(where: \.isCurrent) ?? g.tabs[0]).id
            }
        }
        keepers = next
    }

    func keeper(of group: DuplicateGroup) -> String? { keepers[group.key] }

    func extras(in group: DuplicateGroup) -> [SafariTab] {
        let keep = keepers[group.key]
        return group.tabs.filter { $0.id != keep }
    }

    func closeExtras(in groups: [DuplicateGroup]) async {
        let doomed = groups.flatMap { extras(in: $0) }
        guard !doomed.isEmpty else { return }
        do {
            let (closed, skipped) = try await Safari.close(doomed)
            status = "Closed \(closed) tab\(closed == 1 ? "" : "s")"
                + (skipped > 0 ? ", skipped \(skipped) that had changed since the last scan" : "")
        } catch {
            status = "Couldn't close tabs: \(error.localizedDescription)"
        }
        await refresh()
    }

    func reveal(_ tab: SafariTab) async {
        do { try await Safari.reveal(tab) } catch {
            status = "Couldn't switch to that tab, try Refresh"
        }
    }
}
