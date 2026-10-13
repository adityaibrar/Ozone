// PortProcessInfo.swift
// BatteryGuard / Ozone — Model data informasi port jaringan dan proses background
// Menyimpan informasi lengkap: port, protokol, PID, user, path binary, dan kategori

import Foundation
import AppKit

// MARK: - Port Protocol

public enum PortProtocol: String, CaseIterable, Identifiable, Codable {
    case tcp = "TCP"
    case udp = "UDP"

    public var id: String { rawValue }

    public var badgeColorName: String {
        switch self {
        case .tcp: return "blue"
        case .udp: return "orange"
        }
    }
}

// MARK: - Port Category

public enum PortCategory: String, CaseIterable, Identifiable {
    case all = "Semua"
    case web = "Web"
    case dev = "Developer"
    case database = "Database"
    case system = "Sistem"
    case other = "Lainnya"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .web: return "globe"
        case .dev: return "hammer.fill"
        case .database: return "cylinder.split.1x2.fill"
        case .system: return "apple.logo"
        case .other: return "network"
        }
    }
}

// MARK: - Port Process Information

public struct PortProcessInfo: Identifiable, Hashable {
    public let id: String
    public let pid: Int32
    public let processName: String
    public let commandPath: String?
    public let user: String
    public let port: Int
    public let protocolType: PortProtocol
    public var ipVersion: String // IPv4, IPv6, atau Dual-Stack
    public let bindAddress: String
    public let state: String
    public let isSystemProcess: Bool

    public var portString: String {
        return "\(port)"
    }

    public var pidString: String {
        return "\(pid)"
    }

    public init(
        pid: Int32,
        processName: String,
        commandPath: String? = nil,
        user: String,
        port: Int,
        protocolType: PortProtocol,
        ipVersion: String,
        bindAddress: String,
        state: String,
        isSystemProcess: Bool
    ) {
        self.id = "\(pid)_\(port)_\(protocolType.rawValue)_\(bindAddress)"
        self.pid = pid
        self.processName = processName
        self.commandPath = commandPath
        self.user = user
        self.port = port
        self.protocolType = protocolType
        self.ipVersion = ipVersion
        self.bindAddress = bindAddress
        self.state = state
        self.isSystemProcess = isSystemProcess
    }

    // MARK: - Computed Properties

    /// Klasifikasi otomatis kategori port berdasarkan port standar & nama proses
    public var category: PortCategory {
        if isSystemProcess {
            return .system
        }

        let p = port
        let name = processName.lowercased()

        // 1. Database
        if [5432, 3306, 6379, 27017, 1433, 9042, 8086, 9200, 26257].contains(p) ||
            name.contains("postgres") || name.contains("mysql") || name.contains("redis") ||
            name.contains("mongo") || name.contains("mariadb") || name.contains("memcached") ||
            name.contains("clickhouse") || name.contains("sqlite") {
            return .database
        }

        // 2. Web Servers & Frontend Frameworks
        let isWebPort = [80, 443, 8080, 8000, 8888].contains(p) ||
            (3000...3010).contains(p) || (5000...5010).contains(p) ||
            (5173...5180).contains(p) || (8000...8090).contains(p) ||
            (4200...4210).contains(p) || (9000...9010).contains(p)

        let isWebProcess = name.contains("php") || name.contains("vite") ||
            name.contains("next") || name.contains("nuxt") || name.contains("caddy") ||
            name.contains("nginx") || name.contains("apache") || name.contains("rails") ||
            name.contains("django") || name.contains("flask") || name.contains("uvicorn") ||
            name.contains("gunicorn") || name.contains("express") || name.contains("fastify") ||
            name.contains("puma") || name.contains("hugo")

        if isWebPort || isWebProcess {
            return .web
        }

        // 3. Developer Tooling, Compilers, Watchers, IDEs, Local AI
        let isDevProcess = name.contains("air") || name.contains("bun") ||
            name.contains("node") || name.contains("python") || name.contains("go") ||
            name.contains("cargo") || name.contains("rust") || name.contains("docker") ||
            name.contains("orbstack") || name.contains("antigravity") || name.contains("code") ||
            name.contains("cursor") || name.contains("windsurf") || name.contains("language_server") ||
            name.contains("ollama") || name.contains("electron") || name.contains("java") ||
            name.contains("dart") || name.contains("flutter") || name.contains("adb")

        let isDevPort = p == 9229 || p == 8828 || p == 8829 || p == 5037 || p == 5353

        if isDevProcess || isDevPort {
            return .dev
        }

        return .other
    }

    /// URL lokal jika port adalah HTTP web dev server
    public var localURL: URL? {
        guard protocolType == .tcp else { return nil }
        let host = (bindAddress == "*" || bindAddress == "0.0.0.0" || bindAddress == "[::1]") ? "localhost" : bindAddress
        return URL(string: "http://\(host):\(port)")
    }

    /// Alamat tampilan ringkas (misal localhost:3000 atau *:8080)
    public var displayAddress: String {
        if bindAddress == "*" || bindAddress == "0.0.0.0" {
            return "*:\(port)"
        } else if bindAddress == "127.0.0.1" || bindAddress == "[::1]" {
            return "localhost:\(port)"
        } else {
            return "\(bindAddress):\(port)"
        }
    }

    /// Icon resolusi: mencoba NSRunningApplication -> NSWorkspace path -> Fallback SF Symbol
    public var icon: NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid), let appIcon = app.icon {
            return appIcon
        }
        if let path = commandPath, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }

    /// Fallback SF Symbol icon jika tidak ada image bundle/file
    public var fallbackSymbolName: String {
        let name = processName.lowercased()
        if category == .database {
            return "cylinder.split.1x2.fill"
        }
        if name.contains("node") || name.contains("bun") || name.contains("deno") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if name.contains("python") {
            return "curlybraces.square.fill"
        }
        if name.contains("docker") || name.contains("container") {
            return "shippingbox.fill"
        }
        if name.contains("electron") || name.contains("antigravity") || name.contains("code") {
            return "app.dashed"
        }
        if isSystemProcess {
            return "gearshape.2.fill"
        }
        return "terminal.fill"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: PortProcessInfo, rhs: PortProcessInfo) -> Bool {
        lhs.id == rhs.id
    }
}
