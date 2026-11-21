import Foundation
#if canImport(Security)
import Security
#endif

// Apple push (a233, docs/mobile-app-plan.md slice 7): gw3-phone sends a push for every new needs-you item
// (tools/gw3_push.py) and a silent one when it is gone. These are the app's plain rules for it: the notification
// categories and their buttons, what a button sends to the PC, which delivered notifications to take back, which APNs
// environment this build talks to, and the answer-only token kept readable while the phone is locked. The
// UserNotifications glue is in ios/Sources/PushCenter.swift.

/// One button on a notification. `text`: a text-input action ("Something else…"; the watch offers dictation, Scribble
/// and its keyboard). `destructive`: drawn red.
struct PushButton: Equatable {
    var id: String
    var title: String
    var text = false
    var destructive = false
}

/// The categories gw3-phone names in `aps.category` (gw3_push.category). Labels are fixed per category, so an ask's
/// answers can't be its own words here: the recommended one is "Send recommended" and the notification's text says
/// which it is ("Recommended: …"). The watch app's own notification view (Option 7, next step) shows the real answers.
enum PushCategory {
    static let rec = PushButton(id: "gw3.rec", title: "Send recommended")
    static let other = PushButton(id: "gw3.other", title: "Something else…", text: true)
    static let dismiss = PushButton(id: "gw3.dismiss", title: "Dismiss", destructive: true)
    static let allow = PushButton(id: "gw3.allow", title: "Allow once")
    static let deny = PushButton(id: "gw3.deny", title: "Deny", destructive: true)
    static let sleep = PushButton(id: "gw3.sleep", title: "Sleep idle chats")

    /// the text field's button and placeholder for "Something else…"
    static let sendTitle = "Send"
    static let placeholder = "Your answer"

    /// every category with its buttons, in the order they show
    static let all: [(id: String, buttons: [PushButton])] = [
        ("gw3.ask.rec.other", [rec, other, dismiss]),
        ("gw3.ask.rec", [rec, dismiss]),
        ("gw3.ask.other", [other, dismiss]),
        ("gw3.ask", [dismiss]),
        ("gw3.permission", [allow, deny]),
        ("gw3.memory", [sleep, dismiss]),
        ("gw3.open", []),
    ]

    static func buttons(_ category: String) -> [PushButton] {
        all.first { $0.id == category }?.buttons ?? []
    }
}

/// What a notification's button (or the watch, a234) does: one request to gw3-phone's needs-you routes, the same
/// ones the deck uses. All of them work with the answer-only token (gw3_push.ANSWER_ROUTES).
enum PushAction: Equatable {
    case answer(key: String, option: Int)
    case text(key: String, words: String)
    case dismiss(key: String)
    case snooze(key: String)
    case park(project: String, parked: Bool)

    var key: String {
        switch self {
        case .answer(let k, _), .text(let k, _), .dismiss(let k), .snooze(let k): return k
        case .park(let p, _): return "park:\(p)"
        }
    }

    var path: String {
        switch self {
        case .dismiss: return "/v1/needs/dismiss"
        case .snooze: return "/v1/needs/snooze"
        case .park: return "/v1/needs/park"
        case .answer, .text: return "/v1/needs/answer"
        }
    }

    var body: NeedsAction {
        switch self {
        case .answer(let k, let o): return NeedsAction(key: k, option: o)
        case .text(let k, let w): return NeedsAction(key: k, text: w)
        case .dismiss(let k), .snooze(let k): return NeedsAction(key: k)
        case .park(let p, let parked): return NeedsAction(projectId: p, parked: parked)
        }
    }

    /// What the watch handed over (a234); nil for Open on iPhone, which the iPhone shows itself.
    init?(_ s: WatchSend) {
        switch s.what {
        case .answer:
            if let o = s.option { self = .answer(key: s.key, option: o) }
            else if let t = s.text, !t.isEmpty { self = .text(key: s.key, words: t) }
            else { return nil }
        case .snooze: self = .snooze(key: s.key)
        case .dismiss: self = .dismiss(key: s.key)
        case .park:
            guard let p = s.projectId, !p.isEmpty else { return nil }
            self = .park(project: p, parked: s.parked ?? false)
        case .open, .say: return nil  // a235: words for a main chat go by the chat route, not a needs-you one
        }
    }

    /// The button `action` (its id) pressed on a notification whose payload is `info`; nil for a tap on the
    /// notification itself, a button this push doesn't carry, or "Something else…" sent empty.
    static func from(action: String, info: [AnyHashable: Any], text: String? = nil) -> PushAction? {
        guard let key = info["needs"] as? String, !key.isEmpty else { return nil }
        let g = info["gw3"] as? [String: Any] ?? [:]
        func index(_ name: String) -> Int? { PushPayload.int(g[name]).flatMap { $0 >= 0 ? $0 : nil } }
        switch action {
        case PushCategory.rec.id: return index("rec").map { .answer(key: key, option: $0) }
        case PushCategory.allow.id: return index("allow").map { .answer(key: key, option: $0) }
        case PushCategory.deny.id: return index("deny").map { .answer(key: key, option: $0) }
        case PushCategory.sleep.id: return .answer(key: key, option: index("sleep") ?? 0)
        case PushCategory.dismiss.id: return .dismiss(key: key)
        case let a where a.hasPrefix(WatchNotice.optionPrefix):
            // the watch's own notification buttons (a234), should the watch hand a tap to the iPhone
            return Int(a.dropFirst(WatchNotice.optionPrefix.count)).flatMap { $0 >= 0 ? .answer(key: key, option: $0) : nil }
        case PushCategory.other.id:
            let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return words.isEmpty ? nil : .text(key: key, words: String(words.prefix(4000)))
        default: return nil
        }
    }
}

