import Foundation

public enum DPIMode: Int, CaseIterable, Codable {
    case five = 5
    case six = 6
    case nine = 9

    public var title: String {
        switch self {
        case .five: return "Mode 5 — fragment + reverse"
        case .six: return "Mode 6 — fragment + fake hello"
        case .nine: return "Mode 9 — fragment + drop QUIC"
        }
    }
}

public struct DPIConfig: Codable, Equatable {
    public var enabled: Bool
    public var mode: DPIMode
    public var dohURL: String
    public var fragmentSize: Int
    public var reverseFrag: Bool
    public var dropQUIC: Bool
    public var httpTricks: Bool
    public var hosts: [String]

    public static let appGroup = "group.goodbye.dpi"
    public static let key = "dpi.config"

    public static var `default`: DPIConfig {
        DPIConfig(
            enabled: true,
            mode: .nine,
            dohURL: "https://1.1.1.1/dns-query",
            fragmentSize: 2,
            reverseFrag: true,
            dropQUIC: true,
            httpTricks: true,
            hosts: [
                "discord.com",
                "discordapp.com",
                "discord.gg",
                "gateway.discord.gg",
                "cdn.discordapp.com",
                "media.discordapp.net",
                "discord-attachments-uploads-prd.storage.googleapis.com",
                "youtube.com",
                "youtu.be",
                "googlevideo.com",
                "instagram.com",
                "cdninstagram.com",
                "twitter.com",
                "x.com",
                "t.co"
            ]
        )
    }

    public func matches(host: String) -> Bool {
        let h = host.lowercased()
        return hosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    public static func load() -> DPIConfig {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = defaults.data(forKey: Self.key),
              let cfg = try? JSONDecoder().decode(DPIConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    public func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public var applyingMode: DPIConfig {
        var c = self
        switch mode {
        case .five:
            c.fragmentSize = 2
            c.reverseFrag = true
            c.dropQUIC = false
        case .six:
            c.fragmentSize = 2
            c.reverseFrag = true
            c.dropQUIC = false
        case .nine:
            c.fragmentSize = 2
            c.reverseFrag = true
            c.dropQUIC = true
        }
        return c
    }
}
