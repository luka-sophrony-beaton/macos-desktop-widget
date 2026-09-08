# Gotchas — read before building

Ordered by how much time they cost. Each is a real failure we hit.

### 1. Widget won't appear in the gallery → it needs the App Sandbox
Symptom: `pluginkit -mAD | grep <APP>` shows nothing; the widget never appears in
*Edit Widgets*, even though the `.appex` is embedded and LaunchServices knows the
app. Cause: **macOS silently refuses to register a non-sandboxed widget
extension.** Fix: add `com.apple.security.app-sandbox = true` to the widget
extension's entitlements (and the app's).

### 2. "requires a provisioning profile" → it's App Groups, not the sandbox
Sandbox alone builds fine ad-hoc. The moment you add
`com.apple.security.application-groups`, the build fails with *"requires a
provisioning profile"* because App Groups is a capability that must be authorized
by a signing team (Apple ID). **Do not use App Groups** for a no-Apple-ID build.

### 3. Sandboxed app + widget can't see a shared file → temporary-exception
Under the sandbox, `FileManager.urls(for: .applicationSupportDirectory, ...)`
resolves to each target's *private container*, so the app and widget write to
different files and never share. Two-part fix:
- Entitlement (BOTH targets):
  `com.apple.security.temporary-exception.files.absolute-path.read-write` →
  `["/Users/<you>/Library/Application Support/<APP>/"]` (trailing slash).
- Code: compute the REAL path, not the sandbox one:
  ```swift
  let home = String(cString: getpwuid(getuid()).pointee.pw_dir)   // real ~, even in sandbox
  let dir = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/<APP>")
  ```
The exception path in the entitlements and the path in code must match exactly.
This path is hardcoded per-user; note it in the README and update on username change.

### 4. Xcode license / first-launch block builds → user must sudo
`xcodebuild` fails with a license or a missing `CoreSimulator.framework` /
"runFirstLaunch" error. These installs need admin auth — **you cannot** run them.
Ask the user to run `sudo xcodebuild -license accept` and
`sudo xcodebuild -runFirstLaunch` once.

### 5. Case-insensitive filesystem merges "MyWidget" and "mywidget"
macOS default FS is case-insensitive. A folder named `MyWidget` and an Electron
`userData` dir named `mywidget` are the SAME directory. Watch for accidental file
collisions when a lowercase and uppercase variant of the app name coexist.

### 6. +N button labels invisible on the desktop → vibrant rendering mode
Desktop widgets render in a *vibrant* material mode that flattens custom colors;
dark-button-with-tinted-text collapses and the text disappears (it looked fine in
Notification Center's full-color mode). Fix by branching on
`@Environment(\.widgetRenderingMode)`: in non-`.fullColor`, use `Color.primary`
for the label and a subtle `.primary.opacity(0.12)` fill + outline so the number
is the opaque hero.

### 7. Tapping the widget does nothing → needs widgetURL + registered scheme
Interactive widgets don't open the app on tap unless you set
`.widgetURL(URL(string:"<scheme>://open"))` AND register that scheme in the app's
`Info.plist` under `CFBundleURLTypes`. Verify with `open "<scheme>://open"`. Also
set `applicationShouldTerminateAfterLastWindowClosed → true` so a tap always
relaunches a fresh, visible window (closing the window otherwise leaves the app
running windowless and the next tap shows nothing).

### 8. Adding a model field wiped all saved data → synthesized Codable
Swift's synthesized `Codable` decoder THROWS on a missing key; it does NOT use the
property's default value. So loading an old JSON file after adding a field fails,
your `catch` returns defaults, and the next save overwrites the user's history
with an empty model. **Always** write a custom `init(from:)` using
`decodeIfPresent(...) ?? default` for every persisted field.

### 9. Duplicate registrations confuse chronod
Building into DerivedData AND copying to `/Applications` registers two copies of
the same bundle id. Unregister the stale build-folder copy
(`lsregister -u <path>`) and keep only `/Applications`, then `killall pkd chronod`.

### 10. Placed tiles cache old builds
After a rebuild, an already-placed desktop tile may keep showing the old render.
`killall chronod` usually refreshes it; if not, the user must Remove Widget and
re-add it from *Edit Widgets*.

### 11. You often can't see the screen
The user may decline screen-control. Verify everything from the CLI instead:
`pluginkit` for registration, `cat` the data file for persistence, `open
<scheme>://open` for tap-to-open, DiagnosticReports for crashes. Don't claim the
widget "works on the desktop" from a build success alone — verify the registration
and data-flow you actually can.

### 12. Tapping the widget's OWN button opens the app instead of running the
action in place → `.widgetURL` is scoped too wide
Symptom: the widget has a `Button(intent:)` (e.g. a +1 tap target) AND
`.widgetURL(...)` for tap-to-open, and tapping the *button* also opens the
app / shows the app's window instead of just running the `AppIntent` in
place. Cause: applying `.widgetURL()` to the whole container view (the same
`VStack` that holds the button) makes the entire tile one big tap target for
the URL, and on macOS desktop widgets this can win over the button
underneath instead of yielding to it. Fix: **never put `.widgetURL()` on
the root container that also holds an interactive button.** Instead wrap
only a specific non-button element — e.g. the title/header `Text` — in a
`Link(destination:)`:
```swift
VStack {
    Link(destination: URL(string: "<scheme>://open")!) {
        Text("...")   // tapping THIS opens the app
    }
    Button(intent: MyIntent()) { Text("+1") }   // tapping THIS stays on the desktop
}
.containerBackground(for: .widget) { ... }   // no .widgetURL here
```
Any interactive widget that has both a tappable button and a tap-to-open
target needs this scoping — it's not optional once both exist together.
