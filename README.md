# macos-desktop-widget

A [Claude Code](https://claude.com/claude-code) skill for building **real WidgetKit desktop
widgets** on macOS — the kind that shows up in the *Edit Widgets* gallery next to Apple's own
Calendar and Weather widgets — plus a small companion app, **without an Apple Developer
account**.

The value isn't the SwiftUI (that's easy). It's the handful of undocumented, hard-won gotchas
that stand between "widget code that compiles" and "widget that actually registers, shares
data, and renders correctly on the desktop." This skill encodes those so an agent (or you)
doesn't have to rediscover them.

## What it produces

- A macOS **app target** (a companion window — text input, steppers, whatever settings the
  widget needs) and a **widget extension target** (the desktop tile, with interactive
  AppIntent buttons if you want them).
- Data shared between the two via a **plain JSON file**, no App Groups.
- Built with **XcodeGen** → `.xcodeproj`, signed **ad-hoc** (no Apple ID, no provisioning
  profile), installed straight to `/Applications`, rebuildable with one script.

## The core trick

A macOS widget extension has to be **App-Sandboxed** to register with the system at all — but
the usual way two sandboxed targets share data (**App Groups**) is a signing *capability* that
forces you into a paid Apple Developer account and a provisioning profile.

The workaround: sandbox both targets, skip App Groups entirely, and instead grant both a
**temporary-exception entitlement** for one specific absolute path
(`com.apple.security.temporary-exception.files.absolute-path.read-write`). Read and write that
real path in code (via `getpwuid`, not the sandboxed Application Support URL), and both the app
and the widget see the same file. This is honored under ad-hoc signing — no team, no profile,
no Apple ID required.

See [`references/gotchas.md`](references/gotchas.md) for this and 10 other failure modes,
ordered by how much debugging time each one cost.

## Using this skill

Clone (or copy) this repo into your Claude Code skills directory:

```bash
git clone https://github.com/<you>/macos-desktop-widget.git ~/.claude/skills/macos-desktop-widget
```

Claude Code will pick it up automatically. Then just ask for a macOS widget — e.g.:

> "Make me a desktop widget that shows my daily step count with a companion app to set a goal."

Claude will read [`SKILL.md`](SKILL.md) first (the entry point — the non-negotiable facts,
prerequisites, and build workflow), then [`references/gotchas.md`](references/gotchas.md) and
[`references/patterns.md`](references/patterns.md) for the copy-paste Swift patterns, and
scaffold a new Xcode project using the templates in [`assets/`](assets/).

## Prerequisites (some steps need you — they need admin/password)

- **Full Xcode** (not just Command Line Tools) — `xcode-select -p` should point at
  `Xcode.app`. Install from the App Store if missing (~16 GB).
- Run once, with your password:
  ```bash
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ```
- **XcodeGen**: `brew install xcodegen`

## What's in this repo

```
SKILL.md                  # entry point Claude reads: facts, prerequisites, build workflow
references/
  gotchas.md               # 11 numbered failure modes, ordered by cost
  patterns.md               # copy-paste Swift: resilient Store, AppIntent, widget views, app delegate
assets/
  project.yml                # XcodeGen spec template ({{APP}} / {{BUNDLE}} placeholders)
  rebuild.sh                  # one-command ad-hoc build → install → register → launch
  entitlements.plist          # sandbox + temporary-exception template (same file, both targets)
  app-Info.plist               # registers the tap-to-open URL scheme
  widget-Info.plist            # widget extension point declaration
```

## Verifying a build worked

The agent (or you) often can't see the screen, so verify from the CLI:

```bash
# widget registered with the widget system?
pluginkit -mAD 2>/dev/null | grep -i <APP>

# shared data file actually written to the real path?
cat "<DATA_DIR>/<datafile>.json"

# tap-to-open works?
open "<SCHEME>://open"

# no crashes?
ls ~/Library/Logs/DiagnosticReports/ | grep -i <APP>
```

## License

[MIT](LICENSE)