enum PushPayload {
    /// a number from a push's JSON (NSNumber on Apple's side, Int or Double elsewhere)
    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d.rounded() == d { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    /// The needs-you item a notification is about (userInfo "needs"); nil for the app's other notifications.
    static func key(_ info: [AnyHashable: Any]) -> String? {
        (info["needs"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The delivered notifications to take back after a silent push (`gone`, `live`) or a fresh list from the PC
    /// (`live` only): every needs-you notification whose item is gone, or not live when the PC says what is.
    /// `delivered`: (notification id, its item key or nil for other notifications).
    static func toRemove(_ delivered: [(id: String, key: String?)], gone: Set<String> = [], live: Set<String>?) -> [String] {
        delivered.compactMap { d in
            guard let k = d.key else { return nil }
            if gone.contains(k) { return d.id }
            if let live, !live.contains(k) { return d.id }
            return nil
        }
    }

    /// (gone, live) from a silent push's userInfo
    static func removal(_ info: [AnyHashable: Any]) -> (gone: Set<String>, live: Set<String>?)? {
        let gone = (info["gone"] as? [Any])?.compactMap { $0 as? String }
        let live = (info["live"] as? [Any])?.compactMap { $0 as? String }
        guard gone != nil || live != nil else { return nil }
        return (Set(gone ?? []), live.map(Set.init))
    }
}

/// Which APNs gw3-phone must use for this build's token, read from the build's embedded provisioning profile: a
/// development-signed build says `aps-environment` development there; TestFlight and App Store builds carry no
/// profile and use production.
enum PushEnvironment {
    static func of(profile: Data?) -> String {
        guard let profile, let text = String(data: profile, encoding: .isoLatin1),
              let at = text.range(of: "<key>aps-environment</key>") else { return "production" }
        let rest = text[at.upperBound...].prefix(80)
        return rest.contains("<string>development</string>") ? "development" : "production"
    }
}

/// The APNs device token as gw3-phone wants it: lower-case hex.
enum PushToken {
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// the Apple team id from the build (Info.plist GW3Team = $(DEVELOPMENT_TEAM)), when it is one
    static func team(_ raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return t.count == 10 && t.unicodeScalars.allSatisfy(CharacterSet.ascii(plus: "").contains)
            && t == t.uppercased() ? t : nil
    }
}

/// POST /v1/push/register
struct PushRegistration: Codable, Equatable {
    var token: String
    var environment: String
    var device: String
    var team: String?
    /// true when the phone has no answer-only token (or lost it): the PC makes a new one
    var answer: Bool
}

struct PushStatus: Codable, Equatable {
    var on: Bool
    var text: String
    var phones: Int?
}

struct PushRegisterReply: Codable, Equatable {
    var ok: Bool
    var answerToken: String?
    var push: PushStatus?
}

/// The answer-only token and where it goes. It can only answer or dismiss a needs-you item (gw3-phone refuses it
/// everywhere else and drops it with its pairing), so it is kept readable after the first unlock: a notification's
/// button can then answer while the phone is locked, which is when the watch shows the notification. The pairing's
/// own token, which can read every chat and send anything, stays readable only while the phone is unlocked.
struct AnswerPass: Codable, Equatable {
    var baseURL: URL
    var token: String
}

#if canImport(Security)
enum AnswerPassStore {
    private static let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                              kSecAttrService as String: "app.gupworks3.phone.answer",
                                              kSecAttrAccount as String: "pc",
                                              kSecAttrSynchronizable as String: false]

    static func load() -> AnswerPass? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AnswerPass.self, from: data)
    }

    @discardableResult
    static func save(_ pass: AnswerPass) -> Bool {
        guard let data = try? JSONEncoder().encode(pass) else { return false }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
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
enum AnswerPassStore {
    private static var kept: AnswerPass?
    static func load() -> AnswerPass? { kept }
    @discardableResult
    static func save(_ pass: AnswerPass) -> Bool { kept = pass; return true }
    static func clear() { kept = nil }
}
#endif

/// Which token a notification's button answers with: the answer-only pass for this PC, else (an app from before
/// a233 that never registered, or a pass lost) the pairing's own token while it can be read (phone unlocked).
enum PushAnswerer {
    static func credentials(pass: AnswerPass?, pairing: Pairing?) -> (base: URL, token: String)? {
        if let pass, pairing == nil || pairing?.baseURL == pass.baseURL { return (pass.baseURL, pass.token) }
        if let pairing { return (pairing.baseURL, pairing.token) }
        return nil
    }
}

extension APIClient {
    /// POST /v1/push/register with the pairing's token
    func registerPush(_ p: Pairing, _ body: PushRegistration) async throws -> PushRegisterReply {
        try await request(p.baseURL, "/v1/push/register", token: p.token, method: "POST", encoding: body)
    }

    /// DELETE /v1/push/register: unpaired, so no more pushes to this phone
    func unregisterPush(_ p: Pairing) async throws {
        let _: PushRegisterReply = try await request(p.baseURL, "/v1/push/register", token: p.token, method: "DELETE")
    }

    /// GET /v1/push: is push on, in words (Settings)
    func pushStatus(_ p: Pairing) async throws -> PushStatus {
        try await request(p.baseURL, "/v1/push", token: p.token)
    }

    /// a notification's button: its one request, with whichever token `PushAnswerer` picked
    func perform(_ action: PushAction, base: URL, token: String) async throws {
        let _: NeedsReply = try await request(base, action.path, token: token, method: "POST", encoding: action.body)
    }
}
