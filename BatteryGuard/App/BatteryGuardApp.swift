// BatteryGuardApp.swift
// BatteryGuard — App entry point
//
// Dashboard dikelola via NSWindowController di AppDelegate (bukan SwiftUI Window scene)
// agar tidak auto-show saat launch. SwiftUI Window scene selalu menampilkan window
// saat launch dan melawan orderOut() — tidak cocok untuk menu bar apps.

import SwiftUI
import ServiceManagement

@main
struct BatteryGuardApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Dashboard = NSWindowController di AppDelegate (dikontrol penuh, tidak auto-show)
        // Settings = SwiftUI Settings scene (aman karena tidak auto-show)
        Settings {
            SettingsView()
                .environmentObject(appDelegate.prefs)
                .environmentObject(appDelegate.helperInstaller)
                .environmentObject(appDelegate.viewModel)
        }
    }
}
