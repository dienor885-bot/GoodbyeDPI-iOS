import NetworkExtension
import Network
import Foundation

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var config = DPIConfig.default.applyingMode
    private var doh: DoHClient!
    private var tcpConns: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "dpi.tunnel")
    private var packetLoopRunning = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        config = DPIConfig.load().applyingMode
        doh = DoHClient(url: config.dohURL)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1400
        let ipv4 = NEIPv4Settings(addresses: ["10.89.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.ipv6Settings = NEIPv6Settings(addresses: ["fd00:89::2"], networkPrefixLengths: [64])

        setTunnelNetworkSettings(settings) { [weak self] err in
            if let err { completionHandler(err); return }
            self?.packetLoopRunning = true
            self?.readPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        packetLoopRunning = false
        completionHandler()
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.packetLoopRunning else { return }
            for (i, pkt) in packets.enumerated() {
                let proto = protocols[i].intValue
                self.handle(packet: pkt, proto: proto)
            }
            self.readPackets()
        }
    }

    private func handle(packet: Data, proto: Int) {
        guard packet.count >= 20 else {
            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: proto)])
            return
        }
        let version = packet[0] >> 4
        if version == 4 {
            handleIPv4(packet)
        } else {
            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: proto)])
        }
    }

    private func handleIPv4(_ packet: Data) {
        let ihl = Int(packet[0] & 0x0f) * 4
        guard packet.count >= ihl + 8 else { return }
        let proto = packet[9]
        if proto == 17 {
            handleUDP(packet, ihl: ihl)
        } else if proto == 6 {
            handleTCP(packet, ihl: ihl)
        } else {
            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
        }
    }

    private func handleUDP(_ packet: Data, ihl: Int) {
        let dstPort = Int(packet[ihl + 2]) << 8 | Int(packet[ihl + 3])
        if dstPort == 53 {
            rewriteDNS(packet, ihl: ihl)
            return
        }
        if config.dropQUIC && dstPort == 443 {
            return
        }
        packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
    }

    private func rewriteDNS(_ packet: Data, ihl: Int) {
        let udpStart = ihl
        guard packet.count >= udpStart + 8 else { return }
        let dnsPayload = packet.subdata(in: (udpStart + 8)..<packet.count)
        guard let qname = DNSCodec.qname(dnsPayload) else {
            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
            return
        }
        let qtype = DNSCodec.qtype(dnsPayload)
        doh.resolve(qname, type: qtype) { [weak self] ips in
            guard let self else { return }
            let reply = DNSCodec.buildReply(query: dnsPayload, ips: ips, qtype: qtype)
            guard let resp = IPv4UDP.swap(packet, ihl: ihl, payload: reply) else { return }
            self.packetFlow.writePackets([resp], withProtocols: [NSNumber(value: AF_INET)])
        }
    }

    private func handleTCP(_ packet: Data, ihl: Int) {
        let tcpStart = ihl
        let dataOff = Int((packet[tcpStart + 12] >> 4) & 0x0f) * 4
        let payloadOff = tcpStart + dataOff
        guard packet.count > payloadOff else {
            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
            return
        }
        let payload = packet.subdata(in: payloadOff..<packet.count)
        let dstPort = Int(packet[tcpStart + 2]) << 8 | Int(packet[tcpStart + 3])

        if dstPort == 80, config.httpTricks, let host = HTTPTricks.host(from: payload), config.matches(host: host) {
            let mangled = HTTPTricks.mangle(payload)
            if let out = IPv4TCP.replacePayload(packet, ihl: ihl, tcpLen: dataOff, payload: mangled) {
                emitFragments(original: out, ihl: ihl, tcpLen: dataOff)
                return
            }
        }

        if dstPort == 443, let sni = TLSParse.sni(from: payload), config.matches(host: sni) {
            if config.mode == .six {
                let fake = FakeHello.packet(sni: "www.google.com")
                if let fp = IPv4TCP.replacePayload(packet, ihl: ihl, tcpLen: dataOff, payload: fake) {
                    packetFlow.writePackets([fp], withProtocols: [NSNumber(value: AF_INET)])
                }
            }
            emitFragments(original: packet, ihl: ihl, tcpLen: dataOff)
            return
        }

        packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
    }

    private func emitFragments(original: Data, ihl: Int, tcpLen: Int) {
        let payloadOff = ihl + tcpLen
        guard original.count > payloadOff else {
            packetFlow.writePackets([original], withProtocols: [NSNumber(value: AF_INET)])
            return
        }
        let payload = original.subdata(in: payloadOff..<original.count)
        let plan = FragmentPlan.split(payload, size: config.fragmentSize, atSNI: true, reverse: config.reverseFrag)
        var seq = IPv4TCP.seq(original, ihl: ihl)
        var packets: [Data] = []
        var prots: [NSNumber] = []
        for chunk in plan.chunks {
            if let p = IPv4TCP.replacePayload(original, ihl: ihl, tcpLen: tcpLen, payload: chunk, seq: seq) {
                packets.append(p)
                prots.append(NSNumber(value: AF_INET))
            }
            seq = seq &+ UInt32(chunk.count)
        }
        if !packets.isEmpty {
            packetFlow.writePackets(packets, withProtocols: prots)
        }
    }
}

