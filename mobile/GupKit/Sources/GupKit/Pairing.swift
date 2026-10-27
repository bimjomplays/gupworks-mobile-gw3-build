import Foundation
#if canImport(Security)
import Security
#endif

/// The paired PC: its base URL, the token it gave this phone and what it said about itself. Lives only in the
/// Keychain (this device only, readable while unlocked), never in UserDefaults or files.
struct Pairing: Codable, Equatable {
    var baseURL: URL
    var token: String
    var pairedAt: Date
    var pcName: String

    /// The machine name only (first label of the host), for the UI.
    var shortHost: String { String((baseURL.host ?? "").split(separator: ".").first ?? "") }
}

#if canImport(Security)
enum PairingStore {
    private static let service = "app.gupworks3.phone.pairing"
    private static let account = "pc"

    private static var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    /// nil = not paired (or the item can't be read right now).
    static func load() -> Pairing? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    @discardableResult
    static func save(_ pairing: Pairing) -> Bool {
        guard let data = try? JSONEncoder().encode(pairing) else { return false }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(item as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(item.merging(attrs) { $1 } as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func clear() {
        SecItemDelete(item as CFDictionary)
    }
}
#else
/// Linux (GupKit's tests): no Keychain, so the pairing is kept in memory only.
enum PairingStore {
    private static var kept: Pairing?
    static func load() -> Pairing? { kept }
    @discardableResult
    static func save(_ pairing: Pairing) -> Bool { kept = pairing; return true }
    static func clear() { kept = nil }
}
#endif

/// The pairing link the PC shows as a QR code (`gw3-phone pair`):
///     gupworks3://pair?v=1&url=<percent-encoded https://<pc>.<tailnet>.ts.net:10005>&code=<one-time code>
/// The address must be a Tailscale HTTPS name, so a code can't point the app at an ordinary internet host.
struct PairLink: Equatable {
    let baseURL: URL
    let code: String

    enum Problem: Error, Equatable {
        case notOurs, newerVersion, badAddress, badCode

        var message: String {
            switch self {
            case .notOurs: return "That isn't a GupWorks pairing code. On the PC, run gw3-phone pair."
            case .newerVersion: return "The PC made a code this app doesn't know yet. Update the app, then try again."
            case .badAddress: return "The code's PC address isn't a Tailscale HTTPS name, so the app won't use it."
            case .badCode: return "The code is cut off or damaged. Make a new one on the PC."
            }
        }
    }

    static func parse(_ text: String) -> Result<PairLink, Problem> {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "gupworks3", c.host?.lowercased() == "pair",
              c.path.isEmpty || c.path == "/", let items = c.queryItems else { return .failure(.notOurs) }
        var q: [String: String] = [:]
        for it in items {
            guard q[it.name] == nil else { return .failure(.notOurs) }  // a field twice: crafted, not from the PC
            q[it.name] = it.value ?? ""
        }
        guard let v = q["v"].flatMap(Int.init) else { return .failure(.notOurs) }
        guard v == 1 else { return .failure(v > 1 ? .newerVersion : .notOurs) }
        guard let raw = q["url"], let url = tailnetBaseURL(raw) else { return .failure(.badAddress) }
        guard let code = q["code"], isCode(code) else { return .failure(.badCode) }
        return .success(PairLink(baseURL: url, code: code))
    }

    /// https://<machine>.<tailnet>.ts.net[:port][/] with nothing else (no user, path, query or fragment)
    static func tailnetBaseURL(_ raw: String) -> URL? {
        guard let c = URLComponents(string: raw), c.scheme?.lowercased() == "https",
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", let host = c.host?.lowercased() else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let ok = CharacterSet.ascii(upper: false, plus: "-")
        guard labels.count >= 4, labels.suffix(2) == ["ts", "net"],
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.unicodeScalars.allSatisfy(ok.contains) })
        else { return nil }
        var out = URLComponents()
        out.scheme = "https"
        out.host = host
        out.port = c.port
        return out.url
    }

    /// base64url without padding; the PC makes 43 characters (32 bytes)
    static func isCode(_ s: String) -> Bool {
        (43...128).contains(s.count) && s.unicodeScalars.allSatisfy(CharacterSet.ascii(plus: "-_").contains)
    }
}

extension CharacterSet {
    /// ASCII digits and letters (lower case, and upper case unless `upper` is false) plus the characters in `plus`.
    static func ascii(upper: Bool = true, plus: String) -> CharacterSet {
        var set = CharacterSet(charactersIn: "0"..."9")
        set.formUnion(CharacterSet(charactersIn: "a"..."z"))
        if upper { set.formUnion(CharacterSet(charactersIn: "A"..."Z")) }
        set.insert(charactersIn: plus)
        return set
    }
}
