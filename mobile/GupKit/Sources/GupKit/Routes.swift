#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// The two ways to the PC. One is its Tailscale name over HTTPS (the pairing's address). The other is its tailnet
/// address directly, once the PC has sent it in hello or Tailscale's own DNS has told it: plain HTTP inside
/// Tailscale's encrypted tunnel, through `tailscale serve --tcp`. The direct way needs no name lookup, and the lookup is what fails on some days: the
/// phone's DNS answers the ts.net name from the public records Funnel adds, so the request waits on Tailscale's relays
/// until it times out, while the tunnel itself works.
final class Routes: @unchecked Sendable {
    static let shared = Routes()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let tunnelUp: () -> Bool
    private var directs: [String: URL]  // the pairing's address -> the PC's direct address
    private var good: [String: URL]     // the pairing's address -> the way that last answered
    private var bad: [String: URL] = [:]  // the way that last failed, tried last until it answers again

    private let lookup: @Sendable (String) async -> String?
    private var asked: [String: Date] = [:]  // when Tailscale's DNS was last asked for a pairing's name

    /// gw3-phone's port for the direct way (`tailscale serve --tcp=10007`, bin/gw3-install-phone)
    static let directPort = 10007

    init(defaults: UserDefaults = .standard, tunnelUp: @escaping () -> Bool = Tailnet.isUp,
         lookup: @escaping @Sendable (String) async -> String? = { await MagicDNS.lookup($0) }) {
        self.defaults = defaults
        self.tunnelUp = tunnelUp
        self.lookup = lookup
        directs = Self.load(defaults, "routes.direct")
        good = Self.load(defaults, "routes.good")
    }

    /// The ways to try, in order. The direct way comes first, but only while Tailscale's tunnel is up on this iPhone,
    /// so its plain HTTP never goes out on a network where that address means something else. The way that last
    /// answered goes first, and the way that last failed goes last.
    func order(for base: URL) -> [URL] {
        let up = tunnelUp()
        lock.lock()
        defer { lock.unlock() }
        let key = base.absoluteString
        var ways = [base]
        if up, let d = directs[key] { ways = [d, base] }
        if let b = bad[key], ways.count > 1, ways.contains(b) { ways = ways.filter { $0 != b } + [b] }
        if let g = good[key], ways.contains(g) { ways = [g] + ways.filter { $0 != g } }
        return ways
    }

    /// Where pictures and links load from now.
    func current(for base: URL) -> URL { order(for: base).first ?? base }

    /// The PC's direct address from hello. Only an `http://` tailnet IPv4 address with a port is kept, so a wrong
    /// answer can't send the token anywhere else in plain text.
    func learn(_ direct: String?, for base: URL) {
        let key = base.absoluteString
        lock.lock()
        defer { lock.unlock() }
        let url = direct.flatMap(Self.validDirect)
        guard directs[key] != url else { return }
        if let old = directs[key] {
            if good[key] == old { good[key] = nil }
            if bad[key] == old { bad[key] = nil }
        }
        directs[key] = url
        save()
    }

    /// No direct address known yet (the first open after an update, or the name has failed ever since pairing): ask
    /// Tailscale's own DNS server for the PC's address. It answers inside the tunnel, so it works on exactly the
    /// days the phone's own lookup goes outside it. At most once a minute per PC.
    func discover(for base: URL) async {
        guard let host = base.host, host.hasSuffix(".ts.net"), shouldAsk(base) else { return }
        guard let ip = await lookup(host) else { return }
        learnFound("http://\(ip):\(Self.directPort)", for: base)
    }

    private func shouldAsk(_ base: URL) -> Bool {
        guard tunnelUp() else { return false }
        let key = base.absoluteString
        lock.lock()
        defer { lock.unlock() }
        guard directs[key] == nil, asked[key].map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return false }
        asked[key] = Date()
        return true
    }

    /// what discover found, unless hello taught an address meanwhile
    private func learnFound(_ direct: String, for base: URL) {
        lock.lock()
        let known = directs[base.absoluteString] != nil
        lock.unlock()
        if !known { learn(direct, for: base) }
    }

    func worked(_ way: URL, for base: URL) {
        let key = base.absoluteString
        lock.lock()
        defer { lock.unlock() }
        if bad[key] == way { bad[key] = nil }
        guard good[key] != way else { return }
        good[key] = way
        save()
    }

    func failed(_ way: URL, for base: URL) {
        let key = base.absoluteString
        lock.lock()
        defer { lock.unlock() }
        bad[key] = way
        if good[key] == way {
            good[key] = nil
            save()
        }
    }

    /// Unpaired: nothing about that PC stays.
    func forget(_ base: URL) {
        let key = base.absoluteString
        lock.lock()
        defer { lock.unlock() }
        directs[key] = nil
        good[key] = nil
        bad[key] = nil
        asked[key] = nil
        save()
    }

    static func validDirect(_ text: String) -> URL? {
        guard let c = URLComponents(string: text), c.scheme == "http", let host = c.host, let port = c.port,
              port > 0, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/",
              let v4 = Tailnet.ipv4(host), Tailnet.isTailnet(v4)
        else { return nil }
        return URL(string: "http://\(host):\(port)")
    }

    private func save() {  // called with the lock held
        defaults.set(directs.mapValues(\.absoluteString), forKey: "routes.direct")
        defaults.set(good.mapValues(\.absoluteString), forKey: "routes.good")
    }

    private static func load(_ d: UserDefaults, _ key: String) -> [String: URL] {
        (d.dictionary(forKey: key) as? [String: String] ?? [:]).compactMapValues { URL(string: $0) }
    }
}

