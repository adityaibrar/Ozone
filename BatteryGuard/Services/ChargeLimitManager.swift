// ChargeLimitManager.swift
// BatteryGuard — State management untuk charge limit + komunikasi ke helper

import Foundation
import Combine

// MARK: - ChargeLimitManager

/// Mengelola state charge limit dan berkomunikasi dengan HelperTool via XPC
final class ChargeLimitManager: ObservableObject {

    // MARK: - Published State

    @Published var state: ChargeLimitState = .default
    @Published var isApplying: Bool = false
    @Published var lastError: String?
    @Published var helperVersion: String?

    // MARK: - Dependencies

    private let connection: HelperConnection
    private let prefs: PreferencesStore

    // MARK: - Init

    init(
        connection: HelperConnection = .shared,
        prefs: PreferencesStore = .shared
    ) {
        self.connection = connection
        self.prefs = prefs

        // Load state dari preferences
        state = ChargeLimitState(
            limitPercent: prefs.chargeLimit,
            isEnabled: prefs.isChargeLimitEnabled,
            dischargeModeEnabled: prefs.isDischargeModeEnabled
        )
    }

    // MARK: - Restore on Launch (Layer 2 — backup)

    /// Dipanggil saat Main App launch untuk re-sinkronkan limit ke helper.
    ///
    /// Helper daemon sudah bisa auto-restore dari persistent config (Layer 1),
    /// tapi ini berfungsi sebagai backup untuk memastikan sinkronisasi:
    /// - Jika user mengubah limit dari UI sebelum restart
    /// - Jika persistent config file corrupt atau terhapus
    /// - Sebagai heartbeat pertama dari Main App ke helper
    func restoreOnLaunch() {
        guard state.isEnabled, state.limitPercent < 100 else {
            NSLog("[ChargeLimitManager] restoreOnLaunch: limit disabled atau 100%%, skip")
            return
        }

        NSLog("[ChargeLimitManager] 🔄 restoreOnLaunch: re-apply limit %d%% ke helper",
              state.limitPercent)
        applyCurrentState()
    }

    // MARK: - Set Charge Limit

    /// Set limit charging (20-100%) dan apply ke helper
    func setChargeLimit(_ percent: Int) {
        let clamped = max(20, min(100, percent))
        state.limitPercent = clamped
        prefs.chargeLimit = clamped

        if state.isEnabled {
            applyCurrentState()
        }
    }

    // MARK: - Toggle Enable

    /// Enable/disable charge limiter
    func toggleEnabled() {
        state.isEnabled.toggle()
        prefs.isChargeLimitEnabled = state.isEnabled

        if state.isEnabled {
            applyCurrentState()
        } else {
            disableLimit()
        }
    }

    func setEnabled(_ enabled: Bool) {
        state.isEnabled = enabled
        prefs.isChargeLimitEnabled = enabled

        if enabled {
            applyCurrentState()
        } else {
            disableLimit()
        }
    }

    // MARK: - Discharge Mode

    /// Toggle discharge mode
    func toggleDischargeMode() {
        state.dischargeModeEnabled.toggle()
        prefs.isDischargeModeEnabled = state.dischargeModeEnabled
        applyDischargeMode()
    }

    // MARK: - Update from BatteryMonitor

    /// Di-panggil oleh SystemStatsViewModel saat battery status berubah
    /// Cek apakah baterai sudah mencapai limit
    func checkLimitReached(currentPercent: Int) -> Bool {
        guard state.isEnabled else { return false }
        return currentPercent >= state.limitPercent
    }

    // MARK: - Verify Helper Connection

    func verifyHelperConnection() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let version = try await self.connection.getHelperVersion()
                self.helperVersion = version
                self.lastError = nil
            } catch {
                self.helperVersion = nil
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Private

    private func applyCurrentState() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isApplying = true
            defer { self.isApplying = false }
            do {
                try await self.connection.applyChargeLimit(self.state.limitPercent)
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func disableLimit() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isApplying = true
            defer { self.isApplying = false }
            do {
                try await self.connection.disableChargeLimit()
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func applyDischargeMode() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await self.connection.setDischargeMode(self.state.dischargeModeEnabled)
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }
}
