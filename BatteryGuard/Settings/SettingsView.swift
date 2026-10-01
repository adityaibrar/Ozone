// SettingsView.swift
// BatteryGuard — Preferences panel (dibuka via Cmd+, atau gear icon)
// Update: tambah tab Mouse untuk fitur Natural Scrolling Auto-Toggle

import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject var prefs: PreferencesStore
    @EnvironmentObject var helperInstaller: HelperInstaller
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @ObservedObject private var mouseService = MouseScrollService.shared

    var body: some View {
        TabView {
            // MARK: General
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            // MARK: Menu Bar
            MenuBarSettingsTab()
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }

            // MARK: Mouse
            MouseSettingsTab()
                .tabItem {
                    Label("Mouse", systemImage: "computermouse")
                }

            // MARK: Helper
            HelperSettingsTab()
                .tabItem {
                    Label("Helper", systemImage: "wrench.and.screwdriver")
                }

            // MARK: Uninstaller
            UninstallerView()
                .tabItem {
                    Label("Uninstaller", systemImage: "trash")
                }

            // MARK: About
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 600, height: 500)
        .environmentObject(prefs)
        .environmentObject(helperInstaller)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {
    @EnvironmentObject var prefs: PreferencesStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Buka aplikasi otomatis saat login", isOn: $prefs.launchAtLogin)
            }

            Section("Charge Limiter") {
                Toggle("Enable Charge Limit on Launch", isOn: $prefs.isChargeLimitEnabled)
                HStack {
                    Text("Default Limit")
                    Spacer()
                    Stepper("\(prefs.chargeLimit)%", value: $prefs.chargeLimit, in: 20...100, step: 1)
                }
            }

            Section("Notifications") {
                Toggle("Notify when limit reached", isOn: $prefs.notifyOnLimitReached)
                Toggle("Notify on low battery", isOn: $prefs.notifyOnLowBattery)
                HStack {
                    Text("Low Battery Threshold")
                    Spacer()
                    Stepper("\(prefs.lowBatteryThreshold)%", value: $prefs.lowBatteryThreshold, in: 5...30, step: 1)
                }
            }

            Section("Heat Protection") {
                Toggle("Enable Heat Protection", isOn: $prefs.isHeatProtectionEnabled)
                HStack {
                    Text("Temperature Threshold")
                    Spacer()
                    Stepper(String(format: "%.0f°C", prefs.heatProtectionThreshold),
                            value: $prefs.heatProtectionThreshold,
                            in: 35...60, step: 1)
                }
                .disabled(!prefs.isHeatProtectionEnabled)
            }

            Section("Polling Intervals") {
                HStack {
                    Text("Battery Polling")
                    Spacer()
                    Picker("", selection: $prefs.batteryPollingInterval) {
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("5s").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                HStack {
                    Text("System (RAM/Network)")
                    Spacer()
                    Picker("", selection: $prefs.systemPollingInterval) {
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu Bar Settings Tab

private struct MenuBarSettingsTab: View {
    @EnvironmentObject var prefs: PreferencesStore

    var body: some View {
        Form {
            Section("Display Options") {
                Toggle("Show Battery Percentage", isOn: $prefs.showBatteryPercent)
                Toggle("Show Network Speed", isOn: $prefs.showNetworkSpeed)
                Toggle("Show RAM Usage", isOn: $prefs.showRAMUsage)
                Toggle("Show Temperature", isOn: $prefs.showTemperature)
                Toggle("Compact Mode", isOn: $prefs.isCompactMenuBar)
            }

            Section("Temperature Monitoring") {
                Toggle("Enable Temperature Monitoring", isOn: $prefs.temperatureMonitoringEnabled)
                Text("CPU temperature requires additional permissions. Battery temperature is always available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if prefs.temperatureMonitoringEnabled {
                    HStack {
                        Text("Polling Interval")
                        Spacer()
                        Picker("", selection: $prefs.tempPollingInterval) {
                            Text("3s").tag(3.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Mouse Settings Tab

private struct MouseSettingsTab: View {
    @EnvironmentObject var prefs: PreferencesStore
    @ObservedObject private var mouseService = MouseScrollService.shared

    var body: some View {
        Form {
            // MARK: Master Toggle
            Section("Pisahkan Scroll Mouse & Trackpad") {
                Toggle("Aktifkan", isOn: $prefs.mouseAutoScrollEnabled)
                    .onChange(of: prefs.mouseAutoScrollEnabled) { enabled in
                        // userInitiated: true → otomatis prompt permission jika belum ada
                        if enabled { mouseService.start(userInitiated: true) }
                        else       { mouseService.stop() }
                    }

                Text("Saat aktif: scroll wheel mouse menggunakan arah normal (tidak natural), sedangkan trackpad tetap menggunakan natural scrolling. System Settings tidak diubah sama sekali.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Direction Options
            Section("Arah Pengguliran (Inversion)") {
                Toggle("Balikkan Arah Vertikal (Y-Axis)", isOn: $prefs.mouseInvertVertical)
                Toggle("Balikkan Arah Horizontal (X-Axis)", isOn: $prefs.mouseInvertHorizontal)
            }
            .disabled(!prefs.mouseAutoScrollEnabled)

            // MARK: Accessibility Permission
            Section("Accessibility Permission") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(mouseService.hasAccessibilityPermission ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(mouseService.hasAccessibilityPermission
                             ? "Permission aktif"
                             : "Permission diperlukan")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if !mouseService.hasAccessibilityPermission {
                            Text("System Settings → Privacy & Security → Accessibility")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !mouseService.hasAccessibilityPermission {
                        Button("Buka Settings") {
                            mouseService.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(!prefs.mouseAutoScrollEnabled)

            // MARK: Status Event Tap
            Section("Status") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(mouseService.isActive ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)

                    Text(mouseService.isActive
                         ? "Aktif — mouse scroll dibalik, trackpad tetap natural"
                         : statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(mouseService.isActive ? .primary : .secondary)

                    Spacer()
                }
                .padding(.vertical, 2)

                // Tampilkan tombol retry jika toggle ON tapi tap belum aktif
                if prefs.mouseAutoScrollEnabled && !mouseService.isActive && mouseService.hasAccessibilityPermission {
                    Button("Aktifkan Sekarang") {
                        mouseService.start(userInitiated: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .disabled(!prefs.mouseAutoScrollEnabled)
        }
        .formStyle(.grouped)
        .onAppear {
            // Re-cek permission setiap kali tab dibuka (user mungkin baru grant dari Settings)
            mouseService.refreshPermissionStatus()
        }
    }

    private var statusDescription: String {
        if !prefs.mouseAutoScrollEnabled { return "Toggle dimatikan" }
        if !mouseService.hasAccessibilityPermission { return "Menunggu Accessibility permission" }
        return "Tidak aktif"
    }
}

// MARK: - Helper Settings Tab

private struct HelperSettingsTab: View {
    @EnvironmentObject var helperInstaller: HelperInstaller

    var body: some View {
        Form {
            Section("Privileged Helper") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(statusColor)
                        .fontWeight(.medium)
                }

                HStack {
                    Button("Install / Update Helper") {
                        helperInstaller.install()
                    }
                    .disabled(helperInstaller.isInstalled)

                    Button("Uninstall Helper") {
                        helperInstaller.uninstall()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!helperInstaller.isInstalled)
                }

                Text("The helper tool runs as a privileged daemon to apply charge limits. It must be installed once and requires your approval in System Settings → Privacy & Security → Background Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = helperInstaller.lastError {
                Section("Last Error") {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            helperInstaller.checkStatus()
        }
    }

    private var statusText: String {
        switch helperInstaller.installStatus {
        case .checking: return "Memeriksa..."
        case .running: return "Aktif & Berjalan"
        case .enabled: return "Aktif & Berjalan"
        case .notRunning: return "Belum Terinstall"
        }
    }

    private var statusColor: Color {
        switch helperInstaller.installStatus {
        case .running, .enabled: return .green
        case .checking: return .secondary
        case .notRunning: return .red
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {

    // Baca versi & build dari Bundle — otomatis sinkron dengan Info.plist
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Ozone"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon asli dari bundle — selalu sinkron dengan Assets.xcassets
            ZStack {
                // Glow ambient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.green.opacity(0.2), .green.opacity(0)],
                            center: .center,
                            startRadius: 30,
                            endRadius: 70
                        )
                    )
                    .frame(width: 130, height: 130)

                // Icon asli app
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
            }

            VStack(spacing: 6) {
                Text(appName)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)

                // Versi dinamis dari Bundle
                HStack(spacing: 6) {
                    Text("Version \(appVersion)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("(\(buildNumber))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text("System Monitor, Battery & Keyboard Utility\nfor Apple Silicon Macs")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Tech badges
            HStack(spacing: 8) {
                ForEach(["SwiftUI", "IOKit", "XPC", "Swift Charts"], id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
