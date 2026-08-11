// VolumeMixerService.swift
// BatteryGuard — Service Pengelola Volume Per-Aplikasi via CoreAudio Process Tap (macOS 14.4+)

import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI

// MARK: - VolumeMixerService

/// Service yang mendeteksi aplikasi yang sedang aktif menggunakan audio,
/// dan memungkinkan kontrol volume per-aplikasi serta master system volume.
///
/// Arsitektur:
/// - Resolusi Process ID & Child Process (Brave, Chrome, Safari, Slack, Spotify, dll) via `ResponsibleProcess`.
/// - Process Tap dengan `muteBehavior = .mutedWhenTapped` untuk membungkam stream asli app.
/// - Aggregate Device re-rendering dengan DSP `MixerRender` dan Peak Limiter `BoostLimiter` (> 100%).
/// - Lock-free token tracking `MixerEngineBuilds` untuk menjamin stabilitas saat slider digeser cepat.
/// - Hardware property listeners untuk sync real-time dengan keyboard/Control Center.
@MainActor
final class VolumeMixerService: ObservableObject {

    // MARK: - Published State

    /// Daftar aplikasi yang sedang memiliki audio connection aktif
    @Published private(set) var apps: [VolumeApp] = []

    /// Volume system master output (0.0–1.0)
    @Published var systemVolume: Float = 1.0

    /// Status mute system master output
    @Published var isSystemMuted: Bool = false

    /// Status apakah permission Screen & System Audio Recording diperlukan (terpicu jika CoreAudio gagal membuat Process Tap)
    @Published private(set) var needsPermission: Bool = false

    // MARK: - Private State

    private var refreshTimer: Timer?
    private let userDefaultsKey = "volumeMixer.volumes"

    /// Device ID default output saat ini (nonisolated untuk deinit safety)
    nonisolated(unsafe) private var monitoredDeviceID: AudioDeviceID?

    /// Active GainEngines per bundleIdentifier
    private var engines: [String: any GainEngine] = [:]

    /// Build token coordinator
    private var builds = MixerEngineBuilds()

    /// Volume terakhir yang audible (> 0) per bundleId, untuk restore saat toggle unmute
    private var lastAudibleVolume: [String: Float] = [:]

    /// Listener registration tracking
    private var runningListeners = Set<AudioObjectID>()
    private var globalListenersInstalled = false
    private var permissionObserver: NSObjectProtocol?

    private let halQueue = DispatchQueue(label: "com.ibrardev.ozone.mixer.hal", qos: .userInitiated)
    private let buildQueue = DispatchQueue(label: "com.ibrardev.ozone.mixer.build", qos: .userInitiated)

    /// Cache volume per bundleIdentifier yang tersimpan di disk
    private var savedVolumes: [String: Float] {
        get { UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Float] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    // MARK: - Init & Deinit

    init() {
        setupPermissionObserver()
        loadSystemVolume()
        registerGlobalListeners()
        startPolling()
        checkPermission()
    }

    deinit {
        refreshTimer?.invalidate()
        if let observer = permissionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for engine in engines.values {
            engine.stop()
        }
        engines.removeAll()
        nonisolatedRemoveListeners(monitoredDeviceID: monitoredDeviceID)
    }

    // MARK: - Permission Management

    @discardableResult
    func checkPermission() -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        self.needsPermission = !granted
        if granted {
            reconcileEngines(with: self.apps)
        }
        return granted
    }

    /// Memicu prompt sistem izin Screen & Audio Recording pada macOS jika belum diberikan saat pertama kali dibuka
    func requestInitialPermissionIfNeeded() {
        let granted = CGPreflightScreenCaptureAccess()
        if !granted {
            _ = CGRequestScreenCaptureAccess()
            self.needsPermission = true
        }
    }

