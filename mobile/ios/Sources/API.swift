import Foundation

// What gw3-phone sends (tools/gw3_phone.py; the demo copies are in mobile/fixtures/).

struct Hello: Codable, Equatable {
    var app: String
    var version: String
    var api: Int
    var pc: String
    var features: [String]
}

struct PairReply: Codable {
    var token: String
    var pc: String
    var version: String
}

struct Home: Codable, Equatable {
    var now: Double
    var projects: [ProjectRow]
    var setups: [ChatRow]
    var chats: [ChatRow]
    var archivedCount: Int
    var projectsError: String?
}

struct ProjectRow: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var state: String      // needs | permission | working | paused | idle
    var detail: String
    var needs: Int
    var permission: Int
    var working: Int
    var paused: Bool
    var mainChatId: String?
}

struct ChatRow: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var state: String      // working | needs | permission | done | idle
    var model: String
    var provider: String
    var lastActive: Double // ms since 1970 on the PC's clock
    var pinned: Bool
    var running: Bool
}

enum APIError: Error, Equatable {
    case notPaired           // 401: the PC doesn't know this phone (anymore)
    case unreachable         // no answer: Tailscale off, PC asleep, service stopped
    case server(String)      // the PC answered with an error

    var message: String {
        switch self {
        case .notPaired: return "Your PC doesn't know this phone anymore. Pair again."
        case .unreachable:
            return "Can't reach your PC. Is Tailscale on? In the Tailscale app, also check that Use Tailscale DNS is on."
        case .server(let text): return text
        }
    }
}

/// Talks to gw3-phone: an ephemeral session (no cookies, cache or stored credentials), no redirects.
final class APIClient {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.waitsForConnectivity = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// `device` is the name the PC lists this phone under (`gw3-phone status`)
    func pair(_ link: PairLink, device: String) async throws -> Pairing {
        let body = ["code": link.code, "device": device]
        let reply: PairReply = try await request(link.baseURL, "/v1/pair", token: nil, method: "POST", body: body)
        return Pairing(baseURL: link.baseURL, token: reply.token, pairedAt: Date(), pcName: reply.pc)
    }

    func hello(_ p: Pairing) async throws -> Hello {
        try await request(p.baseURL, "/v1/hello", token: p.token)
    }

    func home(_ p: Pairing) async throws -> Home {
        try await request(p.baseURL, "/v1/home", token: p.token)
    }

    func chat(_ p: Pairing, _ id: String) async throws -> ChatHeader {
        try await request(p.baseURL, "/v1/chats/\(id)", token: p.token)
    }

    /// a page of turns, oldest first; `before` is the oldest turn the phone has
    func turns(_ p: Pairing, _ id: String, before: String? = nil, limit: Int = 30) async throws -> TurnsPage {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { q.append(URLQueryItem(name: "before", value: before)) }
        return try await request(p.baseURL, "/v1/chats/\(id)/turns", token: p.token, query: q)
    }

    func card(_ p: Pairing, chat: String, card: String) async throws -> CardDetail {
        try await request(p.baseURL, "/v1/chats/\(chat)/cards/\(card)", token: p.token)
    }

    /// A server-sent events stream (`/v1/home/events`, `/v1/chats/<id>/events`). Ends when the PC closes it; throws
    /// APIError like the other calls.
    func events(_ p: Pairing, _ path: String, query: [URLQueryItem] = []) -> AsyncThrowingStream<SSEEvent, Error> {
        let req = Self.makeRequest(p.baseURL, path, token: p.token, query: query, accept: "text/event-stream")
        let session = streamSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401 { throw APIError.notPaired }
                    guard status == 200 else { throw APIError.server("The PC answered \(status).") }
                    var parser = SSEParser()
                    for try await byte in bytes {
                        if let e = parser.feed(byte) { continuation.yield(e) }
                    }
                    continuation.finish()
                } catch let e as APIError {
                    continuation.finish(throwing: e)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() as Error : APIError.unreachable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams stay open for minutes; the PC sends a keepalive every 15 s, so a quiet 45 s means the line is dead.
    private let streamSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = 60 * 60 * 24
        c.waitsForConnectivity = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    private static func makeRequest(_ base: URL, _ path: String, token: String?, query: [URLQueryItem] = [],
                                    accept: String = "application/json") -> URLRequest {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.path = path
        c.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: c.url!)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return req
    }

    private func request<T: Decodable>(_ base: URL, _ path: String, token: String?, method: String = "GET",
                                       query: [URLQueryItem] = [], body: [String: String]? = nil) async throws -> T {
        var req = Self.makeRequest(base, path, token: token, query: query)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            if token == nil, let e = try? JSONDecoder().decode([String: String].self, from: data), let text = e["error"] {
                throw APIError.server(text)  // a wrong or expired pairing code
            }
            throw APIError.notPaired
        }
        guard status == 200 else {
            let text = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError.server(text ?? "The PC answered \(status).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.server("The PC sent something this app can't read. Update GupWorks on the PC or the app.")
        }
    }
}

/// One server-sent event: `event: <name>` and its `data:` lines.
struct SSEEvent: Equatable {
    var name: String
    var data: String
}

/// Reads an event stream byte by byte (AsyncBytes.lines drops the empty lines that end each event).
struct SSEParser {
    private var line: [UInt8] = []
    private var name = ""
    private var data: [String] = []

    mutating func feed(_ byte: UInt8) -> SSEEvent? {
        if byte == 13 { return nil }               // \r\n endings
        guard byte == 10 else { line.append(byte); return nil }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { name = ""; data = [] }
            return data.isEmpty ? nil : SSEEvent(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        if text.hasPrefix(":") { return nil }       // keepalive
        let field = text.prefix { $0 != ":" }
        var value = text.dropFirst(field.count).dropFirst()
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    mutating func feed(_ text: String) -> [SSEEvent] {
        text.utf8.compactMap { feed($0) }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The demo mode (`-demo` launch argument, used by the screenshot tests): answers from the bundled fixtures, with
/// the times moved so the recorded "now" is now.
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func load<T: Decodable>(_ name: String, in folder: String = "fixtures") -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: folder),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static var home: Home? {
        guard var h: Home = load("home") else { return nil }
        let shift = Date().timeIntervalSince1970 * 1000 - h.now
        h.now += shift
        h.chats = h.chats.map { var c = $0; c.lastActive += shift; return c }
        return h
    }

    static var pairing: Pairing {
        Pairing(baseURL: URL(string: "https://desktop.example.ts.net:10005")!, token: "demo",
                pairedAt: Date(timeIntervalSinceNow: -86_400 * 3), pcName: "desktop")
    }
}