enum DNSCodec {
    static func qname(_ msg: Data) -> String? {
        guard msg.count > 12 else { return nil }
        var i = 12
        var labels: [String] = []
        while i < msg.count {
            let l = Int(msg[i])
            if l == 0 { break }
            i += 1
            guard i + l <= msg.count else { return nil }
            labels.append(String(bytes: msg[i..<(i + l)], encoding: .utf8) ?? "")
            i += l
        }
        return labels.joined(separator: ".")
    }

    static func qtype(_ msg: Data) -> UInt16 {
        guard msg.count > 12 else { return 1 }
        var i = 12
        while i < msg.count {
            let l = Int(msg[i])
            if l == 0 {
                i += 1
                break
            }
            i += 1 + l
        }
        guard i + 2 <= msg.count else { return 1 }
        return UInt16(msg[i]) << 8 | UInt16(msg[i + 1])
    }

    static func buildReply(query: Data, ips: [String], qtype: UInt16) -> Data {
        var out = Data(query)
        if out.count >= 4 {
            out[2] = 0x81
            out[3] = 0x80
        }
        var an: UInt16 = 0
        for ip in ips {
            if qtype == 1, let a = IPv4.parse(ip) {
                appendA(&out, query: query, addr: a)
                an += 1
            }
        }
        if out.count >= 8 {
            out[6] = UInt8(an >> 8)
            out[7] = UInt8(an & 0xff)
        }
        return out
    }

    private static func appendA(_ out: inout Data, query: Data, addr: [UInt8]) {
        out.append(contentsOf: [0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3c, 0x00, 0x04])
        out.append(contentsOf: addr)
    }
}

enum IPv4 {
    static func parse(_ s: String) -> [UInt8]? {
        let p = s.split(separator: ".")
        guard p.count == 4 else { return nil }
        let b = p.compactMap { UInt8($0) }
        guard b.count == 4 else { return nil }
        return b
    }

    static func checksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        let bytes = [UInt8](data)
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }
}

enum IPv4UDP {
    static func swap(_ packet: Data, ihl: Int, payload: Data) -> Data? {
        var out = Data(packet.prefix(ihl + 8)) + payload
        guard out.count >= ihl + 8 else { return nil }
        let srcIP = out.subdata(in: 12..<16)
        let dstIP = out.subdata(in: 16..<20)
        out.replaceSubrange(12..<16, with: dstIP)
        out.replaceSubrange(16..<20, with: srcIP)
        let sp = out.subdata(in: (ihl)..<(ihl + 2))
        let dp = out.subdata(in: (ihl + 2)..<(ihl + 4))
        out.replaceSubrange((ihl)..<(ihl + 2), with: dp)
        out.replaceSubrange((ihl + 2)..<(ihl + 4), with: sp)
        let total = UInt16(out.count)
        out[2] = UInt8(total >> 8)
        out[3] = UInt8(total & 0xff)
        out[10] = 0
        out[11] = 0
        let csum = IPv4.checksum(out.prefix(ihl))
        out[10] = UInt8(csum >> 8)
        out[11] = UInt8(csum & 0xff)
        let ulen = UInt16(8 + payload.count)
        out[ihl + 4] = UInt8(ulen >> 8)
        out[ihl + 5] = UInt8(ulen & 0xff)
        out[ihl + 6] = 0
        out[ihl + 7] = 0
        return out
    }
}

enum IPv4TCP {
    static func seq(_ packet: Data, ihl: Int) -> UInt32 {
        let b = packet
        let o = ihl + 4
        return UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
    }

    static func replacePayload(_ packet: Data, ihl: Int, tcpLen: Int, payload: Data, seq: UInt32? = nil) -> Data? {
        var head = Data(packet.prefix(ihl + tcpLen))
        if let seq {
            let o = ihl + 4
            head[o] = UInt8((seq >> 24) & 0xff)
            head[o + 1] = UInt8((seq >> 16) & 0xff)
            head[o + 2] = UInt8((seq >> 8) & 0xff)
            head[o + 3] = UInt8(seq & 0xff)
        }
        var out = head + payload
        let total = UInt16(out.count)
        out[2] = UInt8(total >> 8)
        out[3] = UInt8(total & 0xff)
        out[10] = 0
        out[11] = 0
        let ipcs = IPv4.checksum(out.prefix(ihl))
        out[10] = UInt8(ipcs >> 8)
        out[11] = UInt8(ipcs & 0xff)
        out[ihl + 16] = 0
        out[ihl + 17] = 0
        var pseudo = Data()
        pseudo.append(out.subdata(in: 12..<20))
        pseudo.append(contentsOf: [0, 6])
        let tcpLenAll = UInt16(tcpLen + payload.count)
        pseudo.append(contentsOf: [UInt8(tcpLenAll >> 8), UInt8(tcpLenAll & 0xff)])
        pseudo.append(out.subdata(in: ihl..<out.count))
        if pseudo.count % 2 == 1 { pseudo.append(0) }
        let tcs = IPv4.checksum(pseudo)
        out[ihl + 16] = UInt8(tcs >> 8)
        out[ihl + 17] = UInt8(tcs & 0xff)
        return out
    }
}
