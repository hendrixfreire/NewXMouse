# Contributing to New X Mouse

Thanks for your interest! Here's how to contribute.

## Development Setup

1. Clone the repo
2. Open `NewXMouse.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)
4. Grant Accessibility permission when prompted

## Requirements

- macOS 13.0+ (Ventura)
- Xcode 15+
- Swift 5.9+

## Architecture

The app follows a simple pipeline:

1. **EventTapManager** — CGEvent session tap intercepts mouse events
2. **ActiveAppMonitor** — Tracks frontmost app via NSWorkspace notifications
3. **ConfigStore** — JSON config lookup: (MouseButton, bundleID) → Action
4. **Action** — Executes mapped actions (keystroke, mouse button, app launch, shell)

Key constraints:
- The CGEvent callback is a C function pointer — no Swift closures. State is accessed via `EventTapManager.shared`.
- The callback may run off the main thread. Shared state must be thread-safe.
- The app is non-sandboxed (CGEvent taps don't work in the sandbox).

## Pull Request Process

1. Fork the repo and create a feature branch
2. Make your changes
3. Test on macOS 13+ and macOS 14+
4. Submit a PR with a clear description of the change

## Code Style

- Follow Swift API Design Guidelines
- Use `os_log` for logging (not `print`)
- Keep the C callback minimal — delegate to Swift methods ASAP
- Prefer SwiftUI for new UI components

## Reporting Issues

- Include macOS version, app version, and mouse model
- Check the Diagnostics panel (stethoscope icon in Settings) for relevant info
- Attach Console.app logs filtered by `com.newxmouse.app` if possible
