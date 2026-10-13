// PortManagerView.swift
// BatteryGuard / Ozone — UI Port Manager & Process Killer
// Desain: Modern Clean Minimalist dengan sentuhan Soft UI
// Toolbar terpadu: Kategori, Search, dan Custom Protocol Selector dalam satu baris kompak

import SwiftUI
import AppKit

// MARK: - PortManagerView

struct PortManagerView: View {
    @StateObject private var vm = PortManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // ── Banner Feedback Notifikasi ───────────────────────────────────
            if let success = vm.successMessage {
                notificationBanner(text: success, isError: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let error = vm.errorMessage {
                notificationBanner(text: error, isError: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // ── 1. Header Ringkas ────────────────────────────────────
                    headerSection

                    // ── 2. Unified Controls Toolbar (Kategori, Search, Protokol) ─
                    controlsToolbar

                    // ── 3. Tabel Port Bersih & Rapat ─────────────────────────
                    portListSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.35))
        .onAppear {
            vm.loadPorts()
        }
        .confirmationDialog(
            "Konfirmasi Penghentian Proses Sistem",
            isPresented: $vm.showSystemKillAlert,
            titleVisibility: .visible
        ) {
            Button("Hentikan Proses", role: .destructive) {
                vm.confirmSystemKill(force: false)
            }
            Button("Paksa Berhenti (SIGKILL)", role: .destructive) {
                vm.confirmSystemKill(force: true)
            }
            Button("Batal", role: .cancel) {
                vm.pendingKillTarget = nil
            }
        } message: {
            if let target = vm.pendingKillTarget {
                Text("\(target.processName) (PID: \(target.pidString)) adalah proses sistem macOS. Menghentikannya dapat memengaruhi layanan latar belakang.")
            } else {
                Text("Proses ini adalah layanan latar belakang sistem macOS.")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.successMessage)
        .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
    }

    // MARK: - 1. Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon Soft UI
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: "network")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.indigo)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Port Manager")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    // Counter badge total aktif
                    Text(verbatim: "\(vm.totalCount) aktif")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.1))
                        .clipShape(Capsule())
                }

                Text("Pantau dan kendalikan proses port jaringan di latar belakang.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toolbar Kontrol Kanan (Auto-Refresh & Segarkan)
            HStack(spacing: 8) {
                // Auto Refresh Toggle
                HStack(spacing: 5) {
                    Toggle("Auto Refresh", isOn: $vm.autoRefreshEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.indigo)

                    Text("3s")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
                )

                // Refresh Button
                Button {
                    vm.loadPorts()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(vm.isLoading ? 360 : 0))
                            .animation(vm.isLoading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: vm.isLoading)

                        Text("Segarkan")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
            }
        }
    }

    // MARK: - 2. Unified Controls Toolbar (Kategori + Search + Protokol Custom)

    private var controlsToolbar: some View {
        HStack(spacing: 10) {
            // Sisi Kiri: Tab Kategori Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(PortCategory.allCases) { cat in
                        let isSelected = vm.selectedCategory == cat
                        let count: Int = {
                            switch cat {
                            case .all: return vm.totalCount
                            case .web: return vm.webCount
                            case .dev: return vm.devCount
                            case .database: return vm.databaseCount
                            case .system: return vm.systemCount
                            case .other: return vm.otherCount
                            }
                        }()

                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                                vm.selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.iconName)
                                    .font(.system(size: 10, weight: .semibold))

                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))

                                Text(verbatim: "\(count)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(isSelected ? Color.white.opacity(0.24) : Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? Color.indigo : Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 8)

            // Sisi Kanan: Search Bar + Custom Protocol Segmented Control
            HStack(spacing: 6) {
                // Search Input Box
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Cari port, proses, PID...", text: $vm.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .rounded))

                    if !vm.searchQuery.isEmpty {
                        Button {
                            vm.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .frame(width: 175)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
                )

                // Custom Soft UI Protocol Segmented Selector (Semua | TCP | UDP)
                customProtocolSelector
            }
        }
    }

    // MARK: - Custom Protocol Selector (Soft UI)

    private var customProtocolSelector: some View {
        HStack(spacing: 2) {
            ForEach(PortProtocolFilter.allCases) { filter in
                let isSelected = vm.selectedProtocol == filter
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                        vm.selectedProtocol = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(isSelected ? Color.indigo : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 3. Port List Section

    private var portListSection: some View {
        VStack(spacing: 0) {
            let list = vm.filteredPorts

            if vm.isLoading && list.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.indigo)
                    Text("Memindai port aktif...")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else if list.isEmpty {
                emptyStateView
            } else {
                // Table header
                HStack(spacing: 12) {
                    Text("PORT")
                        .frame(width: 75, alignment: .leading)
                    Text("PROSES & APLIKASI")
                        .frame(minWidth: 210, alignment: .leading)
                    Text("BIND & PROTOKOL")
                        .frame(width: 150, alignment: .leading)
                    Text("STATUS")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Text("AKSI")
                        .frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

                Divider().opacity(0.25)

                // List Items Container
                VStack(spacing: 1) {
                    ForEach(list) { item in
                        PortRowView(
                            item: item,
                            isTerminating: vm.terminatingPIDs.contains(item.pid),
                            onStop: { force in
                                vm.requestKill(port: item, force: force)
                            }
                        )
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.45))
                .padding(.top, 18)

            Text("Tidak Ada Port Ditemukan")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if !vm.searchQuery.isEmpty {
                Text("Tidak ditemukan port atau proses yang cocok dengan \"\(vm.searchQuery)\".")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Tidak ada port yang aktif pada filter ini.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Notification Banner

    private func notificationBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isError ? Color.red : Color.green)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                if isError {
                    vm.errorMessage = nil
                } else {
                    vm.successMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(isError ? Color.red.opacity(0.2) : Color.green.opacity(0.2)),
            alignment: .bottom
        )
    }
}

// MARK: - PortRowView

private struct PortRowView: View {
    let item: PortProcessInfo
    let isTerminating: Bool
    let onStop: (_ force: Bool) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // ── 1. Port Number ───────────────────────────────────────────────
            Text(verbatim: item.portString)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.indigo)
                .frame(width: 75, alignment: .leading)

            // ── 2. Process & App Info ────────────────────────────────────────
            HStack(spacing: 8) {
                // Icon squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 26, height: 26)

                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: item.fallbackSymbolName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.processName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(verbatim: "PID \(item.pidString)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)

                        Text(item.user)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minWidth: 210, alignment: .leading)
            .help(item.commandPath ?? "\(item.processName) (PID: \(item.pidString))")

            // ── 3. Bind Address & Protocol ───────────────────────────────────
            HStack(spacing: 5) {
                Text(item.displayAddress)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)

                Text(item.protocolType.rawValue)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(item.protocolType == .tcp ? Color.blue : Color.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background((item.protocolType == .tcp ? Color.blue : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
            }
            .frame(width: 150, alignment: .leading)

            // ── 4. Status Indicator ──────────────────────────────────────────
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)

                Text(item.state)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.08))
            .clipShape(Capsule())
            .frame(width: 80, alignment: .leading)

            Spacer()

            // ── 5. Action Buttons (Stop & Context Menu) ───────────────────────
            HStack(spacing: 4) {
                if isTerminating {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 22, height: 22)
                } else {
                    // Tombol Stop: Soft Red yang tenang, lebih terang saat hover
                    Button {
                        onStop(false)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 7))
                            Text("Stop")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(isHovered ? 0.16 : 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Hentikan proses (SIGTERM)")

                    // Menu Opsi Tambahan (Context Actions)
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
                                Label("Buka di Browser (\(url.absoluteString))", systemImage: "safari")
                            }

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            } label: {
                                Label("Salin URL", systemImage: "doc.on.doc")
                            }
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.portString, forType: .string)
                        } label: {
                            Label("Salin Nomor Port (\(item.portString))", systemImage: "number")
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("kill -9 \(item.pidString)", forType: .string)
                        } label: {
                            Label("Salin: kill -9 \(item.pidString)", systemImage: "terminal")
                        }

                        if let path = item.commandPath {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            } label: {
                                Label("Salin Path Binary", systemImage: "folder")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(isHovered ? 0.12 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20, height: 20)
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        )
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hover
            }
        }
    }
}
