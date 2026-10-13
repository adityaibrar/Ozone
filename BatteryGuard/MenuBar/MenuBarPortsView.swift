// MenuBarPortsView.swift
// BatteryGuard / Ozone — Komponen Menu Bar Popover untuk menampilkan & menghentikan port aktif
// Menyediakan tab bar untuk Web, Developer, dan Database dengan tombol Stop langsung

import SwiftUI
import AppKit

// MARK: - Menu Bar Port Category

public enum MenuBarPortCategory: String, CaseIterable, Identifiable {
    case web = "Web"
    case dev = "Developer"
    case database = "Database"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .web: return "globe"
        case .dev: return "hammer.fill"
        case .database: return "cylinder.split.1x2.fill"
        }
    }

    public var color: Color {
        switch self {
        case .web: return .blue
        case .dev: return .indigo
        case .database: return .teal
        }
    }
}

// MARK: - MenuBarPortsView

struct MenuBarPortsView: View {
    @State private var ports: [PortProcessInfo] = []
    @State private var selectedCategory: MenuBarPortCategory = .web
    @State private var isLoading: Bool = false
    @State private var terminatingPIDs: Set<Int32> = []
    @State private var statusMessage: String? = nil

    private let service = PortMonitorService.shared

    var body: some View {
        VStack(spacing: 0) {
            // ── Header & Category Tab Bar ────────────────────────────────────
            categoryTabBar
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider().opacity(0.4)

            // ── Status Feedback Banner ───────────────────────────────────────
            if let message = statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)

                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))

                Divider().opacity(0.4)
            }

            // ── Port List Section ────────────────────────────────────────────
            portListContent
                .frame(minHeight: 180, maxHeight: 260)

            Divider().opacity(0.4)

            // ── Footer Toolbar ───────────────────────────────────────────────
            footerToolbar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .onAppear {
            refreshPorts()
        }
        .animation(.easeInOut(duration: 0.2), value: statusMessage)
    }

    // MARK: - Category Tab Bar

    private var categoryTabBar: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.indigo)

                    Text("Active Ports")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    refreshPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isLoading ? 360 : 0))
                        .animation(isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isLoading)
                }
                .buttonStyle(.plain)
                .help("Segarkan port aktif")
            }

            // Segmented Tab Bar Pills
            HStack(spacing: 6) {
                ForEach(MenuBarPortCategory.allCases) { cat in
                    let isSelected = selectedCategory == cat
                    let count = portsForCategory(cat).count

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedCategory = cat
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 10, weight: .semibold))

                            Text(cat.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))

                            // Counter badge
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? cat.color : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Port List Content

    private var portListContent: some View {
        let currentPorts = portsForCategory(selectedCategory)

        return Group {
            if isLoading && ports.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Memindai port...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if currentPorts.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: selectedCategory.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text("Tidak ada port \(selectedCategory.rawValue.lowercased()) aktif")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(currentPorts) { port in
                            MenuBarPortRow(
                                item: port,
                                isTerminating: terminatingPIDs.contains(port.pid),
                                onStop: { force in
                                    stopPort(port, force: force)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Footer Toolbar

    private var footerToolbar: some View {
        HStack {
            Text("\(portsForCategory(selectedCategory).count) port berjalan")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                NotificationCenter.default.post(name: .openDashboardRequest, object: nil)
            } label: {
                HStack(spacing: 4) {
                    Text("Port Manager Lengkap")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.indigo)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions & Filtering

    private func refreshPorts() {
        isLoading = true
        Task {
            let active = await service.fetchActivePorts()
            await MainActor.run {
                self.ports = active
                self.isLoading = false
            }
        }
    }

    private func stopPort(_ port: PortProcessInfo, force: Bool) {
        let pid = port.pid
        let name = port.processName
        let portNum = port.port

        terminatingPIDs.insert(pid)

        Task {
            do {
                try await service.killProcess(pid: pid, force: force)
                try? await Task.sleep(nanoseconds: 180_000_000)

                let updated = await service.fetchActivePorts()
                await MainActor.run {
                    self.ports = updated
                    self.terminatingPIDs.remove(pid)
                    self.statusMessage = "Port \(portNum) (\(name)) dihentikan"

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if self.statusMessage?.contains("\(portNum)") == true {
                            self.statusMessage = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.terminatingPIDs.remove(pid)
                    self.statusMessage = "Gagal menghentikan PID \(pid)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.statusMessage = nil
                    }
                }
            }
        }
    }

    private func portsForCategory(_ category: MenuBarPortCategory) -> [PortProcessInfo] {
        ports.filter { item in
            let p = item.port
            let name = item.processName.lowercased()

            switch category {
            case .web:
                // Port standar web & dev HTTP
                let isWebPort = [80, 443, 8080, 8000, 8888, 8828, 8829].contains(p) ||
                    (3000...3010).contains(p) || (5000...5010).contains(p) ||
                    (5173...5180).contains(p) || (8000...8090).contains(p) ||
                    (4200...4210).contains(p) || (9000...9010).contains(p)

                let isWebProcess = name.contains("php") || name.contains("vite") ||
                    name.contains("next") || name.contains("nuxt") || name.contains("caddy") ||
                    name.contains("nginx") || name.contains("apache") || name.contains("rails") ||
                    name.contains("django") || name.contains("flask") || name.contains("uvicorn") ||
                    name.contains("gunicorn") || name.contains("express") || name.contains("fastify") ||
                    name.contains("puma") || name.contains("hugo")

                return isWebPort || isWebProcess

            case .dev:
                // Developer runtime, compiler, watcher, local AI
                let isDevProcess = name.contains("air") || name.contains("bun") ||
                    name.contains("node") || name.contains("python") || name.contains("go") ||
                    name.contains("cargo") || name.contains("rust") || name.contains("docker") ||
                    name.contains("orbstack") || name.contains("antigravity") || name.contains("code") ||
                    name.contains("cursor") || name.contains("windsurf") || name.contains("language_server") ||
                    name.contains("ollama") || name.contains("electron") || name.contains("java")

                let isDevPort = p == 9229 || p == 8828 || p == 8829 ||
                    (3000...3010).contains(p) || (5173...5180).contains(p) || (8000...8090).contains(p)

                return isDevProcess || isDevPort

            case .database:
                // Database engine ports & daemons
                let isDbPort = [5432, 3306, 6379, 27017, 1433, 9042, 8086, 9200, 26257].contains(p)
                let isDbProcess = name.contains("postgres") || name.contains("mysql") ||
                    name.contains("redis") || name.contains("mongo") || name.contains("mariadb") ||
                    name.contains("memcached") || name.contains("clickhouse") || name.contains("sqlite")

                return isDbPort || isDbProcess
            }
        }
    }
}

// MARK: - MenuBarPortRow

private struct MenuBarPortRow: View {
    let item: PortProcessInfo
    let isTerminating: Bool
    let onStop: (_ force: Bool) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Port Number Badge
            Text(verbatim: item.portString)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.indigo)
                .frame(width: 52, alignment: .leading)

            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 24, height: 24)

                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: item.fallbackSymbolName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Process Name & PID
            VStack(alignment: .leading, spacing: 1) {
                Text(item.processName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(verbatim: "PID \(item.pidString) • \(item.displayAddress)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Stop Action Button
            if isTerminating {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 24, height: 24)
            } else {
                Button {
                    onStop(false)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Stop")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.red.opacity(isHovered ? 0.18 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Hentikan proses port ini")

                // Menu Opsi Lainnya
                Menu {
                    Button(role: .destructive) {
                        onStop(true)
                    } label: {
                        Label("Paksa Berhenti (SIGKILL)", systemImage: "bolt.fill")
                    }

                    Divider()

                    if let url = item.localURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Buka \(url.absoluteString)", systemImage: "safari")
                        }
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.portString, forType: .string)
                    } label: {
                        Label("Salin Port (\(item.portString))", systemImage: "number")
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("kill -9 \(item.pidString)", forType: .string)
                    } label: {
                        Label("Salin: kill -9 \(item.pidString)", systemImage: "terminal")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .onHover { hover in
            isHovered = hover
        }
    }
}
