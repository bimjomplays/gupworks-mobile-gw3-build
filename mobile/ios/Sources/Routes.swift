import Darwin
import Foundation

/// The two ways to the PC. One is its Tailscale name over HTTPS (the pairing's address). The other is its tailnet
/// address directly, once the PC has sent it in hello: plain HTTP inside Tailscale's encrypted tunnel, through
/// `tailscale serve --tcp`. The direct way needs no name lookup, and the lookup is what fails on some days: the
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

    init(defaults: UserDefaults = .standard, tunnelUp: @escaping () -> Bool = Tailnet.isUp) {
        self.defaults = defaults
        self.tunnelUp = tunnelUp
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