    /// Tampilkan prompt izin dan buka jendela System Settings -> Screen & System Audio Recording
    func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        // Polling singkat untuk memperbarui status saat user mengaktifkan switch di System Settings
        for delay in [1.0, 2.0, 3.5, 5.0, 7.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.checkPermission()
            }
        }
    }

    /// Tampilkan file Ozone.app di Finder untuk memudahkan drag & drop manual ke System Settings jika diperlukan
    func revealInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// Memuat ulang (restart) aplikasi Ozone agar izin TCC yang baru diberikan diaktifkan oleh macOS
    func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func setupPermissionObserver() {
        permissionObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPermission()
        }
    }

    private func clearPermissionIfNoActiveAdjustments() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted {
            needsPermission = false
        }
    }

    // MARK: - HAL Listeners & System Volume Sync

    private func registerGlobalListeners() {
        guard !globalListenersInstalled else { return }
        globalListenersInstalled = true

        // 1. Listener Default Output Device
        var defaultDeviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.handleDefaultDeviceChanged()
        }

        // 2. Listener Process Object List (Apps audio stream change)
        var processListAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh()
        }

        // 3. Attach ke master hardware output volume
        attachDeviceListeners()
    }

    private func attachDeviceListeners() {
        guard let deviceID = defaultOutputDeviceID() else { return }
        monitoredDeviceID = deviceID

        // Volume master listener
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let volumeElement: UInt32 = AudioObjectHasProperty(deviceID, &volAddr)
            ? kAudioObjectPropertyElementMain : 1
        volAddr.mElement = volumeElement

        AudioObjectAddPropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.syncSystemVolumeFromHardware()
        }

        if volumeElement == kAudioObjectPropertyElementMain {
            var ch1Addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
            if AudioObjectHasProperty(deviceID, &ch1Addr) {
                AudioObjectAddPropertyListenerBlock(deviceID, &ch1Addr, DispatchQueue.main) { [weak self] _, _ in
                    self?.syncSystemVolumeFromHardware()
                }
            }
        }

        // Mute listener
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main) { [weak self] _, _ in
                self?.syncSystemMuteFromHardware()
            }
        }
    }

    private func handleDefaultDeviceChanged() {
        if let old = monitoredDeviceID {
            nonisolatedDetachDeviceListeners(from: old)
        }
        attachDeviceListeners()
        syncSystemVolumeFromHardware()
        syncSystemMuteFromHardware()

        // Invalidate in-flight builds and retarget running engines to new output device
        builds.invalidateAll()
        refresh()
    }

    private nonisolated func nonisolatedRemoveListeners(monitoredDeviceID: AudioDeviceID?) {
        var defaultDeviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddr,
            DispatchQueue.main
        ) { _, _ in }

        var processListAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddr,
            DispatchQueue.main
        ) { _, _ in }

        if let deviceID = monitoredDeviceID {
            nonisolatedDetachDeviceListeners(from: deviceID)
        }
    }

    private nonisolated func nonisolatedDetachDeviceListeners(from deviceID: AudioDeviceID) {
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main) { _, _ in }
        volAddr.mElement = 1
        AudioObjectRemovePropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main) { _, _ in }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main) { _, _ in }
    }

    private func syncSystemVolumeFromHardware() {
        let hw = readSystemOutputVolume()
        if abs(hw - systemVolume) > 0.005 {
            systemVolume = hw
        }
    }

    private func syncSystemMuteFromHardware() {
        let hw = readSystemOutputMute()
        if hw != isSystemMuted {
            isSystemMuted = hw
        }
    }

    // MARK: - Public App Volume Controls

    /// Mengubah volume aplikasi tertentu (0.0–2.0)
    func setVolume(_ volume: Float, for bundleId: String) {
        let clamped = min(max(volume, 0.0), 2.0)

        guard let idx = apps.firstIndex(where: { $0.bundleIdentifier == bundleId }) else { return }
        apps[idx].volume = clamped

        if clamped > 0.001 {
            lastAudibleVolume[bundleId] = clamped
        }

        // Persist ke UserDefaults
        var saved = savedVolumes
        saved[bundleId] = clamped
        savedVolumes = saved

        applyRouting(for: apps[idx])
    }

    /// Toggle mute aplikasi tertentu
    func toggleMute(for bundleId: String) {
        guard let idx = apps.firstIndex(where: { $0.bundleIdentifier == bundleId }) else { return }
        let current = apps[idx]

        if current.isMuted {
            let restore = lastAudibleVolume[bundleId] ?? 1.0
            setVolume(restore, for: bundleId)
        } else {
            if current.volume > 0.001 {
                lastAudibleVolume[bundleId] = current.volume
            }
            setVolume(0.0, for: bundleId)
        }
    }

    // MARK: - Real-Time Engine Routing

    /// Menentukan pembuatan, penyesuaian gain, atau pembongkaran TapGainEngine untuk app.
    private func applyRouting(for app: VolumeApp) {
        let bundleId = app.bundleIdentifier
        let isUnity = MixerRoutingSupport.isUnity(app.volume)

        // 1. Jika volume 100% (Unity Passthrough), engine tidak dibutuhkan
        guard !isUnity else {
            discardEngine(for: bundleId)
            return
        }

        guard let outputUID = defaultOutputDeviceUID() else {
            discardEngine(for: bundleId)
            return
        }

        // 2. Jika engine sudah aktif dengan target audioObjects & output device yang cocok
        if let existing = engines[bundleId],
           existing.tappedObjects == app.audioObjects,
           existing.outputDeviceUID == outputUID {
            existing.gain = app.volume
            return
        }

        // 3. Jika sedang ada build asynchronous in-flight untuk bundleId ini, biarkan selesai
        guard let token = builds.begin(bundleId) else { return }

        let objectsToTap = app.audioObjects
        let targetGain = app.volume
        let targetBundle = bundleId

        // 4. Bangun engine secara asynchronous pada background queue agar tidak memblokir UI
        buildQueue.async { [weak self] in
            guard #available(macOS 14.4, *) else { return }
            let engine = TapGainEngine(objects: objectsToTap,
                                       gain: targetGain,
                                       outputDeviceUID: outputUID)

            DispatchQueue.main.async { [weak self] in
                self?.installEngine(engine, for: targetBundle, token: token)
            }
        }
    }

    /// Memasang engine yang selesai dibangun ke dictionary engines
    private func installEngine(_ engine: (any GainEngine)?, for bundleId: String, token: Int) {
        let isCurrent = builds.isCurrent(bundleId, token: token)
        builds.finish(bundleId, token: token)

        guard isCurrent else {
            engine?.stop()
            return
        }

        guard let engine else {
            if engines[bundleId] == nil, !needsPermission {
                needsPermission = true
            }
            return
        }

        if needsPermission {
            needsPermission = false
        }

        guard let currentApp = apps.first(where: { $0.bundleIdentifier == bundleId }) else {
            engine.stop()
            return
        }

        let isUnity = MixerRoutingSupport.isUnity(currentApp.volume)
        guard !isUnity,
              currentApp.audioObjects == engine.tappedObjects,
              (defaultOutputDeviceUID() == engine.outputDeviceUID) else {
            engine.stop()
            applyRouting(for: currentApp)
            return
        }

        // Terapkan gain terkini sebelum dipasang
        engine.gain = currentApp.volume
        let previous = engines.updateValue(engine, forKey: bundleId)
        previous?.stop()
    }

    private func discardEngine(for bundleId: String) {
        engines.removeValue(forKey: bundleId)?.stop()
        clearPermissionIfNoActiveAdjustments()
    }

    // MARK: - Discovery & App State Management

    func refresh() {
        halQueue.async { [weak self] in
            guard let self else { return }
            let discovered = self.readActiveAudioAppsFromHAL()

            DispatchQueue.main.async { [weak self] in
                self?.mergeDiscoveredApps(discovered)
            }
        }
    }

    private func startPolling() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    /// Membaca snapshot proses audio dari HAL (berjalan pada halQueue)
    private nonisolated func readActiveAudioAppsFromHAL() -> [VolumeApp] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &objectIDs
        ) == noErr else { return [] }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        var groups: [pid_t: [AudioObjectID]] = [:]
        var playingSet: Set<pid_t> = []
        var appOwners: [pid_t: NSRunningApplication] = [:]

        for obj in objectIDs {
            var pid: pid_t = -1
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(obj, &pidAddr, 0, nil, &pidSize, &pid) == noErr,
                  pid > 0, pid != ownPid else { continue }

            // Resolusi PID helper / worker ke Regular UI App Owner
            guard let ownerApp = ResponsibleProcess.regularAppOwner(of: pid) else { continue }
            let ownerPid = ownerApp.processIdentifier
            if ownerPid == ownPid { continue }

            groups[ownerPid, default: []].append(obj)
            appOwners[ownerPid] = ownerApp

            // Periksa apakah sedang playing output
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(obj, &runAddr, 0, nil, &runningSize, &isRunning) == noErr,
               isRunning != 0 {
                playingSet.insert(ownerPid)
            }
        }

        var result: [VolumeApp] = []
        for (ownerPid, objects) in groups {
            guard let ownerApp = appOwners[ownerPid] else { continue }
            let bundleId = ownerApp.bundleIdentifier ?? "pid.\(ownerPid)"
            let name = ResponsibleProcess.displayName(pid: ownerPid, fallback: ownerApp.localizedName ?? "App")

            // Pro audio / DAW bypass check
            if MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: bundleId, name: name) {
                continue
            }

            let icon = ResponsibleProcess.icon(for: ownerPid, pointSize: 32)
            let isPlaying = playingSet.contains(ownerPid)

            result.append(VolumeApp(
                id: ownerPid,
                bundleIdentifier: bundleId,
                name: name,
                icon: icon,
                audioObjects: objects.sorted(),
                volume: 1.0, // Akan di-update dengan savedVolumes di MainActor
                isPlayingAudio: isPlaying
            ))
        }

        return result
    }

    private func mergeDiscoveredApps(_ discovered: [VolumeApp]) {
        var currentSaved = savedVolumes

        var coalesced: [VolumeApp] = []
        var indexesByBundleID: [String: Int] = [:]

        for var app in discovered {
            let bundleId = app.bundleIdentifier
            let vol = currentSaved[bundleId] ?? 1.0
            app.volume = vol

            if let existingIndex = indexesByBundleID[bundleId] {
                let existing = coalesced[existingIndex]
                let mergedObjects = Array(Set(existing.audioObjects).union(app.audioObjects)).sorted()
                coalesced[existingIndex] = VolumeApp(
                    id: existing.id,
                    bundleIdentifier: existing.bundleIdentifier,
                    name: existing.name,
                    icon: existing.icon,
                    audioObjects: mergedObjects,
                    volume: existing.volume,
                    isPlayingAudio: existing.isPlayingAudio || app.isPlayingAudio
                )
            } else {
                indexesByBundleID[bundleId] = coalesced.count
                coalesced.append(app)
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            self.apps = coalesced.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }

        // Reconcile engines
        reconcileEngines(with: self.apps)
    }

    private func reconcileEngines(with currentApps: [VolumeApp]) {
        let currentBundleIds = Set(currentApps.map(\.bundleIdentifier))

        // 1. Hapus engine untuk app yang sudah tidak aktif
        for bundleId in Array(engines.keys) {
            if !currentBundleIds.contains(bundleId) {
                discardEngine(for: bundleId)
            }
        }

        // 2. Pasang/sesuaikan engine untuk app yang memiliki volume non-unity
        for app in currentApps {
            if !MixerRoutingSupport.isUnity(app.volume) {
                applyRouting(for: app)
            } else {
                discardEngine(for: app.bundleIdentifier)
            }
        }
    }

    // MARK: - System Master Volume Helpers

    func setSystemVolume(_ volume: Float) {
        let clamped = min(max(volume, 0.0), 1.0)
        systemVolume = clamped
        applySystemVolume(clamped)
    }

    func toggleSystemMute() {
        isSystemMuted.toggle()
        applySystemMute(isSystemMuted)
    }

    private func loadSystemVolume() {
        systemVolume = readSystemOutputVolume()
        isSystemMuted = readSystemOutputMute()
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func defaultOutputDeviceUID() -> String? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        var uidRef: CFString = "" as CFString
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uidRef) == noErr else {
            return nil
        }
        let uid = uidRef as String
        return uid.isEmpty ? nil : uid
    }

    private func readSystemOutputVolume() -> Float {
        guard let deviceID = defaultOutputDeviceID() else { return 1.0 }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &addr) {
            var vol: Float = 1.0
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }

        var total: Float = 0
        var validChannels = 0
        for ch: UInt32 in [1, 2] {
            addr.mElement = ch
            if AudioObjectHasProperty(deviceID, &addr) {
                var vol: Float = 0
                var size = UInt32(MemoryLayout<Float>.size)
                if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr {
                    total += vol
                    validChannels += 1
                }
            }
        }
        return validChannels > 0 ? total / Float(validChannels) : 1.0
    }

    private func applySystemVolume(_ volume: Float) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &addr) {
            var vol = volume
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
            return
        }

        for ch: UInt32 in [1, 2] {
            addr.mElement = ch
            if AudioObjectHasProperty(deviceID, &addr) {
                var vol = volume
                AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
            }
        }
    }

    private func readSystemOutputMute() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted)
        return muted != 0
    }

    private func applySystemMute(_ muted: Bool) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return }

        var muteValue: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muteValue)
    }
}
