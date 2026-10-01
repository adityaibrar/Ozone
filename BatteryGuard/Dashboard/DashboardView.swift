// DashboardView.swift
// BatteryGuard — Root dashboard window dengan NavigationSplitView + LazyVGrid

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @EnvironmentObject var prefs: PreferencesStore
    @EnvironmentObject var helperInstaller: HelperInstaller

    @State private var sidebarSelection: DashboardSection? = .dashboard

    // Adaptive grid: 2 kolom, minimal 300pt — macOS 26 spacing lebih lega
    private let gridColumns = [
        GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 18)
    ]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            detailContent
                .navigationTitle(sidebarSelection?.rawValue ?? "Dashboard")
                .toolbar {
                    toolbarContent
                }
        }
        .onAppear {
            viewModel.startAll()
            helperInstaller.checkStatus()
            
            // Auto prompt install on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if !helperInstaller.isInstalled && !UserDefaults.standard.bool(forKey: "HasPromptedInstall") {
                    UserDefaults.standard.set(true, forKey: "HasPromptedInstall")
                    helperInstaller.install()
                }
            }
        }
        .onDisappear {
            // Jangan stop monitors saat dashboard ditutup — tetap jalan di background
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch sidebarSelection {
        case .dashboard, .none:
            mainDashboardGrid
        case .chargeControl:
            chargeControlView
        case .mouse:
            MouseControlView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .energyUse:
            EnergyAppsCard()
                .padding()
                .frame(maxWidth: 500)
        case .volumeMixer:
            VolumeMixerView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .keyboard:
            KeyboardMonitorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .log:
            LogView()
        case .uninstaller:
            UninstallerView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Main Dashboard Grid (10 Cards)

    private var mainDashboardGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                NetworkSpeedCard()
                PowerFlowCard()
                BatteryTemperatureCard()
                BatteryLevelCard()
                BatteryHealthCard()
                PowerConsumptionCard()
                BatteryCyclesCard()
                BatterySpecsCard()
                PowerAdapterCard()
                EnergyAppsCard()
                CalibrationCard()
            }
            .padding(22)
        }
    }

    // MARK: - Charge Control View

    private var chargeControlView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Helper status banner
                if !helperInstaller.isInstalled {
                    HelperInstallBanner()
                        .environmentObject(helperInstaller)
                }

                // Charge limit control
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "bolt.badge.clock.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        Text("Charge Limit")
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                    }

                    // Glass card
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Enable Charge Limit", isOn: Binding(
                            get: { viewModel.chargeLimitState.isEnabled },
                            set: { _ in viewModel.toggleChargeLimit() }
                        ))
                        .toggleStyle(.switch)
                        .tint(.green)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Limit")
                                    .fontWeight(.medium)
                                Text("\(viewModel.chargeLimitState.limitPercent)%")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                                    .contentTransition(.numericText())
                                Spacer()
                                Text("Recommended: 80%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.chargeLimitState.limitPercent) },
                                    set: { viewModel.setChargeLimit(Int($0)) }
                                ),
                                in: 20...100,
                                step: 5
                            )
                            .disabled(!viewModel.chargeLimitState.isEnabled)
                            .tint(.green)

                            HStack {
                                Text("20%")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("100%")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .animation(.spring(response: 0.35), value: viewModel.chargeLimitState.isEnabled)
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
                    }

                    // Error display
                    if let error = viewModel.chargeLimitError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .background(.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.vertical, 22)
        }
    }

    // MARK: - Placeholder View

    private func placeholderView(_ title: String, icon: String, description: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                // Refresh all monitors
                viewModel.startAll()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .help("Refresh")
        }

        ToolbarItem(placement: .automatic) {
            if viewModel.isApplyingLimit {
                ProgressView()
                    .controlSize(.small)
                    .tint(.green)
            }
        }
    }
}

// MARK: - Helper Install Banner

struct HelperInstallBanner: View {
    @EnvironmentObject var helperInstaller: HelperInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Helper Belum Terinstall")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                    Text("Fitur pembatasan baterai memerlukan komponen tambahan (Helper) agar bisa mengontrol daya masuk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.4), .orange.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)

            Text("Klik tombol di bawah ini untuk menginstall. Anda akan diminta memasukkan Password atau Touch ID Mac Anda.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Install Helper Sekarang") {
                    helperInstaller.install()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)

                if helperInstaller.installStatus == .checking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.orange)
                }
            }
        }
        .padding(16)
        .background(.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        }
        .padding(.horizontal, 22)
    }
}

