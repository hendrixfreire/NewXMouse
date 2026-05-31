# New X Mouse

A macOS menu bar utility that remaps mouse buttons to configurable actions on a per-application basis.

Map your mouse side buttons to different keyboard shortcuts depending on which app is in focus — back/forward in your browser, copy/paste in your editor, or anything else you want.

## Features

- **Per-app remapping** — Different button mappings for every application
- **Default fallback profile** — Global mappings when no app-specific profile exists
- **Multiple action types**
  - Keyboard shortcuts (with modifiers)
  - Key sequences (multi-step macros)
  - Mouse button remapping & double-click
  - Application launch
  - Shell command execution
- **Quick presets** — Mission Control, App Exposé, Spotlight, Volume, Zoom, and more
- **Scroll wheel remapping** — Remap scroll up/down to any action
- **Key recorder** — Record custom shortcuts and sequences by pressing keys
- **Built-in diagnostics** — Button capture test, permission status, event log
- **Zero dependencies** — Pure Swift + macOS SDK

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (prompted on first launch)
- Input Monitoring permission (prompted on first launch)

## Installation

### Download

Download the latest release from the [Releases page](../../releases).

### Build from Source

```bash
git clone https://github.com/hendrixfreire/new-x-mouse.git
cd new-x-mouse
open NewXMouse.xcodeproj
```

Then build and run in Xcode (Cmd+R).

> **Note:** The app cannot run in the Xcode Simulator. It must run on a real Mac with Accessibility permissions granted.

### Permissions

On first launch, macOS will prompt you to grant:

1. **Accessibility** — Required to intercept mouse events
2. **Input Monitoring** — Required to read input events

Both can be granted in **System Settings → Privacy & Security → Accessibility** and **Input Monitoring**.

## Usage

### Menu Bar

The app lives in the menu bar. Click the mouse icon to:

- View the active profile and current app
- Enable/disable remapping
- Open Settings
- Check permission status

### Settings

The Settings window has a sidebar with your profiles:

- **Default** — Fallback mappings used when no app-specific profile matches
- **App profiles** — Mappings that only apply when a specific app is focused

### Adding an App Profile

1. Click the **+** button in the toolbar
2. Select a running application from the list
3. Configure button mappings for that app

### Mapping a Button

For each remappable button, use the dropdown to:

- Choose a **quick preset** (Mission Control, Volume, etc.)
- Create a **custom shortcut** (any key + modifiers)
- Build a **key sequence** (multi-step macro with recording)
- **Launch an application** by bundle ID
- **Run a shell command**

### Button Numbers

| Button | Number |
|--------|--------|
| Left Click | 0 |
| Right Click | 1 |
| Middle Click | 2 |
| Side Back | 3 |
| Side Forward | 4 |
| Extra 6-8 | 5-7 |
| Scroll Up | — |
| Scroll Down | — |

## Configuration

Config is stored at:

```
~/Library/Application Support/NewXMouse/config.json
```

### Config Format

```json
{
  "defaultProfile": {
    "bundleID": "default",
    "displayName": "Default",
    "mappings": {
      "3": { "keystroke": { "key": 123, "modifiers": ["command"] } },
      "4": { "keystroke": { "key": 124, "modifiers": ["command"] } }
    }
  },
  "appProfiles": [
    {
      "bundleID": "com.apple.Safari",
      "displayName": "Safari",
      "mappings": {
        "3": { "keystroke": { "key": 123, "modifiers": [] } },
        "4": { "keystroke": { "key": 124, "modifiers": [] } }
      }
    }
  ]
}
```

You can edit this file directly — changes are detected on next save from the app.

## Architecture

```
EventTap (CGEvent tap, C callback)
    ↓ intercepts mouse events
ActiveAppMonitor (NSWorkspace notifications)
    ↓ provides current bundleID (thread-safe)
ConfigStore (JSON config)
    ↓ resolves (button, app) → action
Action (execute via CGEvent)
    ↓ posts synthetic events
```

Key design decisions:

- **C function pointer callback** — CGEvent taps don't support Swift closures. State is accessed via `EventTapManager.shared`.
- **Thread-safe** — The event tap callback runs off the main thread. `ActiveAppMonitor` uses `OSAllocatedUnfairLock`.
- **Non-sandboxed** — CGEvent taps cannot work in the App Sandbox. Distributed via Developer ID + notarization.
- **LSUIElement** — The app lives in the menu bar only (no Dock icon).

## Why "New X Mouse"?

A nod to the classic X-Mouse paradigm from X11 window managers, where window focus follows the mouse. This app gives your mouse buttons new life on macOS.

## License

[MIT](LICENSE)
