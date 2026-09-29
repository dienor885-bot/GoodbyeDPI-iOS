import Foundation

public enum TLSParse {
    public static func sni(from payload: Data) -> String? {
        guard payload.count >= 10 else { return nil }
        guard payload[0] == 0x16, payload[5] == 0x01 else { return nil }
        var i = 5
        guard i + 4 <= payload.count else { return nil }
        let hsLen = (Int(payload[i + 1]) << 16) | (Int(payload[i + 2]) << 8) | Int(payload[i + 3])
        i += 4
        guard i + 2 + 32 + 1 <= payload.count else { return nil }
        i += 2
        i += 32
        let sidLen = Int(payload[i])
        i += 1 + sidLen
        guard i + 2 <= payload.count else { return nil }
        let csLen = (Int(payload[i]) << 8) | Int(payload[i + 1])
        i += 2 + csLen
        guard i + 1 <= payload.count else { return nil }
        let cmLen = Int(payload[i])
        i += 1 + cmLen
        guard i + 2 <= payload.count else { return nil }
        let extLen = (Int(payload[i]) << 8) | Int(payload[i + 1])
        i += 2
        let extEnd = min(payload.count, i + extLen)
        while i + 4 <= extEnd {
            let typ = (Int(payload[i]) << 8) | Int(payload[i + 1])
            let len = (Int(payload[i + 2]) << 8) | Int(payload[i + 3])
            i += 4
            if typ == 0x0000, i + 5 <= payload.count {
                var j = i + 2
                guard j + 3 <= payload.count else { return nil }
                let ntype = payload[j]
                let nlen = (Int(payload[j + 1]) << 8) | Int(payload[j + 2])
                j += 3
                if ntype == 0, j + nlen <= payload.count {
                    return String(bytes: payload[j..<(j + nlen)], encoding: .utf8)
                }
            }
            i += len
            _ = hsLen
        }
        return nil
    }

    public static func sniOffset(in payload: Data) -> Int? {
        guard payload.count >= 10, payload[0] == 0x16, payload[5] == 0x01 else { return nil }
        var i = 5 + 4 + 2 + 32
        guard i < payload.count else { return nil }
        i += 1 + Int(payload[i])
        guard i + 2 <= payload.count else { return nil }
        let csLen = (Int(payload[i]) << 8) | Int(payload[i + 1])
        i += 2 + csLen
        guard i + 1 <= payload.count else { return nil }
        i += 1 + Int(payload[i])
        guard i + 2 <= payload.count else { return nil }
        let extLen = (Int(payload[i]) << 8) | Int(payload[i + 1])
        i += 2
        let extEnd = min(payload.count, i + extLen)
        while i + 4 <= extEnd {
            let typ = (Int(payload[i]) << 8) | Int(payload[i + 1])
            let len = (Int(payload[i + 2]) << 8) | Int(payload[i + 3])
            i += 4
            if typ == 0x0000 {
                return i
            }
            i += len
        }
        return nil
    }
}

public enum HTTPTricks {
    public static func host(from payload: Data) -> String? {
        guard let s = String(data: payload.prefix(2048), encoding: .ascii) else { return nil }
        for line in s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("host:") {
                return t.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()
            }
        }
        return nil
    }

    public static func mangle(_ payload: Data) -> Data {
        guard var s = String(data: payload, encoding: .ascii) else { return payload }
        if let r = s.range(of: "Host:", options: .caseInsensitive) {
            s.replaceSubrange(r, with: "hoSt:")
        }
        s = s.replacingOccurrences(of: "hoSt: ", with: "hoSt:")
        if let range = s.range(of: "hoSt:") {
            let after = s[range.upperBound...]
            var mixed = ""
            var up = false
            for ch in after {
                if ch == "\r" || ch == "\n" { mixed.append(ch); break }
                if ch.isLetter {
                    mixed.append(up ? Character(ch.uppercased()) : Character(ch.lowercased()))
                    up.toggle()
                } else {
                    mixed.append(ch)
                }
            }
            let restStart = s.index(range.upperBound, offsetBy: mixed.count)
            s = String(s[..<range.upperBound]) + mixed + String(s[restStart...])
        }
        return Data(s.utf8)
    }
}

public struct FragmentPlan {
    public let chunks: [Data]

    public static func split(_ data: Data, size: Int, atSNI: Bool, reverse: Bool) -> FragmentPlan {
        var parts: [Data] = []
        if atSNI, let off = TLSParse.sniOffset(in: data), off > 0, off < data.count {
            parts.append(data.prefix(off))
            parts.append(data.suffix(from: off))
        } else {
            let n = max(1, size)
            var i = 0
            while i < data.count {
                let end = min(data.count, i + n)
                if i == 0 && n < 40 && data.count > 40 {
                    parts.append(data.prefix(n))
                    i = n
                    continue
                }
                parts.append(data[i..<end])
                i = end
            }
        }
        if reverse && parts.count > 1 {
            parts.reverse()
        }
        return FragmentPlan(chunks: parts)
    }
}

public enum FakeHello {
    public static func packet(sni: String) -> Data {
        var d = Data()
        d.append(contentsOf: [0x16, 0x03, 0x01, 0x00, 0x00])
        d.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        d.append(contentsOf: [0x03, 0x03])
        d.append(contentsOf: (0..<32).map { _ in UInt8.random(in: 0...255) })
        d.append(0x00)
        d.append(contentsOf: [0x00, 0x02, 0x00, 0x2f])
        d.append(contentsOf: [0x01, 0x00])
        let name = Array(sni.utf8)
        let ext: [UInt8] = [0x00, 0x00, 0x00, UInt8(5 + name.count), 0x00, UInt8(3 + name.count), 0x00, 0x00, UInt8(name.count)] + name
        d.append(contentsOf: [UInt8((ext.count >> 8) & 0xff), UInt8(ext.count & 0xff)])
        d.append(contentsOf: ext)
        let recLen = d.count - 5
        d[3] = UInt8((recLen >> 8) & 0xff)
        d[4] = UInt8(recLen & 0xff)
        let hsLen = d.count - 9
        d[6] = UInt8((hsLen >> 16) & 0xff)
        d[7] = UInt8((hsLen >> 8) & 0xff)
        d[8] = UInt8(hsLen & 0xff)
        return d
    }
}
