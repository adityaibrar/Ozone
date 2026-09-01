// MouseScrollService.swift
// BatteryGuard — Pemisahan scroll direction: mouse = normal, trackpad = natural.
//
// ARSITEKTUR & CARA KERJA (Referensi: vorssaint-utils & Scroll-Reverser):
// - Menggunakan CGEventTap di level HID (.cghidEventTap) dengan .headInsertEventTap
// - Deteksi Smart Device:
//   * Discrete event (isContinuous == 0) -> Mouse Fisik Wheel -> Dibalik (Natural OFF)
//   * Continuous event dengan gesture/momentum phase -> Trackpad -> Dibiarkan (Natural ON)
//   * Continuous event tanpa gesture phase (mouse wheel canggih/driver) -> Mouse Fisik -> Dibalik
//   * Grace period 1.0s untuk menyaring transisi gesture phase trackpad
// - Auto Permission Watcher: Timer periodic & NSApplication didBecomeActive observer
// - Auto Re-arm tap saat terjadi .tapDisabledByTimeout atau .tapDisabledByUserInput
// - Delta line, point, dan fixed-point dibalik secara lengkap dan berurutan agar
//   aplikasi macOS modern (Safari, Finder, Xcode, Chrome, dll) menerima delta yang tepat.
//
// PERMISSION: Membutuhkan Accessibility access (System Settings -> Privacy & Security -> Accessibility)

import Foundation
import Cocoa
import Combine
import CoreGraphics

// MARK: - Input Device Type

enum ScrollInputDevice: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case trackpad = "Trackpad"
    case mouse    = "Mouse"
    case none     = "None"

    var icon: String {
        switch self {
        case .trackpad: return "hand.draw.fill"
        case .mouse:    return "computermouse.fill"
        case .none:     return "questionmark.circle"
        }
    }
}

// MARK: - Scroll Wheel Event Traits

struct ScrollWheelEventTraits: Equatable {
    let isContinuous: Bool
    let momentumPhase: Int64
    let scrollPhase: Int64
    let scrollCount: Int64
    let hasPreciseDeltas: Bool
}

// MARK: - Scroll Wheel Classifier Support

enum ScrollWheelSupport {
    /// Jeda waktu (detik) setelah event ber-gesture phase di mana event kontinu tanpa phase
    /// masih diatribusikan ke touch device yang sama (Trackpad / Magic Mouse).
    static let touchGestureGraceSeconds: TimeInterval = 1.0

    /// Tag sintetis internal jika aplikasi meng-inject scroll buatan
    static let syntheticTag: Int64 = 0x564F5253 // "VORS"

    /// Memeriksa apakah event berasal dari scroll wheel mouse fisik (bukan gesture trackpad)
    static func isMouseWheel(
        _ traits: ScrollWheelEventTraits,
        secondsSinceLastGesturePhase: TimeInterval?
    ) -> Bool {
        // Event diskrit (klik-per-klik) selalu merupakan scroll wheel fisik
        if !traits.isContinuous {
            return true
        }

        // Jika tidak memiliki precise scrolling deltas, ini pasti scroll wheel mouse fisik
        if !traits.hasPreciseDeltas {
            return true
        }

        // Jika event membawa momentumPhase atau scrollPhase, ini pasti touch device (Trackpad / Magic Mouse)
        guard traits.momentumPhase == 0, traits.scrollPhase == 0 else {
            return false
        }

        // Trackpad dapat memancarkan transisi event tanpa phase sesaat antara gesture end
        // dan momentum start yang masih membawa scrollCount gesture.
        // Mouse wheel yang melaporkan continuous tidak pernah memancarkan phase,
        // sehingga hanya event yang terjadi tepat setelah phased event yang dianggap touch.
        if traits.scrollCount != 0,
           let elapsed = secondsSinceLastGesturePhase,
           elapsed <= touchGestureGraceSeconds {
            return false
        }

        return true
    }
}

// MARK: - MouseScrollService

final class MouseScrollService: ObservableObject {

    static let shared = MouseScrollService()

    // MARK: - Published State (untuk SwiftUI Binding)

    /// Apakah CGEventTap sedang aktif mencegat scroll events
    @Published private(set) var isActive: Bool = false

    /// Apakah Accessibility permission sudah diberikan oleh user
    @Published private(set) var hasAccessibilityPermission: Bool = false

    /// Device input terakhir yang terdeteksi melakukan scroll
    @Published private(set) var lastDetectedDevice: ScrollInputDevice = .none

    /// Waktu scroll event terakhir
    @Published private(set) var lastEventDate: Date? = nil

    /// Jumlah total event mouse yang telah dibalik (statistik sesi)
    /// Diupdate secara atomik dari CGEventTap thread, di-publish ke main thread
    /// via timer batching — bukan per-event untuk mengurangi context switch
    @Published private(set) var invertedEventCount: Int = 0
    /// Backing atomic counter — nama berbeda dari @Published agar tidak konflik
    /// dengan synthesized property _invertedEventCount milik properti wrapper.
    private var _atomicInvertCount: Int64 = 0

