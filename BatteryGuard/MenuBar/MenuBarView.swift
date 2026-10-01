// MenuBarView.swift
// BatteryGuard — Konten popover MenuBarExtra (macOS 26 Tahoe refresh)
// Redesign: lebih informatif — health, cycle, suhu, CPU/RAM inline

import SwiftUI

// MARK: - MenuBarView

struct MenuBarView: View {

    @EnvironmentObject var viewModel: SystemStatsViewModel
    @EnvironmentObject var prefs: PreferencesStore
    @EnvironmentObject var helperInstaller: HelperInstaller
    @ObservedObject private var mouseService = MouseScrollService.shared

    @State private var tempLimit: Double = 80

    var body: some View {
        VStack(spacing: 0) {

            // MARK: ── Battery Hero ─────────────────────────
            batteryHeroSection
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider().opacity(0.4)

            // MARK: ── Quick Stats Row ──────────────────────
            quickStatsRow
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider().opacity(0.4)

            // MARK: ── Charge Limit ─────────────────────────
            chargeControlSection
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider().opacity(0.4)

            // MARK: ── Mouse Scroll ────────────────────────
            mouseScrollSection
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

            // MARK: ── Error banner ────────────────────────
            if let error = viewModel.chargeLimitError {
                Divider().opacity(0.4)
                helperErrorBanner(error)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            Divider().opacity(0.4)

            // MARK: ── Footer ──────────────────────────────
            footerActions
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 310)
        .background(.ultraThinMaterial)
        .onAppear {
            tempLimit = Double(viewModel.chargeLimitState.limitPercent)
        }
        .onChange(of: viewModel.chargeLimitState.limitPercent) { newVal in
            tempLimit = Double(newVal)
        }
    }

    // MARK: - Battery Hero Section

    private var batteryHeroSection: some View {
        VStack(spacing: 10) {
            // Top row: label + big %
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.batteryIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(batteryColor)
                        Text("Battery")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.bold)
                    }
                    Text(batteryStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(viewModel.batteryStatus.percentage)%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(batteryColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: viewModel.batteryStatus.percentage)
            }

            // Progress bar
            BatteryProgressBar(
                percentage: viewModel.batteryStatus.percentage,
                limit: viewModel.chargeLimitState.isEnabled
                    ? viewModel.chargeLimitState.limitPercent : nil,
                isCharging: viewModel.batteryStatus.isCharging
            )
            .frame(height: 7)

            // Bottom row: time + wattage
            HStack(spacing: 4) {
                if let mins = viewModel.powerFlow.timeRemainingMinutes, mins > 0 {
                    Image(systemName: viewModel.batteryStatus.isCharging ? "bolt.fill" : "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(batteryColor.opacity(0.8))
                    Text(viewModel.timeRemainingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let watt = viewModel.powerFlow.instantWattage {
                    Text(String(format: "%.1f W", watt))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Quick Stats Row (Health · Cycles · Temp · RAM)

    private var quickStatsRow: some View {
        HStack(spacing: 0) {
            // Health
            QuickStatCell(
                icon: "heart.fill",
                label: "Health",
                value: viewModel.batteryHealth.maxCapacityPercent.map { "\($0)%" } ?? "—",
                color: healthColor
            )

            verticalSeparator

            // Cycle Count
            QuickStatCell(
                icon: "arrow.2.circlepath",
                label: "Cycles",
                value: viewModel.batteryHealth.cycleCount.map { "\($0)" } ?? "—",
                color: cycleColor
            )

            verticalSeparator

            // CPU Temp (atau RAM jika tidak ada temp)
            if let _ = viewModel.temperatures.cpuTemperature {
                QuickStatCell(
                    icon: "thermometer.medium",
                    label: "CPU Temp",
                    value: viewModel.temperatures.cpuTempFormatted,
                    color: tempColor
                )
            } else {
                QuickStatCell(
                    icon: "memorychip",
                    label: "RAM",
                    value: String(format: "%.0f%%", viewModel.ramStats.usagePercent),
                    color: ramColor
                )
            }

            verticalSeparator

            // Network down speed
            QuickStatCell(
                icon: "arrow.down",
                label: "Download",
                value: viewModel.networkStats.downloadFormatted,
                color: .cyan
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var verticalSeparator: some View {
        Divider()
            .frame(height: 28)
            .opacity(0.4)
    }

    // MARK: - Charge Control Section

    private var chargeControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.badge.clock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Charge Limit")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                }

                Spacer()

                if viewModel.chargeLimitState.isEnabled {
                    Text("\(viewModel.chargeLimitState.limitPercent)%")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }

                Toggle("", isOn: Binding(
                    get: { viewModel.chargeLimitState.isEnabled },
                    set: { _ in viewModel.toggleChargeLimit() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.green)
            }

            if viewModel.chargeLimitState.isEnabled {
                Slider(value: $tempLimit, in: 20...100) { _ in
                    viewModel.setChargeLimit(Int(tempLimit))
                }
                .tint(sliderColor)

                HStack {
                    Text("20%").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Recommended: 80%").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("100%").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }

            if viewModel.isApplyingLimit {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).tint(.green)
                    Text("Applying...").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Mouse Scroll Section

    private var mouseScrollSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(mouseService.isActive ? Color.indigo : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(mouseService.isActive ? Color.indigo : Color.secondary)
                    Text("Mouse Scroll")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                }
                Text(mouseStatusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(mouseService.hasAccessibilityPermission ? Color.secondary : Color.orange)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { prefs.mouseAutoScrollEnabled },
                set: { enabled in
                    prefs.mouseAutoScrollEnabled = enabled
                    if enabled { mouseService.start(userInitiated: true) }
                    else { mouseService.stop() }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.indigo)
        }
    }

    private var mouseStatusSubtitle: String {
        if !prefs.mouseAutoScrollEnabled { return "Disabled" }
        if !mouseService.hasAccessibilityPermission { return "⚠ Needs Accessibility permission" }
        return mouseService.isActive ? "Active · Inverted scroll" : "Inactive"
    }

    // MARK: - Helper Error Banner

    private func helperErrorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Label icon ⚙ yang dipakai oleh SettingsLink (macOS 14+) dan fallback Button (macOS 13)
    private var settingsIconLabel: some View {
        Image(systemName: "gear")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Footer Actions
    // Dashboard hanya icon kecil — tidak mencolok, mencegah klik tidak sengaja

    private var footerActions: some View {
        HStack(spacing: 6) {
            // Settings — SettingsLink (macOS 14+) dengan fallback sendAction (macOS 13)
            if #available(macOS 14.0, *) {
                SettingsLink {
                    settingsIconLabel
                }
                .buttonStyle(.plain)
                .help("Settings")
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    settingsIconLabel
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            // Dashboard — kirim notification ke AppDelegate, bukan openWindow scene
            Button {
                NotificationCenter.default.post(name: .openDashboardRequest, object: nil)
            } label: {
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Open Dashboard")

            Spacer()

            // App name kecil di tengah
            Text("Ozone")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed Colors & Text

    private var batteryColor: Color {
        if viewModel.chargeLimitState.isEnabled && viewModel.batteryStatus.chargeLimitReached {
            return .orange
        }
        switch viewModel.batteryStatus.percentage {
        case 20...: return .green
        case 10..<20: return .yellow
        default: return .red
        }
    }

    private var healthColor: Color {
        guard let h = viewModel.batteryHealth.maxCapacityPercent else { return .secondary }
        switch h {
        case 85...: return .green
        case 70..<85: return .yellow
        default: return .red
        }
    }

    private var cycleColor: Color {
        guard let c = viewModel.batteryHealth.cycleCount else { return .secondary }
        switch c {
        case ..<300: return .green
        case 300..<700: return .yellow
        default: return .orange
        }
    }

    private var sliderColor: Color {
        switch Int(tempLimit) {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    private var tempColor: Color {
        guard let temp = viewModel.temperatures.cpuTemperature?.celsius else { return .primary }
        switch temp {
        case ..<60: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    private var ramColor: Color {
        switch viewModel.ramStats.usagePercent {
        case ..<70: return .primary
        case 70..<85: return .orange
        default: return .red
        }
    }

    private var batteryStatusText: String {
        if viewModel.chargeLimitState.isEnabled && viewModel.batteryStatus.chargeLimitReached {
            return "Limit reached (\(viewModel.chargeLimitState.limitPercent)%)"
        }
        if viewModel.batteryStatus.isCharging {
            return "Charging\(viewModel.adapterInfo.wattage.map { " · \(Int($0))W" } ?? "")"
        }
        if viewModel.batteryStatus.isPluggedIn {
            return "Plugged in, not charging"
        }
        return "On Battery"
    }
}

// MARK: - Quick Stat Cell

/// Satu kolom statistik di Quick Stats row
private struct QuickStatCell: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Battery Progress Bar

struct BatteryProgressBar: View {
    let percentage: Int
    let limit: Int?
    let isCharging: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 7)

                Capsule()
                    .fill(LinearGradient(
                        colors: fillGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(7, geo.size.width * CGFloat(percentage) / 100), height: 7)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: percentage)

                if let limit = limit {
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: 2.5, height: 11)
                        .offset(x: geo.size.width * CGFloat(limit) / 100 - 1.25)
                        .shadow(color: .orange.opacity(0.5), radius: 3)
                }
            }
        }
    }

    private var fillGradient: [Color] {
        if isCharging { return [.green.opacity(0.8), .green] }
        switch percentage {
        case 20...: return [.green.opacity(0.8), .green]
        case 10..<20: return [.yellow.opacity(0.8), .yellow]
        default: return [.red.opacity(0.8), .red]
        }
    }
}

// MARK: - Preview

#Preview("Menu Bar Popover") {
    MenuBarView()
        .environmentObject(SystemStatsViewModel())
        .environmentObject(PreferencesStore.shared)
        .environmentObject(HelperInstaller())
}