/// Tailscale's addresses: 100.64.0.0/10 for IPv4 and fd7a:115c:a1e0::/48 for IPv6, on every tailnet.
enum Tailnet {
    /// Tailscale's tunnel is up on this iPhone: a VPN interface (utun) holds a tailnet address. A cellular network's
    /// carrier NAT can use the same IPv4 range, but not on a utun interface.
    static func isUp() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            defer { p = ifa.pointee.ifa_next }
            guard String(cString: ifa.pointee.ifa_name).hasPrefix("utun"), let sa = ifa.pointee.ifa_addr else { continue }
            if sa.pointee.sa_family == UInt8(AF_INET) {
                let a = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                if isTailnet(withUnsafeBytes(of: a) { Array($0) }) { return true }
            } else if sa.pointee.sa_family == UInt8(AF_INET6) {
                let a = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                if isTailnet6(withUnsafeBytes(of: a) { Array($0) }) { return true }
            }
        }
        return false
    }

    /// the four bytes of a dotted IPv4 address, or nil
    static func ipv4(_ text: String) -> [UInt8]? {
        var a = in_addr()
        guard inet_pton(AF_INET, text, &a) == 1 else { return nil }
        return withUnsafeBytes(of: a) { Array($0) }
    }

    static func isTailnet(_ v4: [UInt8]) -> Bool {
        v4.count == 4 && v4[0] == 100 && v4[1] & 0xC0 == 64
    }

    static func isTailnet6(_ v6: [UInt8]) -> Bool {
        v6.count == 16 && Array(v6.prefix(6)) == [0xFD, 0x7A, 0x11, 0x5C, 0xA1, 0xE0]
    }
}

/// Tailscale's DNS server (MagicDNS), at the same address on every device inside the tunnel. One A query over UDP.
enum MagicDNS {
    static func lookup(_ name: String) async -> String? {
        await Task.detached { lookupNow(name) }.value
    }

    /// the name's first tailnet IPv4 address, or nil (no answer in two seconds, or none in the tailnet's range)
    static func lookupNow(_ name: String) -> String? {
        let id = UInt16.random(in: 0...UInt16.max)
        guard let q = query(name, id: id) else { return nil }
        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        #else
        let fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), Int32(IPPROTO_UDP))
        #endif
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var limit = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        var to = sockaddr_in()
        #if canImport(Darwin)
        to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        to.sin_family = sa_family_t(AF_INET)
        to.sin_port = in_port_t(53).bigEndian
        to.sin_addr = in_addr(s_addr: 0x6464_6464)  // Tailscale's DNS: 100 in every byte, so byte order doesn't matter
        let sent = q.withUnsafeBytes { bytes in
            withUnsafePointer(to: &to) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == q.count else { return nil }
        let size = 512
        var reply = [UInt8](repeating: 0, count: size)
        for _ in 0..<3 {  // a late reply to an earlier query has another id: read on
            let n = recv(fd, &reply, size, 0)
            guard n > 0 else { return nil }
            if let ip = firstTailnetA(Array(reply[0..<n]), id: id) { return ip }
        }
        return nil
    }

    static func query(_ name: String, id: UInt16) -> [UInt8]? {
        var q: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xFF), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]  // recursion desired
        for label in name.split(separator: ".") {
            let b = Array(label.utf8)
            guard (1...63).contains(b.count) else { return nil }
            q.append(UInt8(b.count))
            q += b
        }
        q += [0, 0, 1, 0, 1]  // end of name, type A, class IN
        return q
    }

    static func firstTailnetA(_ r: [UInt8], id: UInt16) -> String? {
        guard r.count >= 12, r[0] == UInt8(id >> 8), r[1] == UInt8(id & 0xFF), r[2] & 0x80 != 0, r[3] & 0x0F == 0
        else { return nil }
        let questions = Int(r[4]) << 8 | Int(r[5]), answers = Int(r[6]) << 8 | Int(r[7])
        var i = 12
        func skipName() -> Bool {
            while i < r.count {
                let n = Int(r[i])
                if n == 0 { i += 1; return true }
                if n & 0xC0 == 0xC0 { i += 2; return i <= r.count }
                i += 1 + n
            }
            return false
        }
        for _ in 0..<questions {
            guard skipName(), i + 4 <= r.count else { return nil }
            i += 4
        }
        for _ in 0..<answers {
            guard skipName(), i + 10 <= r.count else { return nil }
            let type = Int(r[i]) << 8 | Int(r[i + 1]), length = Int(r[i + 8]) << 8 | Int(r[i + 9])
            i += 10
            guard i + length <= r.count else { return nil }
            if type == 1, length == 4, Tailnet.isTailnet(Array(r[i..<i + 4])) {
                return r[i..<i + 4].map(String.init).joined(separator: ".")
            }
            i += length
        }
        return nil
    }
}