    // MARK: - Private State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let prefs = PreferencesStore.shared
    private static let ownProcessID = Int64(getpid())

    /// Timestamp (ns, event clock) dari event terakhir yang membawa gesture phase
    private var lastGesturePhaseTimestamp: UInt64?

    private var permissionTimer: Timer?
    /// Timer untuk publish invertedEventCount dari background ke main thread (1 detik sekali)
    /// Menggantikan per-event DispatchQueue.main.async di hot path CGEventTap
    private var statsFlushTimer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshPermissionStatus()
        setupPermissionWatcher()
        setupStatsFlushTimer()
    }

    deinit {
        permissionTimer?.invalidate()
        statsFlushTimer?.cancel()
        stop()
    }

    // MARK: - Stats Flush Timer

    /// Publish invertedEventCount dari atomic counter ke @Published var, 1x/detik.
    /// Ini jauh lebih efisien daripada dispatch-per-event dari hot path CGEventTap.
    private func setupStatsFlushTimer() {
        let queue = DispatchQueue(label: "com.batteryguard.scroll-stats", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Baca nilai atomik — OSAtomicAdd64 dengan 0 berfungsi sebagai atomic read
            let current = withUnsafeMutablePointer(to: &self._atomicInvertCount) {
                Int(OSAtomicAdd64(0, $0))
            }
            DispatchQueue.main.async {
                self.invertedEventCount = current
            }
        }
        timer.resume()
        statsFlushTimer = timer
    }

    // MARK: - Permission Watcher Setup

    private func setupPermissionWatcher() {
        // 1. Observer saat aplikasi aktif / kembali ke foreground dari System Settings
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshPermissionStatus()
                if self.hasAccessibilityPermission && self.prefs.mouseAutoScrollEnabled && !self.isActive {
                    self.start()
                }
            }
            .store(in: &cancellables)

        // 2. Observer saat user toggle preferensi di PreferencesStore / UserDefaults
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.prefs.mouseAutoScrollEnabled {
                    if !self.isActive && self.hasAccessibilityPermission {
                        self.start()
                    }
                } else {
                    if self.isActive {
                        self.stop()
                    }
                }
            }
            .store(in: &cancellables)

        // 3. Periodic watcher — interval 15 detik (bukan 1.5) karena:
        //    - AXIsProcessTrusted() adalah IPC call ke securityd
        //    - didBecomeActiveNotification sudah menangani case utama (user balik dari System Settings)
        //    - Timer ini hanya fallback edge case (permission berubah tanpa app ke foreground)
        //    - Saat sudah aktif → timer di-invalidate, tidak perlu polling lagi
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()
            if self.hasAccessibilityPermission != trusted {
                self.refreshPermissionStatus()
            }
            if self.hasAccessibilityPermission && self.prefs.mouseAutoScrollEnabled && !self.isActive {
                self.start()
            }
            // Sudah granted dan aktif → tidak perlu polling lagi
            if trusted && self.isActive {
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    // MARK: - Accessibility Permission

    /// Cek status permission tanpa menampilkan prompt
    func refreshPermissionStatus() {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
            if trusted && self.prefs.mouseAutoScrollEnabled && !self.isActive {
                self.start()
            }
        }
    }

    /// Tampilkan prompt System Settings untuk meminta Accessibility permission & buka System Settings langsung
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Buka langsung jendela Pengaturan Aksesibilitas
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Polling singkat untuk mendeteksi saat user memberikan izin di Settings
        for delay in [1.0, 2.0, 3.5, 5.0, 7.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.refreshPermissionStatus()
                if self.hasAccessibilityPermission && self.prefs.mouseAutoScrollEnabled && !self.isActive {
                    self.start()
                }
            }
        }
    }

    /// Tampilkan file Ozone.app di Finder untuk memudahkan drag & drop atau add manual jika di-build via Xcode
    func revealInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// Restart Ozone agar macOS memuat credential TCC yang baru diberikan pengguna
    func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Start / Stop Event Tap

    /// Aktifkan event tap untuk intercept scroll events.
    /// - Parameter userInitiated: `true` jika dipanggil dari aksi user (toggle ON).
    func start(userInitiated: Bool = false) {
        guard prefs.mouseAutoScrollEnabled else { return }
        guard !isActive else { return }

        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
        }

        guard trusted else {
            if userInitiated {
                requestAccessibilityPermission()
            } else {
                print("[MouseScrollService] ℹ️ Menunggu Accessibility permission diizinkan user...")
            }
            return
        }

        let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

        // Coba buat HID tap di urutan terdepan (.headInsertEventTap)
        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let service = Unmanaged<MouseScrollService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        // Fallback ke session tap jika HID tap gagal
        if tap == nil {
            print("[MouseScrollService] ⚠️ Gagal membuat .cghidEventTap, mencoba fallback ke .cgSessionEventTap...")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo = userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let service = Unmanaged<MouseScrollService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        }

        guard let validTap = tap else {
            print("[MouseScrollService] ❌ Gagal membuat CGEventTap. Pastikan Accessibility access aktif.")
            DispatchQueue.main.async { self.isActive = false }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)

        self.eventTap = validTap
        DispatchQueue.main.async {
            self.isActive = true
        }
        print("[MouseScrollService] ✅ Aktif — Natural scrolling dipisahkan: mouse dibalik, trackpad native.")
    }

    /// Hentikan event tap dan lepas resource.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        self.runLoopSource = nil
        DispatchQueue.main.async {
            self.isActive = false
        }
        print("[MouseScrollService] 🛑 Dihentikan.")
    }

    // MARK: - Event Handler Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS menonaktifkan tap jika terjadi timeout atau session lock; lakukan re-arm otomatis
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                #if DEBUG
                print("[MouseScrollService] 🔄 CGEventTap di-rearm otomatis.")
                #endif
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            #if DEBUG
            print("[MouseScrollService] 📩 Received non-scroll type: \(type.rawValue)")
            #endif
            return Unmanaged.passUnretained(event)
        }

        // CATATAN: Debug diagnostik dijalankan hanya di DEBUG build.
        // CGEventTap dipanggil ratusan kali/detik saat scroll — print() di sini
        // sangat mahal (string alloc + I/O) dan menjadi penyebab utama CPU spike.
        #if DEBUG
        let srcPID = event.getIntegerValueField(.eventSourceUnixProcessID)
        let srcUD  = event.getIntegerValueField(.eventSourceUserData)
        let isCont = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let d1     = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let p1     = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        print("[MouseScrollService] 📜 scrollWheel │ srcPID=\(srcPID) ud=\(srcUD) ownPID=\(Self.ownProcessID) isCont=\(isCont) Δline=\(d1) Δpoint=\(p1)")
        #endif

        // Abaikan scroll event sintetis yang diproduksi oleh proses ini sendiri
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID else {
            print("[MouseScrollService] ⏭️ Skip: event sintetis milik sendiri")
            return Unmanaged.passUnretained(event)
        }

        let nsEvent = NSEvent(cgEvent: event)
        let hasPrecise = nsEvent?.hasPreciseScrollingDeltas ?? false

        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount),
            hasPreciseDeltas: hasPrecise
        )

        let timestamp = UInt64(event.timestamp)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }

        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }

        let isMouse = ScrollWheelSupport.isMouseWheel(
            traits,
            secondsSinceLastGesturePhase: secondsSinceGesturePhase
        )

        #if DEBUG
        print("[MouseScrollService] 🔍 isContinuous=\(traits.isContinuous) hasPrecise=\(traits.hasPreciseDeltas) scrollPhase=\(traits.scrollPhase) momentumPhase=\(traits.momentumPhase) → isMouse=\(isMouse)")
        #endif

        // Update tracking untuk visualizer di Dashboard / Menu Bar
        let detectedDevice: ScrollInputDevice = isMouse ? .mouse : .trackpad
        if self.lastDetectedDevice != detectedDevice {
            DispatchQueue.main.async {
                self.lastDetectedDevice = detectedDevice
                self.lastEventDate = Date()
            }
        }

        // Jika event berasal dari mouse fisik, balikkan arah scroll sesuai konfigurasi
        if isMouse {
            #if DEBUG
            print("[MouseScrollService] 🖱️ MOUSE event — akan dibalik. invertV=\(prefs.mouseInvertVertical) invertH=\(prefs.mouseInvertHorizontal)")
            #endif

            // PENTING: Semua delta (line, point, fixedPoint) WAJIB dibaca SEBELUM penulisan apapun!
            // Menulis line delta memicu WindowServer menghitung ulang nilai point & fixedPoint.
            let invertVertical = prefs.mouseInvertVertical
            let invertHorizontal = prefs.mouseInvertHorizontal

            if invertVertical {
                let lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                let fixedPointY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)

                // 1. Line delta (integer)
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -lineY)

                // 2. Pixel point delta (integer) — HARUS ditulis setelah DeltaAxis1
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pointY)

                // 3. Fixed point delta (double) — HARUS ditulis setelah DeltaAxis1
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedPointY)
            }

            if invertHorizontal {
                let lineX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                let pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                let fixedPointX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

                // 1. Line delta (integer)
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -lineX)

                // 2. Pixel point delta (integer) — HARUS ditulis setelah DeltaAxis2
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pointX)

                // 3. Fixed point delta (double) — HARUS ditulis setelah DeltaAxis2
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixedPointX)
            }

            // Increment counter secara atomik di background thread.
            // TIDAK dispatch ke main untuk setiap event — terlalu mahal di hot path.
            // Nilai di-publish ke @Published var dari setupStatsFlushTimer() (1 detik sekali).
            withUnsafeMutablePointer(to: &_atomicInvertCount) { OSAtomicIncrement64($0) }
        }

        return Unmanaged.passUnretained(event)
    }
}
