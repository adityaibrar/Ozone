// PortManagerViewModel.swift
// BatteryGuard / Ozone — ViewModel untuk fitur Port Manager & Process Killer
// Menangani state port, pencarian, filter kategori, auto-refresh, dan aksi terminasi

import Foundation
import SwiftUI
import Combine

// MARK: - Port Protocol Filter

public enum PortProtocolFilter: String, CaseIterable, Identifiable {
    case all = "Semua"
    case tcp = "TCP"
    case udp = "UDP"

    public var id: String { rawValue }
}

// MARK: - PortManagerViewModel

@MainActor
public final class PortManagerViewModel: ObservableObject {

    // MARK: - Dependencies

    private let service: PortMonitorService

    // MARK: - Published State

    @Published public var ports: [PortProcessInfo] = []
    @Published public var isLoading: Bool = false
    @Published public var terminatingPIDs: Set<Int32> = []

    // Filter & Search
    @Published public var searchQuery: String = ""
    @Published public var selectedCategory: PortCategory = .all
    @Published public var selectedProtocol: PortProtocolFilter = .all

    // Auto Refresh
    @Published public var autoRefreshEnabled: Bool = false {
        didSet {
            handleAutoRefreshToggled()
        }
    }

    // Feedback Messages
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil

    // Safety Alert
    @Published public var showSystemKillAlert: Bool = false
    @Published public var pendingKillTarget: PortProcessInfo? = nil

    // Timer Auto-refresh
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Init

    public init(service: PortMonitorService = .shared) {
        self.service = service
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    // MARK: - Computed Properties

    /// Daftar port setelah disaring berdasarkan pencarian teks, kategori, dan protokol
    public var filteredPorts: [PortProcessInfo] {
        ports.filter { item in
            // Filter Kategori
            if selectedCategory != .all && item.category != selectedCategory {
                return false
            }

            // Filter Protokol
            switch selectedProtocol {
            case .all:
                break
            case .tcp:
                if item.protocolType != .tcp { return false }
            case .udp:
                if item.protocolType != .udp { return false }
            }

            // Filter Kata Kunci Pencarian
            if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = searchQuery.lowercased()
                let matchesPort = String(item.port).contains(q)
                let matchesName = item.processName.lowercased().contains(q)
                let matchesPID = String(item.pid).contains(q)
                let matchesUser = item.user.lowercased().contains(q)
                let matchesAddress = item.bindAddress.lowercased().contains(q)

                return matchesPort || matchesName || matchesPID || matchesUser || matchesAddress
            }

            return true
        }
    }

    /// Jumlah port per kategori untuk badge indikator
    public var totalCount: Int { ports.count }
    public var webCount: Int { ports.filter { $0.category == .web }.count }
    public var devCount: Int { ports.filter { $0.category == .dev }.count }
    public var databaseCount: Int { ports.filter { $0.category == .database }.count }
    public var systemCount: Int { ports.filter { $0.category == .system }.count }
    public var otherCount: Int { ports.filter { $0.category == .other }.count }

    // MARK: - Public Actions

    /// Memuat daftar port aktif
    public func loadPorts(silent: Bool = false) {
        if !silent {
            isLoading = true
        }

        Task {
            let fetched = await service.fetchActivePorts()
            self.ports = fetched
            self.isLoading = false
        }
    }

    /// Permintaan penghentian proses — jika proses sistem, tampilkan dialog konfirmasi terlebih dahulu
    public func requestKill(port: PortProcessInfo, force: Bool = false) {
        if port.isSystemProcess {
            pendingKillTarget = port
            showSystemKillAlert = true
        } else {
            executeKill(port: port, force: force)
        }
    }

    /// Eksekusi penghentian proses
    public func executeKill(port: PortProcessInfo, force: Bool = false) {
        let pid = port.pid
        let portNumber = port.port
        let name = port.processName

        terminatingPIDs.insert(pid)
        errorMessage = nil

        Task {
            do {
                try await service.killProcess(pid: pid, force: force)

                // Beri jeda singkat agar sistem OS memperbarui status socket
                try? await Task.sleep(nanoseconds: 200_000_000)

                // Refresh data
                let updated = await service.fetchActivePorts()
                self.ports = updated
                self.terminatingPIDs.remove(pid)

                // Notifikasi sukses
                self.successMessage = "Berhasil menghentikan \(name) (PID \(pid)) di Port \(portNumber)"

                // Auto dismiss pesan sukses setelah 3.5 detik
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    if self?.successMessage?.contains("\(pid)") == true {
                        self?.successMessage = nil
                    }
                }
            } catch {
                self.terminatingPIDs.remove(pid)
                self.errorMessage = error.localizedDescription

                // Auto dismiss error setelah 5 detik
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.errorMessage = nil
                }
            }
        }
    }

    /// Hentikan target sistem yang telah dikonfirmasi oleh pengguna
    public func confirmSystemKill(force: Bool = false) {
        guard let target = pendingKillTarget else { return }
        pendingKillTarget = nil
        executeKill(port: target, force: force)
    }

    // MARK: - Auto Refresh Management

    private func handleAutoRefreshToggled() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil

        if autoRefreshEnabled {
            autoRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 detik
                    guard let self = self, self.autoRefreshEnabled else { break }
                    self.loadPorts(silent: true)
                }
            }
        }
    }
}
