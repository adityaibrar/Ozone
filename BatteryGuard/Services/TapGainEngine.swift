// TapGainEngine.swift
// BatteryGuard — Engine Audio Real-Time untuk Volume Control Per-Aplikasi (macOS 14.4+)

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - GainEngine Protocol

/// Protocol type-erased agar service dapat menyimpan engine di macOS versi apa pun
/// sementara implementasi konkrit membutuhkan macOS 14.4+.
protocol GainEngine: AnyObject {
    var gain: Float { get set }
    var tappedObjects: [AudioObjectID] { get }
    var outputDeviceUID: String { get }
    var renderCycles: UInt64 { get }
    func stop()
}

// MARK: - TapGainEngine

/// Mengarahkan audio dari sekumpulan AudioObjectID (proses aplikasi) ke Process Tap
/// dengan perilaku `mutedWhenTapped`, lalu merender ulang audio tersebut dengan pengali gain
/// ke Output Device melalui Aggregate Device secara real-time.
@available(macOS 14.4, *)
final class TapGainEngine: GainEngine {
    let tappedObjects: [AudioObjectID]
    let outputDeviceUID: String

    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = min(max(newValue, 0.0), 2.0) }
    }

    /// Thread-safe boxes untuk komunikasi bebas lock antara Main Thread & Realtime Audio Thread
    private final class GainBox { var value: Float = 1.0 }
    private final class CycleBox { var value: UInt64 = 0 }
    private final class LimiterBox {
        var limiters: ContiguousArray<BoostLimiter>
        init(bufferCount: Int) {
            limiters = ContiguousArray(repeating: BoostLimiter(), count: bufferCount)
        }
    }
    private final class ReleaseBox {
        var value: Float = BoostLimiter.release(sampleRate: 48000)
    }

    private let gainBox = GainBox()
    private let cycleBox = CycleBox()
    private let releaseBox = ReleaseBox()
    var renderCycles: UInt64 { cycleBox.value }

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var rateListenerClient: UnsafeMutableRawPointer?

    init?(objects: [AudioObjectID], gain: Float, outputDeviceUID: String) {
        guard !objects.isEmpty, !outputDeviceUID.isEmpty else { return nil }
        self.tappedObjects = objects
        self.outputDeviceUID = outputDeviceUID
        self.gainBox.value = min(max(gain, 0.0), 2.0)

        // 1. Buat Process Tap Description
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr, newTapID != 0 else {
            print("❌ [TapGainEngine] AudioHardwareCreateProcessTap failed with status: \(tapStatus) (objects: \(objects))")
            return nil
        }
        self.tapID = newTapID

        // 2. Buat Private Aggregate Device dengan Sub-Tap
        let aggregateConfig: [String: Any] = [
            kAudioAggregateDeviceNameKey:          "Ozone Mixer",
            kAudioAggregateDeviceUIDKey:           UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey:     true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey:               description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        var newAggID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateConfig as CFDictionary, &newAggID)
        guard aggStatus == noErr, newAggID != 0 else {
            print("❌ [TapGainEngine] AudioHardwareCreateAggregateDevice failed with status: \(aggStatus)")
            AudioHardwareDestroyProcessTap(newTapID)
            return nil
        }
        self.aggregateID = newAggID

        // 3. Siapkan Audio DSP & Limiter
        let box = gainBox
        let limiterBox = LimiterBox(bufferCount: 8)
        let sampleRate = Self.nominalSampleRate(of: newAggID)
        releaseBox.value = BoostLimiter.release(sampleRate: sampleRate)
        let release = releaseBox
        let cycles = cycleBox
        let tapChannels = Self.tapChannels(of: newTapID)

        // 4. Daftarkan Realtime IO Proc Callback
        var newProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newAggID, nil) { _, inInputData, _, inOutputData, _ in
            cycles.value &+= 1
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(inOutputData)

            guard let tapIndex = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: tapChannels) else {
                return
            }

            let g = box.value
            let frames = MixerRender.render(source: inputBuffers[tapIndex],
                                            into: outputBuffers,
                                            gain: g)

            guard g > 1.0, frames > 0 else { return }

            // Peak limiting untuk gain > 1.0 (mencegah clipping)
            let releaseCoeff = release.value
            var low: Float = -1.0, high: Float = 1.0
            for (index, outputBuffer) in outputBuffers.enumerated() {
                let channels = Int(outputBuffer.mNumberChannels)
                guard channels > 0,
                      let destination = outputBuffer.mData?.assumingMemoryBound(to: Float.self)
                else { continue }

                if index < limiterBox.limiters.count {
                    limiterBox.limiters[index].process(destination,
                                                       frames: frames,
                                                       channels: channels,
                                                       release: releaseCoeff)
                } else {
                    vDSP_vclip(destination, 1, &low, &high, destination, 1,
                               vDSP_Length(frames * channels))
                }
            }
        }

        guard ioStatus == noErr, let procID = newProcID else {
            print("❌ [TapGainEngine] AudioDeviceCreateIOProcIDWithBlock failed with status: \(ioStatus)")
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            return nil
        }
        self.ioProc = procID

        // 5. Mulai Sample Rate Watcher & Mulai IO Device
        startWatchingSampleRate()

        let startStatus = AudioDeviceStart(newAggID, procID)
        guard startStatus == noErr else {
            print("❌ [TapGainEngine] AudioDeviceStart failed with status: \(startStatus)")
            stop()
            return nil
        }
        print("✅ [TapGainEngine] Successfully started Process Tap for \(objects.count) object(s)")
    }

    // MARK: - Sample Rate Watcher

    private func startWatchingSampleRate() {
        var address = Self.nominalSampleRateAddress()
        let client = Unmanaged.passRetained(releaseBox).toOpaque()
        guard AudioObjectAddPropertyListener(aggregateID, &address, Self.sampleRateListener, client) == noErr else {
            Unmanaged<ReleaseBox>.fromOpaque(client).release()
            return
        }
        rateListenerClient = client
    }

    private func stopWatchingSampleRate() {
        guard let client = rateListenerClient else { return }
        rateListenerClient = nil
        var address = Self.nominalSampleRateAddress()
        AudioObjectRemovePropertyListener(aggregateID, &address, Self.sampleRateListener, client)
        Unmanaged<ReleaseBox>.fromOpaque(client).release()
    }

    private static let rateQueue = DispatchQueue(label: "com.ibrardev.ozone.mixer.rate", qos: .userInitiated)

    private static let sampleRateListener: AudioObjectPropertyListenerProc = { deviceID, _, _, client in
        guard let client else { return noErr }
        let box = Unmanaged<ReleaseBox>.fromOpaque(client).takeUnretainedValue()
        rateQueue.async {
            box.value = BoostLimiter.release(sampleRate: nominalSampleRate(of: deviceID))
        }
        return noErr
    }

    private static func nominalSampleRateAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: - Helper CoreAudio Properties

    private static func tapChannels(of tapID: AudioObjectID) -> Int {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &format) == noErr,
              format.mChannelsPerFrame > 0
        else { return 2 }
        return Int(format.mChannelsPerFrame)
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var addr = nominalSampleRateAddress()
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &sampleRate) == noErr,
              sampleRate > 0
        else { return 48000.0 }
        return sampleRate
    }

    // MARK: - Lifecycle Teardown

    func stop() {
        stopWatchingSampleRate()
        if let procID = ioProc {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.ioProc = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            self.aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            self.tapID = 0
        }
    }

    deinit {
        stop()
    }
}
