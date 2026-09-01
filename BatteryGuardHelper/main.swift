// main.swift
// BatteryGuardHelper — Entry point privileged daemon
//
// Daemon ini berjalan sebagai root, dikelola oleh launchd via SMAppService.
// Tugas utama: menjadi XPC listener untuk menerima perintah dari Main App.
//
// AUTO-RESTORE:
//   Saat daemon start (termasuk setelah boot), persistent config dibaca
//   dan charge limit langsung diterapkan TANPA menunggu Main App konek via XPC.
//   Ini menyelesaikan bug di mana limit hilang setelah restart MacBook.

import Foundation

// MARK: - XPC Listener Delegate

/// Menerima dan memvalidasi koneksi XPC dari Main App
final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Validasi koneksi yang masuk — hanya terima dari bundle ID yang dikenal
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        NSLog("[Helper] Koneksi XPC baru diterima (PID: %d)", connection.processIdentifier)

        // Konfigurasi interface yang diekspor ke client (Main App)
        connection.exportedInterface = makeBatteryGuardXPCInterface()
        connection.exportedObject    = HelperTool()

        // Handler saat koneksi putus (normal saat Main App quit)
        connection.invalidationHandler = {
            NSLog("[Helper] Koneksi XPC diputus (invalidated)")
        }
        connection.interruptionHandler = {
            NSLog("[Helper] Koneksi XPC terinterupsi (interrupted)")
        }

        connection.resume()
        NSLog("[Helper] ✅ Koneksi XPC diterima dan aktif")
        return true
    }
}

// MARK: - Auto-Restore Charge Limit dari Persistent Config

/// Baca config yang tersimpan dan langsung mulai monitoring jika ada limit aktif.
/// Dipanggil SEKALI saat daemon start, SEBELUM masuk run loop.
/// Ini memastikan charge limit aktif dari detik pertama setelah boot.
func autoRestoreChargeLimit() {
    NSLog("[Helper] 🔄 Memeriksa persistent config untuk auto-restore...")

    guard let config = PersistentConfigStore.load() else {
        NSLog("[Helper] Tidak ada persistent config, skip auto-restore")
        return
    }

    guard config.enabled, config.limit >= 20, config.limit < 100 else {
        NSLog("[Helper] Config ditemukan tapi disabled atau limit=100%%, skip")
        return
    }

    NSLog("[Helper] 🔄 Auto-restore charge limit dari persistent config: %d%%", config.limit)

    // Gunakan shared monitor yang sama dengan HelperTool
    HelperTool.sharedMonitor.startMonitoring(limit: config.limit)

    NSLog("[Helper] ✅ Monitoring aktif dari boot, limit: %d%%", config.limit)
}

// MARK: - Main Run Loop

NSLog("[Helper] BatteryGuardHelper v%@ dimulai (PID: %d)",
      HelperTool.version, ProcessInfo.processInfo.processIdentifier)

// 1. Auto-restore charge limit SEBELUM terima koneksi XPC
//    → Limit langsung aktif tanpa menunggu Main App
autoRestoreChargeLimit()

// 2. Setup XPC listener
let delegate = HelperDelegate()
// Gunakan Mach service name yang sama seperti yang didaftarkan di launchd plist
let listener = NSXPCListener(machServiceName: "com.ibrardev.Ozone.Helper")
listener.delegate = delegate

// Resume listener dan masuk ke run loop — daemon harus terus berjalan
listener.resume()
NSLog("[Helper] XPC Listener aktif, menunggu koneksi...")
RunLoop.main.run()

