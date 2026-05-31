# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**New X Mouse** is a macOS menu bar utility that intercepts mouse button events and remaps them to configurable actions on a per-application basis. For example, mouse side buttons can trigger different keyboard shortcuts depending on which app is in focus.

## Architecture

### Core Event Pipeline

1. **EventTapManager** (`EventTap/EventTapManager.swift`) — Creates a `CGEvent.tapCreate` session tap that intercepts `otherMouseDown/Up` and `rightMouseDown/Up` events. Uses a C function pointer callback (no closures) with a static `shared` reference for context access.

2. **ActiveAppMonitor** (`Detection/ActiveAppMonitor.swift`) — Subscribes to `NSWorkspace.didActivateApplicationNotification` to track the frontmost app's `bundleIdentifier`. Provides thread-safe access via `OSAllocatedUnfairLock` since the event tap callback runs off the main thread.

3. **ConfigStore** (`Config/ConfigStore.swift`) — Loads/saves JSON config from `~/Library/Application Support/NewXMouse/config.json`. Provides the lookup: `(MouseButton, bundleID) -> Action?`. Falls back to default profile when no app-specific mapping exists.

4. **Action** (`Actions/Action.swift`) — Enum with cases: `.keystroke`, `.mouseButton`, `.appLaunch`, `.shell`, `.none`. Each case can `execute(isDown:)` to post synthetic events via `CGEvent`.

### Key Design Constraints

- **Non-sandboxed**: CGEvent taps cannot work in the App Sandbox. The app must be distributed outside the Mac App Store (Developer ID + notarization).
- **LSUIElement = YES**: Hides the app from the Dock; it lives in the menu bar only.
- **C callback**: The CGEvent tap callback is a C function pointer — it cannot capture Swift context. State is accessed via a static `EventTapManager.shared` property.
- **Thread safety**: The event tap callback may run on a non-main thread. Any shared state it reads (like the current bundle ID) must be protected.
- **Requires macOS 13+**: Uses `MenuBarExtra`, `OSAllocatedUnfairLock`, `SMAppService`.

### UI Layer (SwiftUI)

- `MenuBarExtra` for the status bar menu (enable/disable toggle, settings link, quit)
- `Settings` scene with `NavigationSplitView` for managing profiles
- Per-profile editing with `ActionEditorView` (key picker, modifier toggles)

### Config Format

JSON at `~/Library/Application Support/NewXMouse/config.json`:
- `defaultProfile`: fallback mappings applied when no app-specific profile matches
- `appProfiles`: array of `{bundleID, displayName, mappings}` where mappings key is the `MouseButton` raw value (int)

## Build & Run

Open the Xcode project and build (Cmd+R). The app requires **Accessibility permission** — it will prompt on first launch. Grant it in System Settings > Privacy & Security > Accessibility.

No external dependencies. Pure Swift + macOS SDK.

## Mouse Button Numbers

- 0 = Left, 1 = Right, 2 = Middle, 3 = Side Back, 4 = Side Forward, 5-7 = Extra buttons
- Side/middle buttons arrive as `otherMouseDown/Up`; differentiated via `CGEventField.mouseEventButtonNumber`
