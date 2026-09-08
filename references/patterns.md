# Swift patterns

Generalized from the working MyWidget build. Replace `<APP>` and the data dir.

## Store.swift — resilient model, file I/O, stats, streak
```swift
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// Resilient Codable: custom init(from:) so adding fields never wipes saved data.
struct DayRecord: Codable {
    var total = 0
    var sets: [Int] = []
    init(total: Int = 0, sets: [Int] = []) { self.total = total; self.sets = sets }
    enum CodingKeys: String, CodingKey { case total, sets }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        sets  = try c.decodeIfPresent([Int].self, forKey: .sets) ?? []
    }
}

struct AppData: Codable {
    var dailyGoal = 100
    var label = ""
    var days: [String: DayRecord] = [:]   // "yyyy-MM-dd" -> record
    init() {}
    enum CodingKeys: String, CodingKey { case dailyGoal, label, days }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 100
        label     = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        days      = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
    }
}

enum Store {
    // REAL home via getpwuid — under sandbox the normal API returns the private container.
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
    }
    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    // Streak with a grace day: an unfinished today doesn't zero the streak.
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
        day.total = max(0, day.total + amount); day.sets.append(amount); m.days[k] = day
        save(m); reload(); return m
    }
    static func bootstrap() { save(load()); reload() }   // call on app launch so file exists
    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
```

## LogIntent.swift — interactive button action
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

## Widget — vibrant-aware button + widgetURL
```swift
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

// On the entry view:
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

Companion `ContentView` should include: a TextField for the widget label
(commit on `.onSubmit`), a `− [field] +` goal stepper, quick +N buttons, a manual
number field, and undo — everything that needs typing (widgets can't type).
