import Foundation
import SQLite3

/// Reads the tabs Safari will restore on next launch from its own SafariTabs.db, for when
/// Safari isn't running. The database lives in Safari's container, so this needs Full Disk Access.
enum SavedTabs {
    static let dbURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db")

    /// Each window's ordinary tabs live in a hidden "Local" folder (windows.local_tab_group_id);
    /// tabs are bookmarks rows of type 0 under it. The window's selected tab is in windows_tab_groups.
    private static let query = """
        SELECT w.id, b.order_index, b.url, b.title, (wtg.active_tab_id = b.id), b.extra_attributes
        FROM windows w
        JOIN bookmarks b ON b.parent = w.local_tab_group_id AND b.type = 0
        LEFT JOIN windows_tab_groups wtg ON wtg.window_id = w.id AND wtg.tab_group_id = w.local_tab_group_id
        WHERE w.date_closed IS NULL
        ORDER BY w.id, b.order_index
        """

    static func fetchTabs() throws -> [SafariTab] {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: dbURL.path) else { throw SafariError.noDiskAccess }

        // Work on a copy (with its WAL) so we never hold a lock on Safari's live database.
        let tmp = fm.temporaryDirectory.appendingPathComponent("TabDupes-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent("SafariTabs.db")
        do {
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: dbURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: URL(fileURLWithPath: copy.path + suffix))
            }
        } catch {
            throw SafariError.noDiskAccess
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw SafariError.script("Couldn't open Safari's tab database: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw SafariError.script("Safari's tab database isn't in the expected format: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(stmt) }

        var tabs: [SafariTab] = []
        var windowNumbers: [Int: Int] = [:]
        var nextIndex: [Int: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let windowID = Int(sqlite3_column_int64(stmt, 0))
            let number = windowNumbers[windowID] ?? (windowNumbers.count + 1)
            windowNumbers[windowID] = number
            let index = nextIndex[windowID, default: 0]
            nextIndex[windowID] = index + 1
            tabs.append(SafariTab(
                windowID: windowID,
                windowNumber: number,
                tabIndex: index,
                url: url(stmt),
                title: text(stmt, 3),
                isCurrent: sqlite3_column_int(stmt, 4) == 1
            ))
        }
        return tabs
    }

    /// Local file tabs have an empty url column; their address is LocalURL in extra_attributes.
    private static func url(_ stmt: OpaquePointer?) -> String {
        let url = text(stmt, 2)
        guard url.isEmpty, let blob = sqlite3_column_blob(stmt, 5) else { return url }
        let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 5)))
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?["LocalURL"] as? String ?? ""
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }
}
