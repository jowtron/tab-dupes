import AppKit
import SwiftUI

@main
struct TabDupesApp: App {
    @State private var model = Model()

    var body: some Scene {
        Window("Tab Dupes", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 760, height: 640)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

struct ContentView: View {
    @Environment(Model.self) private var model
    @State private var confirmCloseAll = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.isSaved && model.error == nil {
                savedBanner
                Divider()
            }
            if model.error == nil {
                summary
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Toggle("Ignore #anchors (keeps #/app routes)", isOn: $model.ignoreFragment)
                    Toggle("Ignore ?query strings (loose: merges e.g. YouTube videos)", isOn: $model.ignoreQuery)
                    Toggle("Include empty / start page tabs", isOn: $model.includeEmptyTabs)
                    Divider()
                    Toggle("Exclude Google searches", isOn: $model.excludeGoogleSearches)
                } label: {
                    Label("Matching", systemImage: "slider.horizontal.3")
                }
                .help("How strictly URLs must match to count as duplicates")

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .help("Rescan Safari's tabs (⌘R)")

                Button {
                    confirmCloseAll = true
                } label: {
                    Label("Close All Duplicates", systemImage: "xmark.square")
                }
                .disabled(model.groups.isEmpty || model.isLoading || model.isSaved)
                .help(model.isSaved ? "Open Safari to close tabs" : "Close every duplicate, keeping one tab of each")
            }
        }
        .confirmationDialog(
            "Close \(model.extraCount) duplicate tab\(model.extraCount == 1 ? "" : "s")?",
            isPresented: $confirmCloseAll
        ) {
            Button("Close \(model.extraCount) Tabs", role: .destructive) {
                Task { await model.closeExtras(in: model.groups) }
            }
        } message: {
            Text("One tab from each group is kept. Closed tabs can be brought back from Safari's History menu.")
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { note in
            guard isSafari(note) else { return }
            Task {
                // Give Safari a moment to restore its windows before scanning them.
                try? await Task.sleep(for: .seconds(3))
                await model.refresh()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { note in
            guard isSafari(note) else { return }
            Task {
                // Safari writes its session on quit; wait for that before reading it.
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
    }

    private var savedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
            Text("Safari is closed. These are the tabs it will reopen next launch. Open Safari to close duplicates.")
                .font(.callout)
            Spacer()
            Button("Open Safari") { openSafari(then: model) }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            if model.error == nil {
                Text("\(model.tabs.count) tabs in \(model.windowCount) window\(model.windowCount == 1 ? "" : "s")")
                Text("·").foregroundStyle(.tertiary)
                Text(model.groups.isEmpty
                     ? "no duplicates"
                     : "\(model.groups.count) duplicated page\(model.groups.count == 1 ? "" : "s"), \(model.extraCount) extra tab\(model.extraCount == 1 ? "" : "s")")
                    .foregroundStyle(model.groups.isEmpty ? Color.secondary : Color.orange)
            }
            Spacer()
            if let status = model.status {
                Text(status).foregroundStyle(.secondary).lineLimit(1)
            }
            if !model.groups.isEmpty {
                if model.isSaved {
                    Button("Open Safari to Close Duplicates") { openSafari(then: model) }
                        .help("Tabs can only be closed while Safari is open")
                } else {
                    Button("Close \(model.extraCount) Duplicate\(model.extraCount == 1 ? "" : "s")") {
                        confirmCloseAll = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(model.isLoading)
                    .help("Close every duplicate, keeping the tab marked in each group")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error {
            ErrorView(error: error)
        } else if model.groups.isEmpty {
            ContentUnavailableView {
                Label(model.lastScan == nil ? "Scanning…" : "No duplicate tabs", systemImage: "checkmark.circle")
            } description: {
                if model.lastScan != nil {
                    Text(model.isSaved
                     ? "Every tab Safari will reopen is a different page."
                     : "Every open Safari tab is a different page.")
                }
            }
        } else {
            List {
                ForEach(model.groups) { group in
                    GroupSection(group: group)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
        }
    }
}

struct GroupSection: View {
    @Environment(Model.self) private var model
    let group: DuplicateGroup

    var body: some View {
        Section {
            ForEach(group.tabs) { tab in
                TabRow(tab: tab, isKept: model.keeper(of: group) == tab.id) {
                    model.keepers[group.key] = tab.id
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !group.isEmptyTabs {
                        Text(group.key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Text("×\(group.tabs.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Close \(group.tabs.count - 1)") {
                    Task { await model.closeExtras(in: [group]) }
                }
                .controlSize(.small)
                .disabled(model.isSaved)
                .help("Close every tab in this group except the one marked Keep")
            }
            .padding(.vertical, 4)
        }
    }
}

struct TabRow: View {
    @Environment(Model.self) private var model
    let tab: SafariTab
    let isKept: Bool
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onKeep) {
                Image(systemName: isKept ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isKept ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help(isKept ? "This tab will be kept" : "Keep this tab instead")

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title.isEmpty ? "Untitled" : tab.title)
                    .lineLimit(1)
                Text(tab.url.isEmpty ? "Empty tab" : tab.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .strikethrough(!isKept, color: .secondary.opacity(0.6))
            .opacity(isKept ? 1 : 0.75)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Window \(tab.windowNumber) · Tab \(tab.tabIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if tab.isCurrent {
                    Text("showing")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                Task { await model.reveal(tab) }
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .disabled(model.isSaved)
            .help("Show this tab in Safari")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !model.isSaved { Task { await model.reveal(tab) } }
        }
    }
}

struct ErrorView: View {
    @Environment(Model.self) private var model
    let error: SafariError

    var body: some View {
        ContentUnavailableView {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
        } description: {
            switch error {
            case .notRunning:
                Text("Open Safari, then refresh.")
            case .notAuthorized:
                Text("Allow it in System Settings › Privacy & Security › Automation, under Tab Dupes, by switching on Safari.")
            case .noDiskAccess:
                Text("To see the tabs Safari will reopen, add Tab Dupes under System Settings › Privacy & Security › Full Disk Access. Or just open Safari.")
            case .script:
                Text("Something went wrong reading Safari's tabs.")
            }
        } actions: {
            switch error {
            case .notRunning:
                Button("Open Safari") { openSafari(then: model) }
            case .notAuthorized:
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            case .noDiskAccess:
                Button("Open Full Disk Access Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                Button("Open Safari") { openSafari(then: model) }
            case .script:
                EmptyView()
            }
            Button("Try Again") { Task { await model.refresh() } }
        }
    }
}

@MainActor
func openSafari(then model: Model) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Safari.bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
        Task { @MainActor in
            // Give Safari a moment to restore its windows before scanning them.
            try? await Task.sleep(for: .seconds(2))
            await model.refresh()
        }
    }
}

private func isSafari(_ note: Notification) -> Bool {
    (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Safari.bundleID
}
