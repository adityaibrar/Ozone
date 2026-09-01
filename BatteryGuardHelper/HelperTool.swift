// HelperTool.swift
// BatteryGuardHelper — Implementasi XPC protocol di privileged daemon
//
// Charge limiting menggunakan pendekatan software polling (sama seperti AlDente):
//   - Monitor battery % setiap 15 detik via DispatchSourceTimer
//   - Saat battery% >= limit → tulis CH0B = 0x02 (stop charging)
//   - Saat battery% <= limit - hysteresis → tulis CH0B = 0x00 (allow charging)
//   - Hysteresis default 2% mencegah toggling terlalu cepat
//
// PERSISTENT CONFIG:
//   Limit disimpan ke /Library/Application Support/BatteryGuard/charge_limit.json
//   agar daemon bisa auto-restore saat boot tanpa menunggu Main App.

import Foundation
import IOKit

// MARK: - Persistent Charge Limit Config

/// Model data untuk persistensi charge limit ke disk.
/// Disimpan sebagai JSON agar mudah di-debug dan di-inspect manual.
struct PersistentChargeLimitConfig: Codable {
    let limit: Int
    let enabled: Bool
    let timestamp: Date
}

/// Utilitas baca/tulis config charge limit ke file JSON di path persistent.
///
/// Path: `/Library/Application Support/BatteryGuard/charge_limit.json`
/// - Helper berjalan sebagai root → punya akses tulis ke /Library/
/// - Path ini survive reboot
/// - Terpisah dari UserDefaults domain Main App maupun Helper
enum PersistentConfigStore {

    /// Path lengkap file config
    static let configDir = "/Library/Application Support/BatteryGuard"
    static let configPath = "\(configDir)/charge_limit.json"

    /// Simpan config ke disk (thread-safe, atomic write)
    static func save(limit: Int, enabled: Bool) {
        let config = PersistentChargeLimitConfig(
            limit: limit,
            enabled: enabled,
            timestamp: Date()
        )

        do {
            // Pastikan directory ada
            let fm = FileManager.default
            if !fm.fileExists(atPath: configDir) {
                try fm.createDirectory(atPath: configDir,
                                       withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o755])
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(config)

            // Atomic write: tulis ke temp dulu, lalu rename
            let url = URL(fileURLWithPath: configPath)
            try data.write(to: url, options: .atomic)

            NSLog("[PersistentConfig] ✅ Saved: limit=%d%%, enabled=%@",
                  limit, enabled ? "true" : "false")
        } catch {
            NSLog("[PersistentConfig] ❌ Gagal save: %@", error.localizedDescription)
        }
    }

    /// Baca config dari disk. Return nil jika file tidak ada atau corrupt.
    static func load() -> PersistentChargeLimitConfig? {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            NSLog("[PersistentConfig] File tidak ditemukan, skip restore")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(PersistentChargeLimitConfig.self, from: data)
            NSLog("[PersistentConfig] ✅ Loaded: limit=%d%%, enabled=%@, timestamp=%@",
                  config.limit, config.enabled ? "true" : "false",
                  ISO8601DateFormatter().string(from: config.timestamp))
            return config
        } catch {
            NSLog("[PersistentConfig] ⚠️ Gagal load (corrupt?): %@", error.localizedDescription)
            return nil
        }
    }
}

// MARK: - Helper Tool

final class HelperTool: NSObject, BatteryGuardXPCProtocol {

    static let version = "1.1.0"

    /// Shared ChargeMonitor — satu instance per daemon, digunakan bersama antara
    /// auto-restore (saat boot) dan XPC commands (dari Main App).
    /// Static agar `main.swift` bisa akses untuk auto-restore tanpa XPC.
    static let sharedMonitor = ChargeMonitor()

    private var isMonitoring = false
    private var currentLimit = 100

    // MARK: - Init

    override init() {
        super.init()
        // Sinkronkan state lokal dengan shared monitor jika sudah berjalan
        // (misalnya dari auto-restore di main.swift)
        if Self.sharedMonitor.isCurrentlyMonitoring {
            isMonitoring = true
            currentLimit = Self.sharedMonitor.currentActiveLimit
        }
    }

    // MARK: - applyChargeLimit

    /// Terapkan charge limit dengan nilai persentase bebas (20–100).
    ///
    /// Mekanisme identik dengan AlDente: software polling + SMC CH0B key
    ///   - Battery% >= limit  → CH0B = 0x02 (inhibit/stop charging)
    ///   - Battery% < limit-2 → CH0B = 0x00 (allow charging normal)
    func applyChargeLimit(_ limit: Int, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] applyChargeLimit: %d%%", limit)

        guard limit >= 20 && limit <= 100 else {
            reply(false, "Limit harus antara 20–100%")
            return
        }

        currentLimit = limit

        if limit == 100 {
            // 100% = tidak ada limit — hentikan monitoring dan izinkan charging penuh
            if isMonitoring {
                Self.sharedMonitor.stopMonitoring()
                isMonitoring = false
            }
            // Persist: disabled
            PersistentConfigStore.save(limit: 100, enabled: false)
            NSLog("[HelperTool] Limit = 100%%, charge limit dinonaktifkan")
            reply(true, nil)
            return
        }

        if isMonitoring {
            // Monitoring sudah jalan — cukup update limitnya saja
            Self.sharedMonitor.updateLimit(limit)
        } else {
            // Mulai monitoring fresh
            Self.sharedMonitor.startMonitoring(limit: limit)
            isMonitoring = true
        }

        // Persist: simpan limit baru ke disk agar survive reboot
        PersistentConfigStore.save(limit: limit, enabled: true)

        NSLog("[HelperTool] ✅ Monitoring aktif, limit: %d%%", limit)
        reply(true, nil)
    }

    // MARK: - disableChargeLimit

    /// Nonaktifkan charge limit — baterai boleh isi hingga 100%
    func disableChargeLimit(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] disableChargeLimit dipanggil")
        Self.sharedMonitor.stopMonitoring()
        isMonitoring = false
        currentLimit = 100

        // Persist: tandai sebagai disabled
        PersistentConfigStore.save(limit: 100, enabled: false)

        reply(true, nil)
    }

    // MARK: - Discharge Mode (belum diimplementasikan)

    func setDischargeModeEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[HelperTool] setDischargeModeEnabled: %@ — belum diimplementasikan",
              enabled ? "true" : "false")
        reply(false, "Discharge mode belum tersedia di versi ini.")
    }

    // MARK: - Version & Uninstall

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply(HelperTool.version)
    }

    func uninstallHelper(reply: @escaping (Bool) -> Void) {
        // Unregister daemon ditangani dari sisi Main App via SMAppService
        reply(false)
    }
}
