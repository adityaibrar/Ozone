// PreferencesStore.swift
// BatteryGuard — UserDefaults wrapper untuk semua settings aplikasi

import Foundation
import SwiftUI
import ServiceManagement

// MARK: - PreferencesStore

/// Centralized store untuk semua user preferences
/// Menggunakan @AppStorage untuk SwiftUI binding langsung
final class PreferencesStore: ObservableObject {

    static let shared = PreferencesStore()

    // MARK: - Charge Limiter

    /// Batas pengisian yang di-set user (20–100%)
    @AppStorage("chargeLimit") var chargeLimit: Int = 80
    /// Apakah fitur charge limiter aktif
    @AppStorage("isChargeLimitEnabled") var isChargeLimitEnabled: Bool = false
    /// Apakah discharge mode aktif
    @AppStorage("isDischargeModeEnabled") var isDischargeModeEnabled: Bool = false

    // MARK: - Startup

    /// Buka aplikasi secara otomatis saat login
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLoginState()
        }
    }

    // MARK: - Notifications

    /// Notifikasi saat limit tercapai
    @AppStorage("notifyOnLimitReached") var notifyOnLimitReached: Bool = true
    /// Notifikasi saat baterai di bawah threshold
    @AppStorage("notifyOnLowBattery") var notifyOnLowBattery: Bool = true
    /// Threshold baterai rendah (%)
    @AppStorage("lowBatteryThreshold") var lowBatteryThreshold: Int = 20

    // MARK: - Temperature

    /// Apakah temperature monitoring aktif
    @AppStorage("temperatureMonitoringEnabled") var temperatureMonitoringEnabled: Bool = false
    /// Threshold suhu untuk heat protection (°C)
    @AppStorage("heatProtectionThreshold") var heatProtectionThreshold: Double = 45.0
    /// Apakah heat protection aktif
    @AppStorage("isHeatProtectionEnabled") var isHeatProtectionEnabled: Bool = false

    // MARK: - Menu Bar Display

    /// Mode kompak (kurangi info di menu bar)
    @AppStorage("isCompactMenuBar") var isCompactMenuBar: Bool = false
    /// Tampilkan network speed di menu bar
    @AppStorage("showNetworkSpeed") var showNetworkSpeed: Bool = true
    /// Tampilkan CPU/system temperature di menu bar
    @AppStorage("showTemperature") var showTemperature: Bool = false
    /// Tampilkan RAM usage di menu bar
    @AppStorage("showRAMUsage") var showRAMUsage: Bool = true
    /// Tampilkan persentase baterai di menu bar
    @AppStorage("showBatteryPercent") var showBatteryPercent: Bool = true
    /// Tampilkan CPU usage di menu bar
    @AppStorage("showCPUUsage") var showCPUUsage: Bool = true
    /// Tampilkan GPU usage di menu bar
    @AppStorage("showGPUUsage") var showGPUUsage: Bool = true

    // MARK: - Polling Intervals

    /// Interval polling baterai (detik)
    @AppStorage("batteryPollingInterval") var batteryPollingInterval: Double = 2.0
    /// Interval polling RAM & network (detik)
    @AppStorage("systemPollingInterval") var systemPollingInterval: Double = 1.0
    /// Interval polling temperature (detik)
    @AppStorage("tempPollingInterval") var tempPollingInterval: Double = 3.0

    // MARK: - Appearance

    /// Tema aplikasi: "system", "light", "dark"
    @AppStorage("colorScheme") var colorScheme: String = "system"

    // MARK: - Mouse Natural Scrolling

    /// Master toggle: pisahkan scroll direction mouse (normal) vs trackpad (natural)
    /// Menggunakan CGEventTap — tidak mengubah System Settings apapun.
    /// Default true: otomatis aktif saat Accessibility permission tersedia
    @AppStorage("mouseAutoScrollEnabled") var mouseAutoScrollEnabled: Bool = true
    /// Balik arah scroll vertikal pada mouse fisik
    @AppStorage("mouseInvertVertical") var mouseInvertVertical: Bool = true
    /// Balik arah scroll horizontal pada mouse fisik
    @AppStorage("mouseInvertHorizontal") var mouseInvertHorizontal: Bool = false

    // MARK: - Keyboard Monitor

    /// Master toggle: aktifkan keyboard press counter
    /// Default false — opt-in karena ini fitur monitoring keyboard (privacy consideration)
    @AppStorage("keyboardMonitorEnabled") var keyboardMonitorEnabled: Bool = false

    // MARK: - Calibration

    /// Timestamp kalibrasi terakhir
    @AppStorage("lastCalibrationDate") var lastCalibrationDateInterval: Double = 0
    var lastCalibrationDate: Date? {
        get {
            lastCalibrationDateInterval > 0
                ? Date(timeIntervalSince1970: lastCalibrationDateInterval)
                : nil
        }
        set {
            lastCalibrationDateInterval = newValue?.timeIntervalSince1970 ?? 0
        }
    }

    // MARK: - Helper

    /// Bundle ID helper untuk SMAppService
    let helperBundleID = "com.ibrardev.Ozone.Helper"

    private init() {
        // Sinkronisasi status riil dengan preference di UserDefaults saat init
        let isRegistered = SMAppService.mainApp.status == .enabled
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }
    }
    
    private func updateLaunchAtLoginState() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Gagal mengubah status Launch at Login: \(error.localizedDescription)")
        }
    }
}

