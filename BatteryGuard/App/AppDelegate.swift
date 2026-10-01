// AppDelegate.swift
// BatteryGuard — Application lifecycle + NSStatusItem (AppKit)
// Menggunakan NSStatusItem langsung agar bisa render 2-baris layout
// yang tidak bisa dilakukan oleh SwiftUI MenuBarExtra label.
//
// OPTIMASI CPU (ditambahkan):
// - removeDuplicates() di semua Combine pipeline (SystemStatsViewModel)
// - Custom Equatable (ignore timestamp) di semua stat model
// → SwiftUI hanya re-render saat data benar-benar berubah signifikan

import AppKit
import SwiftUI
import ServiceManagement

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Shared State
    // Di-init di sini agar bisa dipakai oleh NSStatusItem + SwiftUI scenes

    let viewModel       = SystemStatsViewModel() // startAll() otomatis dipanggil di init()
    let prefs           = PreferencesStore.shared
    let helperInstaller = HelperInstaller()
    let mouseScroll     = MouseScrollService.shared

    // MARK: - Status Bar (AppKit)

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // MARK: - Dashboard Window (NSWindowController)
    // Dikontrol penuh di sini — tidak ada auto-show, tidak ada SwiftUI scene fight.
    private var dashboardWindowController: NSWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nonaktifkan window restoration dari sesi sebelumnya
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        helperInstaller.checkStatus()
        setupStatusItem()
        setupSystemNotifications()
        mouseScroll.start()
        if prefs.keyboardMonitorEnabled {
            KeyboardMonitorService.shared.start()
        }

        // Observe openDashboard dari MenuBarView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openDashboard),
            name: .openDashboardRequest,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseScroll.stop()
        KeyboardMonitorService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDashboard() }
        return true
    }

    // MARK: - NSStatusItem Setup

    private func setupStatusItem() {
        // 1. Buat status item dengan panjang fixed
        statusItem = NSStatusBar.system.statusItem(withLength: 315)

        // 2. Buat SwiftUI view untuk label — 2-baris compact
        let labelView = MenuBarStatusLabel(viewModel: viewModel, prefs: prefs)
        let hosting   = NSHostingView(rootView: labelView)
        // PENTING: gunakan Auto Layout, BUKAN frame + autoresizingMask
        // (button.bounds saat setup masih .zero karena belum di-layout)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // 3. Embed hosting view di dalam button status item
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(handleStatusClick)
        button.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        // 4. Setup popover
        setupPopover()
    }

    private func setupPopover() {
        let content = MenuBarView()
            .environmentObject(viewModel)
            .environmentObject(prefs)
            .environmentObject(helperInstaller)

        let controller    = NSHostingController(rootView: content)
        let pop           = NSPopover()
        pop.contentViewController = controller
        pop.contentSize   = NSSize(width: 310, height: 460)
        pop.behavior      = .transient
        pop.animates      = true
        self.popover      = pop
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        guard let pop = popover, let button = statusItem?.button else { return }
        if pop.isShown {
            pop.performClose(sender)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Helper Installation

    private func checkAndInstallHelper() {
        let service = SMAppService.daemon(plistName: "com.ibrardev.Ozone.Helper.plist")
        switch service.status {
        case .enabled:          break
        case .requiresApproval: showHelperApprovalNotification()
        case .notFound:         break
        case .notRegistered:    break
        @unknown default:       break
        }
    }

    private func showHelperApprovalNotification() {
        print("[AppDelegate] Helper memerlukan approval di System Settings > Privacy & Security > Background Items")
    }

    // MARK: - System Notifications

    private func setupSystemNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handlePowerChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handlePowerChange(_ notification: Notification) {
        // Re-apply limit setelah wake dari sleep.
        // SMC state mungkin ter-reset setelah deep sleep pada beberapa model Mac.
        NSLog("[AppDelegate] Wake from sleep detected, re-apply charge limit")
        viewModel.chargeLimitManager.restoreOnLaunch()
    }

    // MARK: - Window Management

    /// Buka dashboard — lazy init NSWindowController agar window dibuat on-demand,
    /// bukan saat launch. Tidak ada SwiftUI scene yang bisa melawan ini.
    @objc func openDashboard() {
        if dashboardWindowController == nil {
            makeDashboardWindowController()
        }
        dashboardWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Buat NSWindowController + NSHostingController untuk DashboardView.
    /// Dipanggil hanya saat pertama kali user membuka dashboard.
    private func makeDashboardWindowController() {
        let rootView = DashboardView()
            .environmentObject(viewModel)
            .environmentObject(prefs)
            .environmentObject(helperInstaller)

        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Ozone"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        // PENTING: jangan release saat ditutup — kita ingin reuse window yang sama
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false

        dashboardWindowController = NSWindowController(window: window)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Dikirim dari MenuBarView (atau komponen lain) untuk membuka Dashboard.
    static let openDashboardRequest = Notification.Name("com.ozone.openDashboardRequest")
}

// MARK: - MenuBarStatusLabel (SwiftUI)
//
// 2-baris compact layout untuk menu bar.
// OPTIMASI: berkat removeDuplicates() di Combine pipeline dan custom Equatable
// yang mengabaikan timestamp, view ini HANYA di-render ulang saat data berubah
// secara signifikan (bukan setiap timer tick).

struct MenuBarStatusLabel: View {

    @ObservedObject var viewModel: SystemStatsViewModel
    @ObservedObject var prefs: PreferencesStore

    var body: some View {
        // spacing 10 agar tiap item tidak berdempetan
        HStack(spacing: 10) {

            // Network Speed — kolom fixed 72pt supaya nilai yg berubah
            // tidak menggeser item lain (monospaced font membantu stabilitas)
            if prefs.showNetworkSpeed {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 2) {
                        Text("↑")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.green)
                        Text(compactSpeed(viewModel.networkStats.uploadBytesPerSec))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                    HStack(spacing: 2) {
                        Text("↓")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(compactSpeed(viewModel.networkStats.downloadBytesPerSec))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(width: 72, alignment: .trailing) // fixed — tidak bergerak saat nilai berubah
            }

            // GPU % — fixed 45pt
            if prefs.showGPUUsage {
                StatusChip(label: "GPU",
                           value: viewModel.gpuStats.shortFormatted,
                           color: gpuColor)
                    .frame(width: 45, alignment: .center)
            }

            // RAM % — fixed 45pt
            if prefs.showRAMUsage {
                StatusChip(label: "RAM",
                           value: String(format: "%.0f%%", viewModel.ramStats.usagePercent),
                           color: ramColor)
                    .frame(width: 45, alignment: .center)
            }

            // CPU % — fixed 45pt
            if prefs.showCPUUsage {
                StatusChip(label: "CPU",
                           value: viewModel.cpuStats.shortFormatted,
                           color: cpuColor)
                    .frame(width: 45, alignment: .center)
            }

            // Suhu
            if prefs.showTemperature {
                let temp = viewModel.temperatures.cpuTemperature
                        ?? viewModel.temperatures.batteryTemperature
                if let temp {
                    Text(temp.shortFormatted)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tempColor(temp.celsius))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Helpers

    /// Format kecepatan dengan satuan jelas: "352 KB/s", "1.2 MB/s", "0 KB/s"
    private func compactSpeed(_ bps: Double) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
        if bps >= 1_000     { return String(format: "%.0f KB/s", bps / 1_000) }
        return "0 KB/s"
    }

    private var gpuColor: Color {
        guard let u = viewModel.gpuStats.usagePercent else { return .primary }
        return u < 50 ? .primary : u < 80 ? .orange : .red
    }

    private var ramColor: Color {
        let u = viewModel.ramStats.usagePercent
        return u < 70 ? .primary : u < 85 ? .orange : .red
    }

    private var cpuColor: Color {
        let u = viewModel.cpuStats.totalUsagePercent
        return u < 50 ? .primary : u < 80 ? .orange : .red
    }

    private func tempColor(_ c: Double) -> Color {
        c < 60 ? .primary : c < 80 ? .orange : .red
    }
}

// MARK: - StatusChip
// 2-baris: label kecil 30% di atas, nilai besar 70% di bawah

struct StatusChip: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Label — ~30% tinggi (font 7pt)
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
            // Nilai — ~70% tinggi (font 13pt)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
