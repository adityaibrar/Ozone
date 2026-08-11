// TemperatureMonitor.swift
// BatteryGuard — Monitor suhu via AppleSMC (SMC)

import Foundation
import IOKit

// MARK: - Temperature Monitor Protocol

protocol TemperatureProviding {
    func fetchTemperatures() -> SystemTemperatures
}

// MARK: - TemperatureMonitor

/// Monitor suhu — membaca CPU temp dan Battery temp melalui SMC API.
final class TemperatureMonitor: ObservableObject {

    // MARK: - Published

    @Published var temperatures: SystemTemperatures = .empty

    // MARK: - Private

    /// DispatchSourceTimer berjalan di background queue — tidak memblokir main thread
    private var timerSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.batteryguard.temp-monitor", qos: .utility)
    private let pollingInterval: TimeInterval
    private let provider: TemperatureProviding

    // MARK: - Init

    init(pollingInterval: TimeInterval = 5.0) {
        self.pollingInterval = pollingInterval
        self.provider = SMCTemperatureProvider()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        // Baca pertama kali di background
        queue.async { [weak self] in
            self?.fetchAndPublish()
        }

        // Setup DispatchSourceTimer di background queue
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(500) // toleransi ±500ms — suhu tidak butuh presisi tinggi
        )
        source.setEventHandler { [weak self] in
            self?.fetchAndPublish()
        }
        source.resume()
        timerSource = source
    }

    func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil
    }

    // MARK: - Private
    // Dipanggil dari background queue — synchronous fetch (tidak perlu async)

    private func fetchAndPublish() {
        let result = provider.fetchTemperatures()
        DispatchQueue.main.async { [weak self] in
            self?.temperatures = result
        }
    }
}
