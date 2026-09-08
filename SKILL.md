---
name: macos-desktop-widget
description: >
  Build any native macOS desktop widget (WidgetKit) plus a companion app — a
  tile that lives on the desktop next to Apple's own widgets, optionally with
  interactive +N buttons, a streak/counter, plain text display, or whatever the
  user asks for, backed by a companion app for anything that needs typing.
  Crucially, it builds and installs with NO Apple ID (local ad-hoc signing +
  a sandbox temporary-exception for data sharing). Use whenever the user wants
  any macOS desktop widget — a habit/rep/counter tracker, a plain text/word
  display, a stat tile, or any other custom widget idea.
---

# Building a native macOS desktop widget

This skill reproduces a **real WidgetKit desktop widget** — the kind that appears
in the macOS *Edit Widgets* gallery and snaps onto the desktop next to Apple's
Calendar/Weather/Battery widgets — plus a small companion app. It was hard-won;
the value here is the **gotchas**, not the SwiftUI. Read `references/gotchas.md`
before doing anything, then follow the workflow. Copy-paste templates live in
`assets/`.

## What it produces
- A macOS **app target** (companion window: text input, steppers, settings — for
  anything that needs typing, since widgets can't have text fields) and a
  **widget extension target** (the desktop tile — plain display, or with
  interactive AppIntent buttons if the widget needs quick taps).
- Data shared via a **plain JSON file** in `~/Library/Application Support/<APP>/`.
- Built with **XcodeGen** → `.xcodeproj`, signed **ad-hoc** (no Apple ID), installed
  to `/Applications`, one-command rebuild via `rebuild.sh`.

## The non-negotiable facts (why this works without an Apple ID)
These are the load-bearing discoveries. Get them wrong and you waste hours.

1. **A macOS widget must be App-Sandboxed to register** with `pkd`/`chronod` and
   appear in the gallery. No sandbox → the extension is silently ignored.
2. **Sandbox alone does NOT require a provisioning profile.** Only *capability*
   entitlements do — chiefly **App Groups**. So DO NOT use App Groups (they force
   an Apple ID / signing team).
3. **To share data between the sandboxed app and widget without App Groups**, give
   BOTH targets a **temporary-exception** entitlement for one absolute path, and
   read/write that real path in code via `getpwuid` (under sandbox the normal
   Application Support URL points at each target's private container, so you must
   target the real home explicitly). This is honored under ad-hoc signing.
4. **Ad-hoc signing**: `CODE_SIGN_IDENTITY="-"`, `CODE_SIGN_STYLE=Manual`,
   `DEVELOPMENT_TEAM=""`. No profile, no team, no Apple ID.
5. **If the widget needs interactive buttons** (not every widget does): use
   `Button(intent:)` with an `AppIntent` (macOS 14+). The intent's `perform()`
   mutates the shared file and calls `WidgetCenter.shared.reloadAllTimelines()`.
   A plain read-only widget (e.g. just displaying text) doesn't need this at all.
6. **Desktop widgets render in a *vibrant* mode that flattens custom colors** — a
   dark button with tinted text becomes invisible. Read
   `@Environment(\.widgetRenderingMode)`; in non-`.fullColor` use `.primary` for
   text and a subtle outlined background so the label stays legible.
7. **Tap-to-open the app**: set `.widgetURL(URL(string:"<scheme>://open"))` on the
   widget AND register that URL scheme in the app's `Info.plist`
   (`CFBundleURLTypes`). Make the app quit on last-window-close so a tap always
   relaunches a fresh, visible window.
8. **Codable must be resilient** — write custom `init(from:)` using
   `decodeIfPresent(...) ?? default` for every field. Swift's *synthesized*
   decoder throws on a missing key instead of using the property default, so
   adding a new field to the model will **wipe the user's saved data**. This bit
   us once; never rely on synthesized decoding for the persisted model.
9. **Widgets can't have text fields.** Put quick actions (+N buttons, steppers) on
   the widget; put anything requiring typing (labels, exact numbers) in the app.

## Prerequisites (some steps need the USER — they need admin/password)
- **Full Xcode** (not just Command Line Tools). Check: `xcode-select -p` should be
  an `Xcode.app` path. If not installed, the user installs it from the App Store
  (~16 GB) — you cannot.
- The user must run, once (needs their password — you cannot):
  - `sudo xcodebuild -license accept`
  - `sudo xcodebuild -runFirstLaunch`
- **XcodeGen**: `brew install xcodegen` (you can do this).

## Build workflow
1. Scaffold the source tree (see Structure below) and copy `assets/project.yml`,
   `assets/rebuild.sh`, `assets/entitlements.plist` (into both `App/` and
   `Widget/`), `assets/widget-Info.plist`, `assets/app-Info.plist`. Replace the
   `{{APP}}`, `{{BUNDLE}}`, `{{SCHEME}}`, and `{{DATA_DIR}}` placeholders
   consistently (e.g. APP=MyWidget, BUNDLE=com.mywidget.MyWidget,
   SCHEME=mywidget, DATA_DIR=/Users/<you>/Library/Application Support/MyWidget/).
   The temporary-exception path in BOTH entitlements must equal DATA_DIR exactly.
2. Write the Swift using the patterns in `references/patterns.md` (store, theme,
   AppIntent, widget views, app views, app delegate).
3. `xcodegen generate`
4. Build/install/run: `./rebuild.sh` (ad-hoc). It builds both targets, copies the
   `.app` to `/Applications`, `lsregister`s it, bounces `pkd`+`chronod`, launches
   the app once (which registers the widget), and you then quit the app.
5. **Verify** (see Verification). Then the USER adds it: right-click desktop →
   *Edit Widgets* → search the app name → drag Small/Medium onto the desktop.
   (You cannot place it for them unless they grant screen control.)

## Structure
```
<APP>/
  project.yml                 # assets/project.yml
  rebuild.sh                  # assets/rebuild.sh
  App/
    <APP>App.swift            # @main App + AppDelegate (quit on close, onOpenURL)
    ContentView.swift         # companion UI: text input, steppers, log buttons
    <APP>.entitlements        # assets/entitlements.plist (sandbox + temp-exception)
    Info.plist                # assets/app-Info.plist (CFBundleURLTypes scheme)
  Widget/
    <APP>Widget.swift         # TimelineProvider + views (vibrant-aware buttons)
    <APP>WidgetBundle.swift   # @main WidgetBundle
    LogIntent.swift           # AppIntent for the +N buttons
    <APP>Widget.entitlements  # assets/entitlements.plist (same as app)
    Info.plist                # assets/widget-Info.plist (NSExtension widgetkit)
  Shared/
    Store.swift               # resilient Codable model + file I/O + stats/streak
    Theme.swift               # colors/fonts shared by app + widget
```

## Verification (do all of these — you usually can't see the screen)
```bash
# widget registered with the widget system?
pluginkit -mAD 2>/dev/null | grep -i <APP>            # expect the widget id
# shared data file actually written to the REAL path (proves temp-exception)?
cat "<DATA_DIR>/<datafile>.json"
# tap-to-open works?
open "<SCHEME>://open"                                # should launch the app
# no crashes?
ls ~/Library/Logs/DiagnosticReports/ | grep -i <APP>  # expect none
```
If `pluginkit` doesn't list it: confirm the sandbox entitlement is present, remove
duplicate `/Applications` vs build-folder registrations (`lsregister -u` the stale
one), then `killall pkd chronod`. If a *placed* tile shows stale content after a
rebuild, tell the user to Remove Widget → re-add.
