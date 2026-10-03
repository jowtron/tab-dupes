# Tab Dupes

A small macOS app that finds duplicate tabs across all your Safari windows and closes the extras, keeping one of each.

## Build

```
./build.sh            # builds build/Tab Dupes.app
./build.sh --install  # also copies it to /Applications
```

Needs only the Command Line Tools (swiftc). Signs with the `Apple Development` identity if present (override with `CODESIGN_IDENTITY`), which keeps macOS permissions across rebuilds; otherwise ad-hoc.

The app icon is drawn in code by `icon/make-icon.swift` (1024px PNG in `icon/`); `build.sh` re-renders it when the script changes and cuts the `.icns` from it. To use a different image, replace `icon/AppIcon-1024.png` and rebuild.

## How it works

- **Safari running:** reads tabs live via JXA run through `/usr/bin/osascript` (`Sources/Safari.swift`). Needs Automation permission for Safari, which macOS asks for on first scan. Closing re-checks each tab's URL first and closes from the highest index down, so a tab that moved is skipped rather than closed by mistake.
- **Safari closed:** reads the tabs Safari will restore from a copy of `~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db` (`Sources/SavedTabs.swift`). Read-only. Needs Full Disk Access. Each window's tabs are `bookmarks` rows (type 0) under the folder in `windows.local_tab_group_id`; the selected tab is `windows_tab_groups.active_tab_id`. Undocumented schema, checked on macOS 26.6.
- **Matching** (`Sources/URLKey.swift`): http/https, `www.`, host case, trailing slashes and tracking params (`utm_*`, `fbclid`, `gclid`…) are ignored. `#anchors` and `?query` are compared unless switched off in the Matching menu. Even with anchors ignored, route-style fragments (`#/…`, `#!…`, anything containing `/`) are kept, since they're different pages in single-page apps. Google results pages are left out by default (toggle in the Matching menu). Empty and start-page tabs form their own group; a titled tab with no URL is never treated as a duplicate.
- **Local file tabs:** in `SafariTabs.db` their `url` column is empty and the address is `LocalURL` in the `extra_attributes` plist.
- **Which tab is kept:** the one currently showing in its window, else the frontmost. Click the circle on any row to keep that one instead.
