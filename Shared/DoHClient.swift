import Foundation
import Network

public final class DoHClient {
    private let session: URLSession
    private let endpoint: URL
    private var cache: [String: [String]] = [:]
    private let lock = NSLock()

    public init(url: String) {
        endpoint = URL(string: url) ?? URL(string: "https://1.1.1.1/dns-query")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 8
        session = URLSession(configuration: cfg)
    }

    public func resolve(_ name: String, type: UInt16 = 1, completion: @escaping ([String]) -> Void) {
        lock.lock()
        if let hit = cache[name + ".\(type)"] {
            lock.unlock()
            completion(hit)
            return
        }
        lock.unlock()

        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var q = comps.queryItems ?? []
        q.append(URLQueryItem(name: "name", value: name))
        q.append(URLQueryItem(name: "type", value: type == 1 ? "A" : "AAAA"))
        comps.queryItems = q
        var req = URLRequest(url: comps.url!)
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        session.dataTask(with: req) { [weak self] data, _, _ in
            var ips: [String] = []
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ans = obj["Answer"] as? [[String: Any]] {
                for a in ans {
                    if let t = a["type"] as? Int, t == Int(type), let d = a["data"] as? String {
                        ips.append(d)
                    }
                }
            }
            if let self {
                self.lock.lock()
                self.cache[name + ".\(type)"] = ips
                self.lock.unlock()
            }
            completion(ips)
        }.resume()
    }
}
