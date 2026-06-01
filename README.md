# New X Mouse

A macOS menu bar utility that remaps mouse buttons to configurable actions on a per-application basis.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![MIT License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Per-app remapping** — Different button mappings for every application
- **Layer system** — Multiple mapping profiles per app, switch instantly
- **Scroll wheel remapping** — Map scroll up/down/left/right to any action
- **Quick presets** — Mission Control, Spotlight, volume, zoom, and more
- **Custom shortcuts** — Record any keyboard shortcut with modifier keys
- **Key sequences** — Simulate multi-key sequences with configurable timing
- **App launching** — Press a button to open any application
- **Shell commands** — Run arbitrary shell commands from a button press
- **Import/Export** — Share configurations between machines
- **Diagnostics** — Built-in event capture tool to debug button mappings

## Installation

### Download

Grab the latest release from the [Releases](../../releases) page.

### Build from Source

1. Clone the repository
2. Open `NewXMouse.xcodeproj` in Xcode
3. Build and run (⌘R)

## Setup

On first launch, macOS will prompt you to grant **Accessibility** and **Input Monitoring** permissions. Both are required for the app to intercept and remap mouse events.

1. Open System Settings → Privacy & Security → Accessibility
2. Enable **New X Mouse**
3. Open System Settings → Privacy & Security → Input Monitoring
4. Enable **New X Mouse**
5. Restart the app

## Usage

### Default Profile

The default profile applies when no app-specific mapping matches. Start here to set global button behavior.

### App-Specific Profiles

1. Click the **+** button in the toolbar
2. Select an installed application or enter a bundle ID manually
3. Configure button mappings for that app

### Layers

Layers let you switch between different mapping configurations for the same app. For example, one layer for normal browsing and another for gaming — without creating separate profiles.

### Actions

| Action | Description |
|--------|-------------|
| **Pass Through** | Let the original button event through unchanged |
| **Block** | Completely block the button — nothing happens |
| **Keystroke** | Send a keyboard shortcut (e.g. ⌘W) |
| **Key Sequence** | Send multiple keys in sequence |
| **Mouse Button** | Simulate a different mouse button click |
| **Double Click** | Simulate a double-click |
| **App Launch** | Open an application |
| **Shell Command** | Run a shell command (with 10s timeout) |

### Mouse Button Reference

| Button | Number |
|--------|--------|
| Left | 0 |
| Right | 1 |
| Middle | 2 |
| Side Back | 3 |
| Side Forward | 4 |
| Extra 1-3 | 5-7 |
| Scroll Up/Down/Left/Right | Virtual |

## Configuration

Config is stored at `~/Library/Application Support/NewXMouse/config.json`.

You can export and import configurations via the toolbar buttons. Importing a full configuration **replaces** all current profiles.

## Architecture

- **EventTapManager** — `CGEvent` tap that intercepts mouse events
- **ActiveAppMonitor** — Tracks frontmost application via NSWorkspace notifications
- **ConfigStore** — JSON config persistence with undo/redo support
- **Action** — Enum of all remappable actions with execution logic
- **SwiftUI** — Menu bar + Settings window with NavigationSplitView

### Key Constraints

- **Non-sandboxed** — CGEvent taps cannot work within the App Sandbox
- **LSUIElement** — App lives in the menu bar, not the Dock
- **Thread safety** — Event tap callback runs off-main-thread; shared state is lock-protected

## Requirements

- macOS 13 Ventura or later
- Accessibility permission
- Input Monitoring permission

## License

[MIT](LICENSE)
