import Foundation

/// Turns a tab URL into the key used to decide whether two tabs are "the same page".
enum URLKey {
    static let emptyKey = "(empty tab)"

    /// Query parameters that only track where a click came from; dropped before comparing.
    private static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid",
        "igshid", "yclid", "_hsenc", "_hsmi", "ref_src", "si",
    ]

    static func isEmptyTab(_ url: String) -> Bool {
        url.isEmpty || url == "about:blank" || url.hasPrefix("favorites://")
            || url.hasPrefix("topsites://") || url.hasPrefix("bookmarks://")
    }

    /// A Google results page on any country domain (google.com, google.com.au, …).
    static func isGoogleSearch(_ url: String) -> Bool {
        guard let c = URLComponents(string: url), var host = c.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.hasPrefix("google.") && c.path == "/search"
    }

    static func key(for raw: String, ignoreFragment: Bool, ignoreQuery: Bool) -> String {
        if isEmptyTab(raw) { return emptyKey }
        guard var c = URLComponents(string: raw), let scheme = c.scheme?.lowercased() else { return raw }

        // http and https copies of a page count as the same page.
        c.scheme = scheme == "http" ? "https" : scheme
        if var host = c.host?.lowercased() {
            if host.hasPrefix("www.") { host.removeFirst(4) }
            c.host = host
        }
        if c.port == 443 || c.port == 80 { c.port = nil }

        var path = c.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        c.percentEncodedPath = path

        if ignoreQuery {
            c.percentEncodedQuery = nil
        } else if let items = c.percentEncodedQueryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingParams.contains(name)
            }
            c.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        }

        // Fragments like #/episode/x or #!/page are app routes, i.e. different pages, so they
        // stay even when anchors are ignored.
        if let f = c.fragment, f.isEmpty || (ignoreFragment && !f.contains("/") && !f.hasPrefix("!")) {
            c.fragment = nil
        }
        return c.string ?? raw
    }
}
