# Swift patterns

These patterns split into two kinds. The **skeleton** (file I/O, sandbox path
handling, reload-on-save, app lifecycle, vibrant-mode-aware rendering) is
mechanical and identical for every widget — copy it as-is. The **data model**
(what fields the widget actually stores and displays) is different for every
request — a word, a number, a streak, a stock price, a countdown, a list of
tasks, whatever the user asked for. Design that part fresh each time; don't
default to the streak/counter example below just because it's what's shown.

## Store.swift — the skeleton (universal, copy as-is)

The sandboxed-file-sharing mechanics never change regardless of what data
the widget holds:

```swift
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum Store {
    // REAL home via getpwuid — under sandbox the normal Application Support
    // API returns each target's private container, so app and widget would
    // otherwise write to two different files and never see each other's data.
    private static var fileURL: URL {
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let dir = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/<APP>", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }
    static func load() -> AppData {
        guard let d = try? Data(contentsOf: fileURL) else { return AppData() }
        return (try? JSONDecoder().decode(AppData.self, from: d)) ?? AppData()
    }
    static func save(_ m: AppData) {
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: fileURL, options: .atomic) }
        reload()
    }
    static func bootstrap() { save(load()) }   // call on app launch so the file exists
    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
```

`AppData` is the one thing that changes per widget — see below. Whatever
its shape, write it with a **custom `init(from:)`** using
`decodeIfPresent(...) ?? default` for every field (gotcha #8 — Swift's
synthesized decoder throws on a missing key instead of using the property
default, so adding a field later would silently wipe the user's saved data).

## Designing AppData for THIS widget

Ask: what does this specific widget need to display, and what (if anything)
does the user need to set from the companion app? Then shape `AppData`
around that — don't reuse fields from a different widget's model. A few
shapes, to show the range:

**Plain display widget** (e.g. shows a word, a name, a quote — nothing to
tap on the widget itself, all input happens in the app):
```swift
struct AppData: Codable {
    var text = ""
    init() {}
    init(text: String) { self.text = text }
    enum CodingKeys: String, CodingKey { case text }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}
```

**Counter/streak widget** (daily total, tappable +N buttons on the tile
itself, a goal, a running streak — this is the one pattern that needs an
`AppIntent`, see below):
```swift
struct DayRecord: Codable {
    var total = 0
    init(total: Int = 0) { self.total = total }
    enum CodingKeys: String, CodingKey { case total }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
    }
}
struct AppData: Codable {
    var dailyGoal = 100
    var days: [String: DayRecord] = [:]   // "yyyy-MM-dd" -> record
    init() {}
    enum CodingKeys: String, CodingKey { case dailyGoal, days }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 100
        days      = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
    }
}
// Streak helper, only relevant if the widget tracks one — grace day so an
// unfinished "today" doesn't zero it out:
extension Store {
    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func streak(_ m: AppData) -> Int {
        let goal = max(1, m.dailyGoal), cal = Calendar.current
        var cur = cal.startOfDay(for: Date())
        if (m.days[dayKey(cur)]?.total ?? 0) < goal { cur = cal.date(byAdding: .day, value: -1, to: cur)! }
        var n = 0
        while (m.days[dayKey(cur)]?.total ?? 0) >= goal { n += 1; cur = cal.date(byAdding: .day, value: -1, to: cur)! }
        return n
    }
    @discardableResult static func log(_ amount: Int) -> AppData {
        var m = load(); let k = dayKey(); var day = m.days[k] ?? DayRecord()
        day.total = max(0, day.total + amount); m.days[k] = day
        save(m); return m
    }
}
```

**Widget that mirrors external/fetched data** (weather, a stock price, a
calendar's next event): the app target fetches/refreshes the value (on
launch, on a timer, or on user action) and calls `Store.save`; the widget
just reads whatever `Store.load()` returns, same as any other shape. The
skeleton doesn't change — only what `AppData` holds and who writes to it.

Other shapes — a short list (tasks, a queue), a single number with no
history, a small enum/status — all follow the same rule: model exactly
what this widget needs, nothing inherited from a different one.

## LogIntent.swift — interactive button action (only if the widget has
tappable buttons; a plain display widget doesn't need this file at all)

```swift
import AppIntents
import WidgetKit

struct LogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log"
    @Parameter(title: "Amount") var amount: Int
    init() {}
    init(amount: Int) { self.amount = amount }
    func perform() async throws -> some IntentResult { Store.log(amount); return .result() }
}
```

## Widget — vibrant-aware rendering + widgetURL (universal — applies
whether the widget shows plain text or interactive buttons)

```swift
// Any text/label on the widget needs this fallback, not just buttons —
// desktop widgets render in a "vibrant" mode that flattens custom colors.
struct RepButton: View {
    @Environment(\.widgetRenderingMode) private var mode
    let amount: Int
    var body: some View {
        Button(intent: LogIntent(amount: amount)) {
            Text("+\(amount)").font(.system(size: 16, weight: .heavy))
                .foregroundStyle(mode == .fullColor ? Theme.accent : .primary)   // vibrant: use .primary
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(background)
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var background: some View {
        if mode == .fullColor {
            RoundedRectangle(cornerRadius: 7).fill(Theme.buttonFill)
        } else {
            RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.5), lineWidth: 1.2))
        }
    }
}

// On the entry view, regardless of what it displays:
//   .containerBackground(for: .widget) { Theme.backdrop }
//   .widgetURL(URL(string: "<scheme>://open"))   // tap opens the app

struct MyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyWidget", provider: Provider()) { entry in
            EntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

## App — quit on close so a widget tap relaunches a visible window
## (universal, copy as-is)

```swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.activate(ignoringOtherApps: true) }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() { Store.bootstrap() }
    var body: some Scene {
        WindowGroup("") {                                  // "" = no title text
            ContentView().onOpenURL { _ in NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
    }
}
```

Companion `ContentView` holds whatever this widget's `AppData` needs set —
a text field for a plain-display widget, a goal stepper and manual-log
field for a counter, nothing at all if the app only ever fetches external
data on its own. Widgets can't have text fields, so anything requiring
typing belongs in the app, not the tile.
