# Ozone v1.2.0 — Polish & Stability Update

This release focuses on bug fixes, scroll performance optimizations, and overall UI quality improvements. No major new features were introduced — all energy was poured into ensuring a smooth, responsive, and error-free experience across the application.

---

## ✨ Changes in v1.2.0

### 🏗️ Architectural Changes (Internal Breaking Changes)

- **Dashboard migrated to `NSWindowController`**
  The Dashboard is no longer managed as a SwiftUI `Window` scene. It is now fully controlled by the `AppDelegate` via `NSWindowController`, allowing full control over when the window is shown or hidden — without interference from the SwiftUI scene lifecycle.

- **Removed SwiftUI `Window` scene from `BatteryGuardApp`**
  Only the `Settings` scene remains. The Dashboard is created lazily (on-demand) only when the user first opens it, eliminating launch overhead.

---

### 🐛 Bug Fixes

#### Dashboard — No Longer Auto-Opens on Launch
- **Root cause:** The SwiftUI `Window` scene always displays its window upon launch and actively fights `orderOut()` calls from the outside — creating an infinite loop.
- **Fix:** Removed the `Window` scene and replaced it with `NSWindowController`. The Dashboard now only appears when explicitly requested by the user (clicking ⊞ in the popover or clicking the Dock icon).

#### About Tab — Hardcoded App Icon & Version
- **Fix:** The app icon now uses `NSApp.applicationIconImage` — automatically syncing with `Assets.xcassets`, requiring no manual updates.
- **Fix:** Version reads dynamically from `Bundle.main.infoDictionary["CFBundleShortVersionString"]` and build number from `CFBundleVersion` — always in sync with Xcode project settings.
- **Fix:** App name reads from `CFBundleDisplayName` / `CFBundleName` dynamically.

#### About Tab — Invalid SF Symbol
- **Fix:** `battery.75.bolt` doesn't exist in SF Symbols — removed and replaced by the actual app icon.

#### Settings — `SettingsLink` vs Deprecated `sendAction`
- **Fix:** Migrated from `NSApp.sendAction("showSettingsWindow:")` (deprecated in macOS 14+) to `SettingsLink` using an `#available(macOS 14.0, *)` guard and fallback `sendAction` for macOS 13.
- **Fix:** Added `settingsIconLabel` as a shared computed property to prevent code duplication between the two availability branches.

#### MenuBar — `openWindow` Environment Dependency Removed
- **Fix:** The Dashboard button in `MenuBarView` no longer uses `@Environment(\.openWindow)`. It now posts `Notification.Name.openDashboardRequest` to the `AppDelegate`, which directly manages the window.

#### Volume Mixer — Different Audio Output in Background
- **Root cause:** `VolumeMixerService` was initialized as a `@StateObject` inside `VolumeMixerView`. This caused the service to be deallocated every time the dashboard was closed, killing the CoreAudio Process Tap and reverting the volume to default passthrough.
- **Fix:** Moved the lifecycle to `SystemStatsViewModel` so it shares the app's lifetime. The view now uses a Wrapper pattern with `@EnvironmentObject` and passes the instance to an inner view using `@ObservedObject` (preserving `$service` binding syntax on the view without compromising background stability).

#### PowerAdapterCard — Invalid SF Symbol
- **Fix:** The `powerplug.slash` symbol does not exist — replaced with a valid combination of `powerplug` + `xmark` overlay.

#### KeyboardMonitorView — Duplicate `ForEach` ID Warning
- **Fix:** Migrated from `id: \.self` to `enumerated()` + index-based ID for heatmap keys, eliminating duplicate ID warnings in the console.

---

### ⚡ Performance

- **`DashboardCardView` — Smoother Scrolling**
  Removed: hover state animations, material blur backgrounds, and redundant shadow layers that caused stuttering when scrolling the `LazyVGrid`. It is now lighter and consistently runs at 60fps.

---

### 🎨 UI/UX

- **MenuBar Popover — "Quick Stats" Row**
  Added a compact row at the top of the popover displaying: Battery Health, Cycle Count, CPU Temp, RAM Usage, and Download Speed — without needing to open the Dashboard.

- **AppDelegate — Adjusted Popover Size**
  Increased the popover size to accommodate the newly added Quick Stats row.

- **About Tab — More Accurate Display**
  The app icon now displays the real icon (instead of a green placeholder), and the version and build numbers always sync automatically.

---

### 🔧 Developer / Internal

- Added `Notification.Name.openDashboardRequest` extension for clean communication between SwiftUI views and the AppDelegate.
- Added `UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")` to prevent unwanted window restoration on the next launch.
- All `[AppDelegate]` debug logs added during the debugging session have been cleaned up from the production build path.

---

## 📁 Changed Files

| File | Changes |
|------|-----------|
| `App/BatteryGuardApp.swift` | Removed `Window` scene, kept only `Settings` scene |
| `App/AppDelegate.swift` | Migrated to `NSWindowController`, added `Notification.Name`, removed suppress logic |
| `MenuBar/MenuBarView.swift` | Replaced `openWindow` → `NotificationCenter`, removed `@Environment(\.openWindow)`, added Quick Stats |
| `Settings/SettingsView.swift` | Fixed About tab: real app icon, dynamic version, removed invalid SF Symbol |
| `Dashboard/Cards/DashboardCardView.swift` | Removed hover animation & material blur for scroll performance |
| `Dashboard/Cards/PowerAdapterCard.swift` | Fixed SF Symbol `powerplug.slash` |
| `Dashboard/Cards/KeyboardMonitorView.swift` | Fixed duplicate ForEach ID |

---

## 💻 Requirements

- macOS 13 (Ventura) or later
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

