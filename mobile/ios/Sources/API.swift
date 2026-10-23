import Foundation
import UIKit

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
        case .unreachable: return "Can't reach your PC. Is Tailscale on?"
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

    func pair(_ link: PairLink) async throws -> Pairing {
        let body = ["code": link.code, "device": UIDevice.current.name]
        let reply: PairReply = try await request(link.baseURL, "/v1/pair", token: nil, method: "POST", body: body)
        return Pairing(baseURL: link.baseURL, token: reply.token, pairedAt: Date(), pcName: reply.pc)
    }

    func hello(_ p: Pairing) async throws -> Hello {
        try await request(p.baseURL, "/v1/hello", token: p.token)
    }

    func home(_ p: Pairing) async throws -> Home {
        try await request(p.baseURL, "/v1/home", token: p.token)
    }

    private func request<T: Decodable>(_ base: URL, _ path: String, token: String?, method: String = "GET",
                                       body: [String: String]? = nil) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
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

    static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "fixtures"),
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
