// PortMonitorService.swift
// BatteryGuard / Ozone — Service untuk memindai port background & terminasi proses
// Memanfaatkan Darwin POSIX C-APIs, lsof field mode, dan sysctl proc_pidpath

import Foundation
import AppKit
import Darwin

// MARK: - Port Kill Error

public enum PortKillError: LocalizedError {
    case permissionDenied(String)
    case processNotFound
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let msg):
            return msg
        case .processNotFound:
            return "Proses sudah tidak berjalan atau telah dihentikan."
        case .failed(let msg):
            return msg
        }
    }
}

// MARK: - PortMonitorService

public final class PortMonitorService {

    public static let shared = PortMonitorService()

    private let executionQueue = DispatchQueue(label: "com.ibrardev.ozone.port-monitor", qos: .userInitiated)

    // Cache username untuk menghindari pemanggilan getpwuid berulang kali
    private var usernameCache: [uid_t: String] = [:]

    public init() {}

    // MARK: - Fetch Active Ports

    /// Mengambil seluruh listening & background bound ports di macOS
    public func fetchActivePorts() async -> [PortProcessInfo] {
        await withCheckedContinuation { continuation in
            executionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                let ports = self.scanPortsUsingLsof()
                continuation.resume(returning: ports)
            }
        }
    }

    // MARK: - Stop / Kill Process

    /// Menghentikan proses yang menempati port
    /// - Parameters:
    ///   - pid: Process ID yang akan dihentikan
    ///   - force: true untuk SIGKILL (Force Stop), false untuk SIGTERM (Graceful Stop)
    public func killProcess(pid: Int32, force: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            executionQueue.async {
                let signal = force ? SIGKILL : SIGTERM
                let result = Darwin.kill(pid_t(pid), signal)

                if result == 0 {
                    // Sinyal berhasil dikirim
                    continuation.resume()
                } else {
                    let err = errno
                    switch err {
                    case EPERM:
                        continuation.resume(throwing: PortKillError.permissionDenied(
                            "Izin ditolak: Proses PID \(pid) dimiliki oleh sistem atau akun pengguna lain."
                        ))
                    case ESRCH:
                        // Proses sudah mati
                        continuation.resume()
                    default:
                        let errorMsg = String(cString: strerror(err))
                        continuation.resume(throwing: PortKillError.failed(
                            "Gagal menghentikan PID \(pid): \(errorMsg) (Code \(err))"
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Private Parser & Execution

    private func scanPortsUsingLsof() -> [PortProcessInfo] {
        let task = Process()
        let lsofPath = FileManager.default.fileExists(atPath: "/usr/sbin/lsof") ? "/usr/sbin/lsof" : "/usr/bin/lsof"
        task.executableURL = URL(fileURLWithPath: lsofPath)

        // Parameter -F: Field output mode untuk machine parsing yang akurat dan stabil
        // p: pid, c: command, u: uid, f: fd, t: type (IPv4/6), P: proto, n: name
        // -i: internet files, -P: inhibits port names (nomor numerik), -n: inhibits hostname lookup (cepat)
        task.arguments = ["-i", "-P", "-n", "-F", "pcuPtfn"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Buang error jika ada

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return parseLsofOutput(output)
        } catch {
            return []
        }
    }

    private func parseLsofOutput(_ output: String) -> [PortProcessInfo] {
        var rawItems: [RawPortItem] = []

        var currentPID: Int32?
        var currentCommand: String = ""
        var currentUID: uid_t = 501
        var currentType: String = ""
        var currentProto: PortProtocol = .tcp

        output.enumerateLines { line, _ in
            guard !line.isEmpty else { return }

            let prefix = line.first!
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = Int32(value)
            case "c":
                currentCommand = value
            case "u":
                if let uid = UInt32(value) {
                    currentUID = uid_t(uid)
                }
            case "t":
                currentType = value // IPv4 atau IPv6
            case "P":
                currentProto = (value.uppercased() == "UDP") ? .udp : .tcp
            case "n":
                // Baris name berisi network address
                // Jika mengandung "->", ini adalah established outbound connection (bukan listening server port)
                guard !value.contains("->") else { return }

                // Parse address dan port dari format misalnya "*:3000", "127.0.0.1:8080", "[::1]:5432"
                if let (host, port) = self.parseAddressAndPort(value) {
                    if let pid = currentPID {
                        rawItems.append(RawPortItem(
                            pid: pid,
                            command: currentCommand,
                            uid: currentUID,
                            proto: currentProto,
                            ipVersion: currentType,
                            host: host,
                            port: port
                        ))
                    }
                }
            default:
                break
            }
        }

        // Kelompokkan dan deduplikasi (misal port yang sama listening di IPv4 & IPv6 oleh PID yang sama)
        return consolidateRawItems(rawItems)
    }

    private func parseAddressAndPort(_ addressString: String) -> (String, Int)? {
        // Abaikan wildcard tanpa port seperti "*:*"
        guard addressString != "*:*" else { return nil }

        // Mencari tanda titik dua terakhir untuk pemisah port
        guard let lastColonIndex = addressString.lastIndex(of: ":") else { return nil }

        let hostPart = String(addressString[..<lastColonIndex])
        let portPart = String(addressString[addressString.index(after: lastColonIndex)...])

        guard let port = Int(portPart), port > 0 else { return nil }

        let cleanedHost: String
        if hostPart.isEmpty || hostPart == "*" {
            cleanedHost = "*"
        } else {
            cleanedHost = hostPart
        }

        return (cleanedHost, port)
    }

    private func consolidateRawItems(_ rawItems: [RawPortItem]) -> [PortProcessInfo] {
        // Grouping key: pid_port_proto
        var grouped: [String: [RawPortItem]] = [:]

        for item in rawItems {
            let key = "\(item.pid)_\(item.port)_\(item.proto.rawValue)"
            grouped[key, default: []].append(item)
        }

        var results: [PortProcessInfo] = []

        for (_, items) in grouped {
            guard let first = items.first else { continue }

            // Gabungkan ipVersion jika ada IPv4 dan IPv6
            let versions = Set(items.map { $0.ipVersion }).sorted()
            let combinedVersion = versions.count > 1 ? "Dual-Stack" : (versions.first ?? "IPv4")

            // Ambil host yang paling deskriptif
            let host: String
            let hosts = items.map { $0.host }
            if hosts.contains("*") || hosts.contains("0.0.0.0") {
                host = "*"
            } else if let local = hosts.first(where: { $0 == "127.0.0.1" || $0 == "[::1]" }) {
                host = local
            } else {
                host = first.host
            }

            // Dapatkan username
            let username = resolveUsername(for: first.uid)

            // Dapatkan full path executable
            let commandPath = resolveExecutablePath(for: first.pid)

            // Tentukan apakah proses sistem
            let isSystem = isSystemProcess(uid: first.uid, command: first.command, path: commandPath)

            let info = PortProcessInfo(
                pid: first.pid,
                processName: first.command,
                commandPath: commandPath,
                user: username,
                port: first.port,
                protocolType: first.proto,
                ipVersion: combinedVersion,
                bindAddress: host,
                state: (first.proto == .tcp) ? "LISTEN" : "BOUND",
                isSystemProcess: isSystem
            )

            results.append(info)
        }

        // Urutkan berdasarkan nomor port menaik
        return results.sorted { $0.port < $1.port }
    }

    // MARK: - Process Metadata Helpers

    private func resolveUsername(for uid: uid_t) -> String {
        if let cached = usernameCache[uid] {
            return cached
        }
        if let pw = getpwuid(uid) {
            let name = String(cString: pw.pointee.pw_name)
            usernameCache[uid] = name
            return name
        }
        let fallback = (uid == 0) ? "root" : "UID \(uid)"
        usernameCache[uid] = fallback
        return fallback
    }

    private func resolveExecutablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let path = String(cString: buffer)
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func isSystemProcess(uid: uid_t, command: String, path: String?) -> Bool {
        if uid == 0 { return true }

        let lowerCmd = command.lowercased()
        let knownSystemDaemons = [
            "launchd", "rapportd", "identityservicesd", "mdnsresponder", "sharingd",
            "bluetoothd", "cupsd", "syslogd", "coreaudiod", "locationd", "timed",
            "trustd", "securityd", "containermanagerd", "distnoted", "cfprefsd"
        ]

        if knownSystemDaemons.contains(lowerCmd) {
            return true
        }

        if let p = path {
            if p.hasPrefix("/System/") || p.hasPrefix("/usr/libexec/") || p.hasPrefix("/usr/sbin/") {
                return true
            }
        }

        return false
    }
}

// MARK: - Internal Raw Item

private struct RawPortItem {
    let pid: Int32
    let command: String
    let uid: uid_t
    let proto: PortProtocol
    let ipVersion: String
    let host: String
    let port: Int
}
