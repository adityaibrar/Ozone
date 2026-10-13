// EnergyAppsCard.swift
// Card 9: Aplikasi yang menggunakan energi signifikan
// Data dari NSWorkspace — untuk data lebih akurat butuh powermetrics (sudo)

import SwiftUI
import AppKit

// MARK: - App Energy Info

struct AppEnergyInfo: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let icon: NSImage?
    let energyImpact: String // "High", "Medium", "Low" atau nilai numerik jika tersedia
}

// MARK: - EnergyAppsCard

struct EnergyAppsCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel
    @State private var energyApps: [AppEnergyInfo] = []
    @State private var isLoading = true

    var body: some View {
        DashboardCardView(
            title: "Energy Use",
            icon: "bolt.fill",
            accentColor: .orange,
            isLoading: isLoading
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if energyApps.isEmpty && !isLoading {
                    // Empty state
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Tidak ada aplikasi developer aktif")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    // App list
                    ForEach(energyApps.prefix(5)) { app in
                        AppEnergyRow(app: app)
                        if app.id != energyApps.prefix(5).last?.id {
                            Divider()
                        }
                    }

                    // Disclaimer
                    Text("Memfilter aplikasi & tools developer yang aktif (IDE, Terminal, Docker, DB, dll).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
        .task {
            await loadEnergyData()
        }
    }

    /// Ambil running apps dari NSWorkspace
    /// Ini adalah data yang tersedia tanpa privilege tambahan
    @MainActor
    private func loadEnergyData() async {
        isLoading = true
        defer { isLoading = false }

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && isDeveloperApp($0) }
            .prefix(10)
            .map { app -> AppEnergyInfo in
                AppEnergyInfo(
                    name: app.localizedName ?? "Unknown",
                    bundleID: app.bundleIdentifier ?? "",
                    icon: app.icon,
                    energyImpact: app.isActive ? "Active" : "Background"
                )
            }

        energyApps = Array(apps)
    }

    /// Memeriksa apakah aplikasi tergolong developer tool atau environment developer
    private func isDeveloperApp(_ app: NSRunningApplication) -> Bool {
        let name = (app.localizedName ?? "").lowercased()
        let bundleID = (app.bundleIdentifier ?? "").lowercased()

        // 1. Bundle ID matchers yang umum digunakan developer
        let devBundlePrefixes = [
            "com.apple.dt.",            // Xcode, Simulator, Instruments
            "com.microsoft.vscode",      // Visual Studio Code
            "com.todesktop.",            // Cursor, Windsurf, dev desktop wrappers
            "com.jetbrains.",            // JetBrains suite
            "com.google.android.studio", // Android Studio
            "com.googlecode.iterm2",     // iTerm2
            "dev.warp.",                 // Warp Terminal
            "com.docker.",               // Docker Desktop
            "dev.orbstack.",             // OrbStack
            "com.tinyapp.tableplus",     // TablePlus
            "com.postmanlabs.",          // Postman
            "com.insomnia.",             // Insomnia
            "com.sequel-ace.",           // Sequel Ace
            "io.dbeaver.",               // DBeaver
            "com.github.GitHubClient",   // GitHub Desktop
            "com.fournova.Tower",        // Tower Git
            "com.DanPristupov.Fork",     // Fork Git
            "com.sublimetext.",          // Sublime Text
            "dev.zed.Zed",               // Zed Editor
            "com.panic.Nova",            // Nova Editor
            "com.proxyman.",             // Proxyman
            "org.wireshark.",            // Wireshark
            "com.charlesproxy."          // Charles Proxy
        ]

        for prefix in devBundlePrefixes {
            if bundleID.hasPrefix(prefix.lowercased()) {
                return true
            }
        }

        // 2. Keyword matchers pada nama aplikasi atau bundle ID
        let devKeywords = [
            "xcode", "code", "cursor", "windsurf", "antigravity",
            "android studio", "intellij", "webstorm", "pycharm", "clion",
            "goland", "datagrip", "phpstorm", "rider", "rubymine", "fleet",
            "sublime", "zed", "nova", "atom", "bbedit", "textmate",
            "terminal", "iterm", "warp", "ghostty", "alacritty", "kitty", "wezterm", "hyper",
            "docker", "orbstack", "podman", "rancher", "simulator", "instruments",
            "postman", "insomnia", "tableplus", "dbeaver", "beekeeper", "pgadmin",
            "compass", "redis", "sequel ace",
            "git", "fork", "sourcetree", "gitkraken", "github desktop", "tower",
            "proxyman", "wireshark", "charles", "devtoys", "hoppscotch", "herd", "mamp", "xampp"
        ]

        for keyword in devKeywords {
            if name.contains(keyword) || bundleID.contains(keyword) {
                return true
            }
        }

        return false
    }
}

// MARK: - App Energy Row

struct AppEnergyRow: View {
    let app: AppEnergyInfo

    var body: some View {
        HStack(spacing: 8) {
            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "app")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }

            // App name
            Text(app.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            // Energy impact
            Text(app.energyImpact)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
