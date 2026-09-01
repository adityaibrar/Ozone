// SMCTemperatureProvider.swift
// BatteryGuard

import Foundation
import IOKit

// MARK: - SMC Structs

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
private struct SMCVersion {
    var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
    var release: UInt16 = 0
}
private struct SMCPLimitData {
    var version: UInt16 = 0, length: UInt16 = 0
    var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
}
private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
}

// MARK: - SMC Client

final class SMCClient {
    private var connection: io_connect_t = 0
    
    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }
    
    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }
    
    private func fourCC(_ s: String) -> UInt32 {
        return s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    
    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        if kr == kIOReturnSuccess && output.result == 0 {
            return output
        }
        return nil
    }
    
    func readTemperature(key: String) -> Double? {
        var infoIn = SMCParamStruct()
        infoIn.key = fourCC(key)
        infoIn.data8 = 9 // cmdKeyInfo
        guard let infoOut = call(&infoIn) else { return nil }
        
        let dataSize = infoOut.keyInfo.dataSize
        let dataType = infoOut.keyInfo.dataType
        
        var readIn = SMCParamStruct()
        readIn.key = fourCC(key)
        readIn.keyInfo.dataSize = dataSize
        readIn.data8 = 5 // cmdReadKey
        guard let readOut = call(&readIn) else { return nil }
        
        let bytes = withUnsafeBytes(of: readOut.bytes) { Array($0.prefix(Int(dataSize))) }
        let typeStr = String(bytes: [
            UInt8((dataType >> 24) & 0xff),
            UInt8((dataType >> 16) & 0xff),
            UInt8((dataType >> 8) & 0xff),
            UInt8(dataType & 0xff)
        ], encoding: .ascii) ?? ""
        
        return decodeTemperature(bytes: bytes, type: typeStr)
    }
    
    private func decodeTemperature(bytes: [UInt8], type: String) -> Double? {
        if type == "sp78" && bytes.count == 2 {
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        } else if type == "fpe2" && bytes.count == 2 {
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        } else if type == "flt " && bytes.count == 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let val = Double(Float32(bitPattern: bits))
            return val.isFinite ? val : nil
        }
        return nil
    }
}

// MARK: - SMC Temperature Provider

final class SMCTemperatureProvider: TemperatureProviding {
    private let client: SMCClient?

    // Semua kandidat key per generasi chip \u2014 dipakai hanya untuk probing awal
    private let cpuKeyCandidates = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", // M1
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",                                   // M2
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",                                   // M3
        "TC0D", "TC0E", "TC0F", "TC0P", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C"   // Intel
    ]
    private let batteryKeyCandidates = ["TB0T", "TB1T", "TB2T", "TB3T"]

    /// Key yang benar-benar ada di hardware ini (diisi sekali saat probe pertama).
    /// Setelah probe, polling hanya iterasi 2\u20134 key ini, bukan 30+ kandidat.
    private var validCPUKeys: [String]?
    private var validBatteryKeys: [String]?

    init() {
        self.client = SMCClient()
    }

    func fetchTemperatures() -> SystemTemperatures {
        guard let client = client else {
            return SystemTemperatures(cpuTemperature: nil, batteryTemperature: nil, allReadings: [], timestamp: Date())
        }

        // Probe sekali untuk menemukan key yang valid di hardware ini.
        // Setelah ini, validCPUKeys/validBatteryKeys tidak nil \u2014 probe tidak diulang.
        if validCPUKeys == nil {
            validCPUKeys = cpuKeyCandidates.filter { key in
                guard let temp = client.readTemperature(key: key) else { return false }
                return temp > 1.0 && temp < 130.0
            }
            validBatteryKeys = batteryKeyCandidates.filter { key in
                guard let temp = client.readTemperature(key: key) else { return false }
                return temp > 1.0 && temp < 130.0
            }
        }

        let now = Date()
        let cpuTemp = getMaxTemperature(keys: validCPUKeys ?? [], client: client)
        let batteryTemp = getMaxTemperature(keys: validBatteryKeys ?? [], client: client)

        var readings: [TemperatureReading] = []
        var cpuReading: TemperatureReading? = nil
        var batteryReading: TemperatureReading? = nil

        if let c = cpuTemp {
            cpuReading = TemperatureReading(sensorName: "CPU (SMC)", celsius: c, timestamp: now)
            readings.append(cpuReading!)
        }
        if let b = batteryTemp {
            batteryReading = TemperatureReading(sensorName: "Battery (SMC)", celsius: b, timestamp: now)
            readings.append(batteryReading!)
        }

        return SystemTemperatures(
            cpuTemperature: cpuReading,
            batteryTemperature: batteryReading,
            allReadings: readings,
            timestamp: now
        )
    }

    private func getMaxTemperature(keys: [String], client: SMCClient) -> Double? {
        var maxTemp: Double? = nil
        for key in keys {
            if let temp = client.readTemperature(key: key), temp > 1.0 && temp < 130.0 {
                if maxTemp == nil || temp > maxTemp! {
                    maxTemp = temp
                }
            }
        }
        return maxTemp
    }
}
